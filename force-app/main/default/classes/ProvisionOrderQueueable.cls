public without sharing class ProvisionOrderQueueable implements Queueable, Database.AllowsCallouts {

    public static final Integer CHUNK_SIZE = 90;

    public class ProvisionRequest {
        public String opportunityId;
        public String errorId;

        public ProvisionRequest(String opportunityId, String errorId) {
            this.opportunityId = opportunityId;
            this.errorId = errorId;
        }
    }

    private List<ProvisionRequest> requests;

    public ProvisionOrderQueueable(List<ProvisionRequest> requests) {
        this.requests = requests;
    }

    public void execute(QueueableContext context) {
        if (requests == null || requests.isEmpty()) return;

        List<API_Key__c> keysToInsert = new List<API_Key__c>();
        List<Integration_Error_Log__c> logsToResolve = new List<Integration_Error_Log__c>();

        Integer toProcess = Math.min(CHUNK_SIZE, requests.size());
        for (Integer i = 0; i < toProcess; i++) {
            ProvisionRequest request = requests[0];
            ProvisionOrderHandler handler = new ProvisionOrderHandler();
            try {
                handler.provisionOrder(request.opportunityId, request.errorId);

                if (handler.pendingApiKeyInsert != null) {
                    keysToInsert.add(handler.pendingApiKeyInsert);
                }
                if (handler.pendingResolvedErrorId != null) {
                    logsToResolve.add(new Integration_Error_Log__c(
                        Id = handler.pendingResolvedErrorId,
                        Resolved__c = true,
                        Retry_Eligible__c = false
                    ));
                }
                if (handler.pendingErrorLogs != null && !handler.pendingErrorLogs.isEmpty()) {
                    logsToResolve.addAll(handler.pendingErrorLogs);
                }
            } catch (Exception e) {
                logsToResolve.add(new Integration_Error_Log__c(
                    Type__c = 'Provision_Order',
                    Error_Message__c = e.getMessage(),
                    Resolved__c = false,
                    Retry_Eligible__c = false,
                    High_Priority__c = true
                ));
            }
            requests.remove(0);
        }

        if (!keysToInsert.isEmpty()) {
            Database.insert(keysToInsert, false, AccessLevel.SYSTEM_MODE);
        }
        if (!logsToResolve.isEmpty()) {
            Database.upsert(logsToResolve, false, AccessLevel.SYSTEM_MODE);
        }

        if (requests.size() > 0) {
            if (!Test.isRunningTest()) {
                System.enqueueJob(new ProvisionOrderQueueable(requests));
            }
        }
    }
}
