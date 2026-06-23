public without sharing class ProvisioningEventTriggerHandler extends TriggerHandler {

    public ProvisioningEventTriggerHandler() {
        super('Provisioning_Event_e');
    }

    // Create the ProvisionKeyRequests and then enqueue them in chunks of 90 records for processing by the ProvisionKeyQueueable.
    public override void afterInsert() {
        List<ProvisionKeyRequest> requests = new List<ProvisionKeyRequest>();
        for(Integer i = 0; i < Trigger.new.size(); i++) {
            requests.add(new ProvisionKeyRequest((String)Trigger.new[i].get('Opportunity_Id__c'), null));
        }
        ProvisionKeyQueueable.enqueueChunked(requests);
    }
}
