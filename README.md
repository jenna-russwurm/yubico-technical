<div align="center">

# Yubico — Secure Order Provisioning Engine

**Salesforce Technical Assignment &nbsp;·&nbsp; Jenna Russwurm &nbsp;·&nbsp; 2026**

**Org:** [wise-goat-s7tn8f-dev-ed.trailblaze.my.salesforce.com](https://wise-goat-s7tn8f-dev-ed.trailblaze.my.salesforce.com)

*An event-driven, bulk-safe provisioning system that issues API keys and tracks license inventory when an Opportunity is Closed Won. Built with platform events, asynchronous Queueable Apex, HMAC-SHA256 request signing, and an automated retry scheduler.*

</div>

---

## Architecture Overview

```
Opportunity (Closed Won)
    │
    ├── publishes ──► Provisioning_Event__e (2,000 records/batch, Automated Process user)
    │                       │
    │                       └── ProvisioningEvent trigger
    │                               └── ProvisioningEventTriggerHandler
    │                                       └── ProvisionKeyQueueable
    │                                               └── ProvisionKeyHandler ──► Mock Provisioning API
    │                                                       └── ServiceHandler (HMAC-SHA256 signing)
    │
    └── aggregate SOQL rollup ──► Account.Active_Licenses_Count__c
```

**Retry path:**
```
Integration_Error_Log__c (Retry_Eligible__c = true)
    └── ProvisioningRetryScheduler (every 15 min)
            └── ProvisionKeyQueueable
```

---

## Custom Metadata Types

Three custom metadata types drive the system's configuration and feature gating:

| Metadata Type | Purpose |
|---|---|
| `Trigger__mdt` | Controls enablement of triggers. Parent to Feature records. Acts as a kill switch at the trigger level. |
| `Feature__mdt` | Controls enablement of individual processes within a trigger. Allows selective disablement without touching code. |
| `HMAC_Secret_Keys__mdt` | Stores the HMAC secret keys used to generate the `X-Secure-Signature` header. Stored in metadata — not hardcoded — because Named Credential protected fields are not accessible in Apex at runtime. |

---

## Task 1 — Event-Driven Trigger & Account Rollup

**Trigger:** `Opportunity.trigger` → `OpportunityTriggerHandler`

- Fires on `after update`, filters only Closed Won transitions
- Publishes `Provisioning_Event__e` via `EventBus.publish()` — no synchronous callouts
- Feature-gated via `Trigger__mdt` / `Feature__mdt` — full kill switch available at both trigger and feature level

**Rollup:** `Active_Licenses_Count__c` on Account

- Aggregate SOQL (`SUM(Quantity)`) grouped by `AccountId`
- Bulk-safe: operates only on affected account IDs, single DML update — no record locking under 200+ records
- Feature-gated via `Rollup_Active_Account_Licenses`

> [!NOTE]
> **Assumption — Active Line Items:** An opportunity may contain a mix of license types as `OpportunityLineItem` records. "Active line items" are defined as those attached to a Closed Won Opportunity where `Start_Date__c <= TODAY` and `End_Date__c >= TODAY`. This accurately reflects currently active license coverage rather than counting all historical closed deals.

---

## Task 2 — Secure Callout & Retry

**Subscriber:** `ProvisioningEvent.trigger` → `ProvisioningEventTriggerHandler` → `ProvisionKeyQueueable`

**One API key per Opportunity** — when a deal is Closed Won, one provisioning request is made for the order regardless of how many line items it contains.

**Request signing (`ServiceHandler`):**
- HMAC-SHA256 signature computed via `Crypto.generateMac()`
- Secret key read from `HMAC_Secret_Keys__mdt` at runtime — never hardcoded
- A Named Credential stores the endpoint; `HMAC_Secret_Keys__mdt` stores the signing key, as Named Credential protected fields are not accessible in Apex
- Injected as `X-Secure-Signature` request header on every outbound request

**Mock endpoint:** A Salesforce Site was used to host `MockProvisioningAPI` as a publicly accessible REST endpoint, simulating real provisioning API behaviour including HMAC verification and randomised 429/503 responses.

**Failure handling:**

| Response | Behaviour |
|---|---|
| `200` | Inserts `API_Key__c`, marks error log resolved (if retry) |
| `429` / `503` | Creates `Integration_Error_Log__c` with `Retry_Eligible__c = true`, `High_Priority__c = false` |
| Other `4xx` / `5xx` | Creates non-retryable `High_Priority__c` error log requiring manual review |

**Retry scheduler (`ProvisioningRetryScheduler`):**
- Runs at `:00`, `:15`, `:30`, `:45` every hour
- A scheduled retry was chosen over immediate re-enqueue — 429 and 503 errors indicate the external system needs time to recover, so retrying immediately increases the chance of repeated failure
- Re-enqueues eligible errors with `Retry_Attempts__c < 3`; increments attempt count on each run
- On the 3rd (final) attempt, `High_Priority__c` is set to `true` — if the attempt fails, the log is already flagged for manual review

> [!TIP]
> `ServiceHandler` is built as a reusable base class. In a real implementation it could be extended to standardise callout behaviour and integration error logging across multiple integrations.

---

## Task 3 — Asynchronous Guardrails & Scalability

**Chunking (`ProvisionKeyQueueable`):**
- `CHUNK_SIZE = 90` — stays safely under the 100-callout-per-transaction governor limit while leaving padding before the ceiling
- `enqueueChunked()` static helper fans out parallel jobs — one per chunk
- Both `ProvisioningEventTriggerHandler` and `ProvisioningRetryScheduler` use `enqueueChunked()` as the single entry point
- `Provisioning_Event__e` is configured to process **2,000 records per batch**, running as the **Automated Process** user. At `CHUNK_SIZE = 90`, a full 2,000-record batch generates ~23 enqueued jobs — well under the 50 concurrent Queueable job limit

<details>
<summary><strong>Architectural Decision: Why Queueable?</strong></summary>

<br>

**vs. Batch Apex:** Batch is built for heavy data processing, scanning millions of records via SOQL. That's not what this integration does. It's callout-heavy, not query-heavy, and Batch's fixed `execute()` windows add unnecessary latency. Queueable fires the moment an event arrives, which is exactly what near-real-time provisioning needs.

**vs. Change Data Capture (CDC):** CDC is designed to stream record changes to external subscribers outside Salesforce. It doesn't replace the need for an internal async processor, so adding it here would just mean more infrastructure for no real benefit.

**Chunking:** Each Queueable job handles a pre-sized chunk of up to 90 requests. Chunks run in parallel, so chunk 2 doesn't wait on chunk 1. On high-volume spikes (e.g., 1,000 Closed Won deals at once), this keeps throughput high while staying within per-transaction callout and heap limits.

</details>

---

## Project Structure

```
force-app/main/default/
├── triggers/
│   ├── Opportunity.trigger                   # Closed Won → publish event + rollup
│   └── ProvisioningEvent.trigger             # Platform event subscriber
├── classes/
│   ├── TriggerHandler.cls                    # Base handler — checkTrigger() + checkFeature() kill switches
│   ├── OpportunityTriggerHandler.cls         # Event publish + account rollup
│   ├── ProvisioningEventTriggerHandler.cls   # Builds requests + calls enqueueChunked()
│   ├── ProvisionKeyQueueable.cls             # Chunked async processor (CHUNK_SIZE = 90)
│   ├── ProvisionKeyHandler.cls               # Per-request orchestration + success/error handling
│   ├── ProvisionKeyRequest.cls               # Request payload (opportunityId + errorId)
│   ├── ServiceHandler.cls                    # Reusable HTTP client + HMAC signing + error logging
│   ├── ProvisioningRetryScheduler.cls        # Scheduled retry job (every 15 min)
│   ├── MockProvisioningAPI.cls               # Salesforce Site-hosted mock endpoint (validates HMAC)
│   └── KeyProvisioning_Tests.cls             # Full test suite
scripts/apex/
├── seedOpportunities_create.apex             # Creates 1,000 seed Opportunities in Prospecting
└── seedOpportunities_closeWon.apex           # Flips seed Opportunities to Closed Won
```

---

## Load Test

To simulate a high-volume provisioning spike end-to-end:

**Step 1 — Seed 1,000 Opportunities**
```bash
sf apex run --file scripts/apex/seedOpportunities_create.apex
```
Creates 1,000 Opportunities in `Prospecting` stage, each with a random quantity of YubiEnterprise Subscription line items from the Standard Licenses pricebook.

**Step 2 — Flip to Closed Won**
```bash
sf apex run --file scripts/apex/seedOpportunities_closeWon.apex
```
Moves all seeded Opportunities to `Closed Won`, triggering the platform event publish and firing the full provisioning pipeline.

**Step 3 — Review results**

Open the org and navigate to the **Business Operations** tab to review:
- **Integration Error Logs** — any failed provisioning requests, retry status, and high-priority flags
- **Generated API Keys** — successfully provisioned `API_Key__c` records linked to their Opportunities
