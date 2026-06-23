public with sharing class ProvisioningRetryScheduler implements Schedulable {
    
    // Schedules the retry job to run every 15 minutes. This method can be called from an anonymous block or a setup script.
    public static void scheduleRetry() {   
        System.schedule('Provisioning Retry :00', '0 0 * * * ?',  new ProvisioningRetryScheduler());
        System.schedule('Provisioning Retry :15', '0 15 * * * ?', new ProvisioningRetryScheduler());
        System.schedule('Provisioning Retry :30', '0 30 * * * ?', new ProvisioningRetryScheduler());
        System.schedule('Provisioning Retry :45', '0 45 * * * ?', new ProvisioningRetryScheduler());
    }

    public void execute(SchedulableContext sc) {
        List<Integration_Error_Log__c> errorsToRetry = getRetryableErrors();

        if(errorsToRetry.isEmpty()) return;

        // Build a list of ProvisionKeyRequests from the retryable error logs and enqueue them in chunks for processing by the ProvisionKeyQueueable.
        // Only add the request for retry if the retry attempts are less than 3. 
        // If the retry attempts are 3 or more, mark the error log as high priority for manual review.
        List<ProvisionKeyRequest> requests = new List<ProvisionKeyRequest>();
        for(Integration_Error_Log__c errorLog : errorsToRetry) {
            errorLog.Retry_Attempts__c = (errorLog.Retry_Attempts__c == null) ? 1 : errorLog.Retry_Attempts__c + 1;
            if (errorLog.Retry_Attempts__c >= 3) errorLog.High_Priority__c = true;
            ProvisionKeyRequest request = (ProvisionKeyRequest)JSON.deserialize(errorLog.Request_Body__c, ProvisionKeyRequest.class);
            requests.add(new ProvisionKeyRequest(request.opportunityId, errorLog.Id));
        }

        ProvisionKeyQueueable.enqueueChunked(requests);
        database.update(errorsToRetry, false);
    }

    private List<Integration_Error_Log__c> getRetryableErrors() {
        return [SELECT Request_Body__c, Retry_Attempts__c, High_Priority__c FROM Integration_Error_Log__c
                WHERE Retry_Eligible__c = true AND Resolved__c = false
                AND Type__c = 'Provision_Key' AND Retry_Attempts__c < 3
                ORDER BY CreatedDate ASC];
    }
}