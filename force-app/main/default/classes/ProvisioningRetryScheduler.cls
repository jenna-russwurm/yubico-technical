public with sharing class ProvisioningRetryScheduler implements Schedulable {
    
    public static void scheduleRetry() {   
        System.schedule('Provisioning Retry :00', '0 0 * * * ?',  new ProvisioningRetryScheduler());
        System.schedule('Provisioning Retry :15', '0 15 * * * ?', new ProvisioningRetryScheduler());
        System.schedule('Provisioning Retry :30', '0 30 * * * ?', new ProvisioningRetryScheduler());
        System.schedule('Provisioning Retry :45', '0 45 * * * ?', new ProvisioningRetryScheduler());
    }

    public void execute(SchedulableContext sc) {
        List<Integration_Error_Log__c> errorsToRetry = [SELECT Request_Body__c, Retry_Attempts__c FROM Integration_Error_Log__c
                                                        WHERE Retry_Eligible__c = true AND Resolved__c = false
                                                        AND Type__c = 'Provision_Order' AND Retry_Attempts__c < 3
                                                        ORDER BY CreatedDate ASC];

        if(errorsToRetry.isEmpty()) return;

        List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>();
        for(Integration_Error_Log__c errorLog : errorsToRetry) {
            errorLog.Retry_Attempts__c = (errorLog.Retry_Attempts__c == null) ? 1 : errorLog.Retry_Attempts__c + 1;
            ProvisionOrderRequest request = (ProvisionOrderRequest)JSON.deserialize(errorLog.Request_Body__c, ProvisionOrderRequest.class);
            requests.add(new ProvisionOrderQueueable.ProvisionRequest(request.opportunityId, errorLog.Id));
        }

        System.enqueueJob(new ProvisionOrderQueueable(requests));
        update errorsToRetry;
    }
}