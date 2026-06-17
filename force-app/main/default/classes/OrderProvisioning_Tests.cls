@isTest
private class OrderProvisioning_Tests {

    // ── Setup ─────────────────────────────────────────────────────────────────────

    @TestSetup
    static void setupTestData() {
        insert new Account(Name = 'Test Account');

        Product2 product = new Product2(Name = 'YubiEnterprise Subscription Test', IsActive = true);
        insert product;

        insert new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id   = product.Id,
            UnitPrice    = 100.00,
            IsActive     = true
        );
    }

    // ── HTTP Mocks ────────────────────────────────────────────────────────────────

    private class MockCallout implements HttpCalloutMock {
        private Integer statusCode;
        public MockCallout(Integer statusCode) { this.statusCode = statusCode; }
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(statusCode == 200
                ? '{"api_key":"yubi_mock_test1234567890ab","provisioned_at":"2026-06-17 00:00:00"}'
                : '{"error":"error"}');
            return res;
        }
    }

    // Validates the HMAC-SHA256 signature against the shared secret — mirrors what
    // MockProvisioningAPI does in production to confirm the full security chain works.
    private class MockCalloutValidateHMAC implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            String signature = req.getHeader('X-Secure-Signature');
            if (String.isBlank(signature)) {
                res.setStatusCode(401);
                res.setBody('{"error":"Missing signature"}');
                return res;
            }
            String secret = (String)HMAC_Secret_Keys__mdt.getInstance('Provision_Order').Key__c;
            Blob mac = Crypto.generateMac('HMACSHA256', Blob.valueOf(req.getBody()), Blob.valueOf(secret));
            if (EncodingUtil.convertToHex(mac) != signature) {
                res.setStatusCode(401);
                res.setBody('{"error":"Invalid signature"}');
                return res;
            }
            res.setStatusCode(200);
            res.setBody('{"api_key":"yubi_mock_test1234567890ab","provisioned_at":"2026-06-17 00:00:00"}');
            return res;
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────────

    private static Opportunity buildOpportunity(Id accountId) {
        return new Opportunity(
            Name          = 'Test Opportunity',
            AccountId     = accountId,
            StageName     = 'Prospecting',
            CloseDate     = Date.today().addDays(30),
            Pricebook2Id  = Test.getStandardPricebookId(),
            Start_Date__c = Date.today().addDays(-30),
            End_Date__c   = Date.today().addDays(60)
        );
    }

    private static PricebookEntry getPricebookEntry() {
        return [SELECT Id, UnitPrice FROM PricebookEntry WHERE Pricebook2Id = :Test.getStandardPricebookId() LIMIT 1];
    }

    // ── Task 1: Rollup ─────────────────────────────────────────────────────────────

    @isTest
    static void testRollupUpdatesOnClosedWon() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = getPricebookEntry();

        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;
        insert new OpportunityLineItem(OpportunityId = opp.Id, PricebookEntryId = pbe.Id, Quantity = 10, UnitPrice = pbe.UnitPrice);

        Test.startTest();
        opp.StageName = 'Closed Won';
        update opp;
        Test.stopTest();

        System.assertEquals(10, [SELECT Active_Licenses_Count__c FROM Account WHERE Id = :acc.Id].Active_Licenses_Count__c,
            'Active_Licenses_Count__c should reflect line item quantity after Closed Won');
    }

    @isTest
    static void testRollupExcludesExpiredLineItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = getPricebookEntry();

        Opportunity activeOpp = buildOpportunity(acc.Id);
        activeOpp.Name = 'Active Opp';

        Opportunity expiredOpp = buildOpportunity(acc.Id);
        expiredOpp.Name          = 'Expired Opp';
        expiredOpp.Start_Date__c = Date.today().addDays(-60);
        expiredOpp.End_Date__c   = Date.today().addDays(-1);

        insert new List<Opportunity>{ activeOpp, expiredOpp };
        insert new List<OpportunityLineItem>{
            new OpportunityLineItem(OpportunityId = activeOpp.Id,  PricebookEntryId = pbe.Id, Quantity = 20, UnitPrice = pbe.UnitPrice),
            new OpportunityLineItem(OpportunityId = expiredOpp.Id, PricebookEntryId = pbe.Id, Quantity = 50, UnitPrice = pbe.UnitPrice)
        };

        Test.startTest();
        activeOpp.StageName  = 'Closed Won';
        expiredOpp.StageName = 'Closed Won';
        update new List<Opportunity>{ activeOpp, expiredOpp };
        Test.stopTest();

        System.assertEquals(20, [SELECT Active_Licenses_Count__c FROM Account WHERE Id = :acc.Id].Active_Licenses_Count__c,
            'Expired line items should not count toward Active_Licenses_Count__c');
    }

    @isTest
    static void testRollupDoesNotFireForNonClosedWonTransition() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        Test.startTest();
        opp.StageName = 'Qualification';
        update opp;
        Test.stopTest();

        System.assertEquals(null, [SELECT Active_Licenses_Count__c FROM Account WHERE Id = :acc.Id].Active_Licenses_Count__c,
            'Rollup should not fire when stage does not transition to Closed Won');
    }

    // ── Task 2: HMAC Signature ─────────────────────────────────────────────────────

    @isTest
    static void testHMACSignatureIsCorrect() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>{
            new ProvisionOrderQueueable.ProvisionRequest(opp.Id, null)
        };

        // This mock rejects missing or incorrect HMAC signatures with 401.
        // A successful API key creation proves the signature was computed correctly.
        Test.setMock(HttpCalloutMock.class, new MockCalloutValidateHMAC());
        Test.startTest();
        System.enqueueJob(new ProvisionOrderQueueable(requests));
        Test.stopTest();

        System.assertEquals(1, [SELECT Id FROM API_Key__c WHERE Opportunity__c = :opp.Id].size(),
            'Valid HMAC signature should result in a successful provisioning');
        System.assertEquals(0, [SELECT Id FROM Integration_Error_Log__c].size(),
            'No error logs should be created when HMAC is valid');
    }

    // ── Task 2: Success / Error Handling ──────────────────────────────────────────

    @isTest
    static void testSuccessCreatesApiKey() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>{
            new ProvisionOrderQueueable.ProvisionRequest(opp.Id, null)
        };

        Test.setMock(HttpCalloutMock.class, new MockCallout(200));
        Test.startTest();
        System.enqueueJob(new ProvisionOrderQueueable(requests));
        Test.stopTest();

        List<API_Key__c> keys = [SELECT API_Key__c, Provisioned_Date_Time__c FROM API_Key__c WHERE Opportunity__c = :opp.Id];
        System.assertEquals(1, keys.size(), 'One API_Key__c record should be created on success');
        System.assertNotEquals(null, keys[0].API_Key__c, 'API key value should be populated');
        System.assertNotEquals(null, keys[0].Provisioned_Date_Time__c, 'Provisioned timestamp should be populated');
        System.assertEquals(0, [SELECT Id FROM Integration_Error_Log__c].size(), 'No error logs should be created on success');
    }

    @isTest
    static void test429CreatesRetryEligibleLog() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>{
            new ProvisionOrderQueueable.ProvisionRequest(opp.Id, null)
        };

        Test.setMock(HttpCalloutMock.class, new MockCallout(429));
        Test.startTest();
        System.enqueueJob(new ProvisionOrderQueueable(requests));
        Test.stopTest();

        List<Integration_Error_Log__c> logs = [SELECT Retry_Eligible__c, High_Priority__c, Resolved__c, Request_Body__c, Status_Code__c FROM Integration_Error_Log__c];
        System.assertEquals(1, logs.size(), 'One error log should be created for 429');
        System.assertEquals(true, logs[0].Retry_Eligible__c, 'Log should be retry eligible');
        System.assertEquals(true, logs[0].High_Priority__c, 'Log should be high priority');
        System.assertEquals(false, logs[0].Resolved__c, 'Log should be unresolved');
        System.assertEquals(429, (Integer)logs[0].Status_Code__c, 'Status code should be recorded');

        ProvisionOrderRequest retryReq = (ProvisionOrderRequest)JSON.deserialize(logs[0].Request_Body__c, ProvisionOrderRequest.class);
        System.assertEquals(opp.Id, retryReq.opportunityId, 'Request_Body__c should contain the Opportunity ID for retry deserialization');
    }

    @isTest
    static void test503CreatesRetryEligibleLog() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>{
            new ProvisionOrderQueueable.ProvisionRequest(opp.Id, null)
        };

        Test.setMock(HttpCalloutMock.class, new MockCallout(503));
        Test.startTest();
        System.enqueueJob(new ProvisionOrderQueueable(requests));
        Test.stopTest();

        List<Integration_Error_Log__c> logs = [SELECT Retry_Eligible__c, Status_Code__c FROM Integration_Error_Log__c];
        System.assertEquals(1, logs.size(), 'One error log should be created for 503');
        System.assertEquals(true, logs[0].Retry_Eligible__c, '503 should be retry eligible');
        System.assertEquals(503, (Integer)logs[0].Status_Code__c);
    }

    @isTest
    static void testFatalErrorCreatesNonRetryableLog() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>{
            new ProvisionOrderQueueable.ProvisionRequest(opp.Id, null)
        };

        Test.setMock(HttpCalloutMock.class, new MockCallout(500));
        Test.startTest();
        System.enqueueJob(new ProvisionOrderQueueable(requests));
        Test.stopTest();

        List<Integration_Error_Log__c> logs = [SELECT Retry_Eligible__c, High_Priority__c, Status_Code__c FROM Integration_Error_Log__c];
        System.assertEquals(1, logs.size(), 'One error log should be created for fatal errors');
        System.assertEquals(false, logs[0].Retry_Eligible__c, 'Fatal errors should not be retry eligible');
        System.assertEquals(true, logs[0].High_Priority__c, 'Fatal errors should be high priority');
        System.assertEquals(500, (Integer)logs[0].Status_Code__c);
    }

    // ── Retry Scheduler ───────────────────────────────────────────────────────────

    @isTest
    static void testRetrySchedulerResolvesLogOnSuccess() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Type__c          = 'Provision_Order',
            Error_Message__c = 'Too Many Requests',
            Request_Body__c  = JSON.serialize(new ProvisionOrderRequest(opp.Id)),
            Retry_Eligible__c = true,
            Resolved__c       = false,
            Retry_Attempts__c = 0,
            High_Priority__c  = true
        );
        insert errorLog;

        Test.setMock(HttpCalloutMock.class, new MockCallout(200));
        Test.startTest();
        new ProvisioningRetryScheduler().execute(null);
        Test.stopTest();

        Integration_Error_Log__c updated = [SELECT Retry_Attempts__c, Resolved__c, Retry_Eligible__c FROM Integration_Error_Log__c WHERE Id = :errorLog.Id];
        System.assertEquals(1, updated.Retry_Attempts__c, 'Retry_Attempts__c should be incremented');
        System.assertEquals(true, updated.Resolved__c, 'Log should be resolved after successful retry');
        System.assertEquals(false, updated.Retry_Eligible__c, 'Log should no longer be retry eligible');
        System.assertEquals(1, [SELECT Id FROM API_Key__c WHERE Opportunity__c = :opp.Id].size(), 'API key should be created on retry success');
    }

    @isTest
    static void testRetrySchedulerRespectsMaxAttempts() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        insert new Integration_Error_Log__c(
            Type__c           = 'Provision_Order',
            Request_Body__c   = JSON.serialize(new ProvisionOrderRequest(opp.Id)),
            Retry_Eligible__c = true,
            Resolved__c       = false,
            Retry_Attempts__c = 3
        );

        Test.setMock(HttpCalloutMock.class, new MockCallout(200));
        Test.startTest();
        new ProvisioningRetryScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT Id FROM API_Key__c].size(),
            'No provisioning should occur when retry cap of 3 is reached');
    }

    @isTest
    static void testRetrySchedulerSkipsResolvedLogs() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Opportunity opp = buildOpportunity(acc.Id);
        insert opp;

        insert new Integration_Error_Log__c(
            Type__c           = 'Provision_Order',
            Request_Body__c   = JSON.serialize(new ProvisionOrderRequest(opp.Id)),
            Retry_Eligible__c = true,
            Resolved__c       = true,
            Retry_Attempts__c = 1
        );

        Test.setMock(HttpCalloutMock.class, new MockCallout(200));
        Test.startTest();
        new ProvisioningRetryScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(0, [SELECT Id FROM API_Key__c].size(), 'Already resolved logs should not be reprocessed');
    }

    // ── Task 3: Chunking ──────────────────────────────────────────────────────────

    @isTest
    static void testQueueableProcessesMultipleRequestsInOneChunk() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 5; i++) {
            Opportunity o = buildOpportunity(acc.Id);
            o.Name = 'Bulk Opp ' + i;
            opps.add(o);
        }
        insert opps;

        List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>();
        for (Opportunity o : opps) {
            requests.add(new ProvisionOrderQueueable.ProvisionRequest(o.Id, null));
        }

        Test.setMock(HttpCalloutMock.class, new MockCallout(200));
        Test.startTest();
        System.enqueueJob(new ProvisionOrderQueueable(requests));
        Test.stopTest();

        System.assertEquals(5, [SELECT Id FROM API_Key__c].size(), 'All 5 requests should be provisioned in a single chunk');
    }

    // ── End-to-End ────────────────────────────────────────────────────────────────

    @isTest
    static void testEndToEnd() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        PricebookEntry pbe = getPricebookEntry();

        // Step 1: Create opportunity in Prospecting
        Opportunity opp = new Opportunity(
            Name         = 'E2E Opportunity',
            AccountId    = acc.Id,
            StageName    = 'Prospecting',
            CloseDate    = Date.today().addDays(30),
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert opp;

        // Step 2: Add YubiEnterprise Subscription line item
        insert new OpportunityLineItem(
            OpportunityId    = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 25,
            UnitPrice        = pbe.UnitPrice
        );

        // Step 3: Set contract dates
        opp.Start_Date__c = Date.today().addDays(-30);
        opp.End_Date__c   = Date.today().addDays(60);
        update opp;

        Test.setMock(HttpCalloutMock.class, new MockCallout(200));
        Test.startTest();

        // Step 4: Move to Closed Won — fires rollup synchronously and publishes Provisioning_Event__e
        opp.StageName = 'Closed Won';
        update opp;

        // Platform events are not delivered synchronously in unit tests, so we invoke
        // the queueable directly to simulate what ProvisioningEventTriggerHandler would do.
        System.enqueueJob(new ProvisionOrderQueueable(new List<ProvisionOrderQueueable.ProvisionRequest>{
            new ProvisionOrderQueueable.ProvisionRequest(opp.Id, null)
        }));

        Test.stopTest();

        // Step 5: Verify rollup updated Account
        System.assertEquals(25, [SELECT Active_Licenses_Count__c FROM Account WHERE Id = :acc.Id].Active_Licenses_Count__c,
            'Active_Licenses_Count__c should equal the line item quantity');

        // Step 6: Verify API key record was created
        List<API_Key__c> keys = [SELECT API_Key__c, Provisioned_Date_Time__c FROM API_Key__c WHERE Opportunity__c = :opp.Id];
        System.assertEquals(1, keys.size(), 'One API_Key__c should be created');
        System.assert(keys[0].API_Key__c.startsWith('yubi_mock_'), 'API key should match mock format');
        System.assertNotEquals(null, keys[0].Provisioned_Date_Time__c, 'Provisioned timestamp should be set');

        // Step 7: No unresolved error logs
        System.assertEquals(0, [SELECT Id FROM Integration_Error_Log__c WHERE Resolved__c = false].size(),
            'No unresolved error logs should exist after successful end-to-end provisioning');
    }
}
