public without sharing class ProvisionKeyQueueable implements Queueable, Database.AllowsCallouts {

    // Under the assumption that the API can handle 100 requests at a time, 
    // we will chunk the requests into batches of 90 to be safe.
    public static final Integer CHUNK_SIZE = 90;

    private List<ProvisionKeyRequest> requests;

    public ProvisionKeyQueueable(List<ProvisionKeyRequest> requests) {
        this.requests = requests;
    }

    // Re-usable method for enqueuing a list of ProvisionKeyRequests in chunks of CHUNK_SIZE. 
    // This is useful for both the trigger and the retry scheduler.
    public static void enqueueChunked(List<ProvisionKeyRequest> requests) {
        for (Integer i = 0; i < requests.size(); i += CHUNK_SIZE) {
            List<ProvisionKeyRequest> chunk = new List<ProvisionKeyRequest>();
            Integer chunkEnd = Math.min(i + CHUNK_SIZE, requests.size());
            for (Integer j = i; j < chunkEnd; j++) {
                chunk.add(requests[j]);
            }
            System.enqueueJob(new ProvisionKeyQueueable(chunk));
        }
    }

    public void execute(QueueableContext context) {
        if (requests == null || requests.isEmpty()) return;

        List<API_Key__c> keysToInsert = new List<API_Key__c>();
        List<Integration_Error_Log__c> logsToResolve = new List<Integration_Error_Log__c>();

        // Pre-query all error logs for retry requests in a single SOQL call to avoid N+1 queries inside the callout loop.
        Set<Id> errorIds = new Set<Id>();
        for (ProvisionKeyRequest req : requests) {
            if (req.errorId != null) errorIds.add(req.errorId);
        }
        Map<Id, Integration_Error_Log__c> errorLogCache = errorIds.isEmpty()
            ? new Map<Id, Integration_Error_Log__c>()
            : new Map<Id, Integration_Error_Log__c>([SELECT Id FROM Integration_Error_Log__c WHERE Id IN :errorIds]);

        // Makes a callout per provisioning request assuming the end-point can only handle one request at a time.
        // If the end-point can handle multiple requests, this can be optimized to make a single callout with all requests in the chunk.
        for (ProvisionKeyRequest request : requests) {
            ProvisionKeyHandler handler = new ProvisionKeyHandler();
            handler.cachedErrorLogs = errorLogCache;
            try {
                // Execute api key provisioning request
                handler.provisionKey(request.opportunityId, request.errorId);

                // If successful, add the API key to the list of keys to insert and mark the error log as resolved
                if (handler.apiKeyToInsert != null) {
                    keysToInsert.add(handler.apiKeyToInsert);
                }
                // If successful & error log exists, mark the error log as resolved
                if (handler.resolvedErrorId != null) {
                    logsToResolve.add(new Integration_Error_Log__c(
                        Id = handler.resolvedErrorId,
                        Resolved__c = true,
                        Retry_Eligible__c = false
                    ));
                }
                if (handler.errorLogs != null && !handler.errorLogs.isEmpty()) {
                    logsToResolve.addAll(handler.errorLogs);
                }
            } catch (Exception e) {
                logsToResolve.add(new Integration_Error_Log__c(
                    Type__c = 'Provision_Key',
                    Error_Message__c = e.getMessage(),
                    Resolved__c = false,
                    Retry_Eligible__c = false,
                    High_Priority__c = true
                ));
            }
        }

        // Insert all successfully provisioned API keys and upsert all resolved error logs in bulk to avoid hitting governor limits.
        if (!keysToInsert.isEmpty()) {
            Database.insert(keysToInsert, false, AccessLevel.SYSTEM_MODE);
        }
        if (!logsToResolve.isEmpty()) {
            Database.upsert(logsToResolve, false, AccessLevel.SYSTEM_MODE);
        }
    }
}
