public without sharing class ProvisioningEventTriggerHandler extends TriggerHandler {

    public ProvisioningEventTriggerHandler() {
        super('Provisioning_Event_e');
    }

    public override void afterInsert() {
        if(checkFeature('Opportunity_Order_Provisioning')) {
            List<ProvisionOrderQueueable.ProvisionRequest> requests = new List<ProvisionOrderQueueable.ProvisionRequest>();
            for(Integer i = 0; i < Trigger.new.size(); i++) {
                requests.add(new ProvisionOrderQueueable.ProvisionRequest((String)Trigger.new[i].get('Opportunity_Id__c'), null));
            }
            for (Integer i = 0; i < requests.size(); i += ProvisionOrderQueueable.CHUNK_SIZE) {
                List<ProvisionOrderQueueable.ProvisionRequest> chunk = new List<ProvisionOrderQueueable.ProvisionRequest>();
                Integer chunkEnd = Math.min(i + ProvisionOrderQueueable.CHUNK_SIZE, requests.size());
                for (Integer j = i; j < chunkEnd; j++) {
                    chunk.add(requests[j]);
                }
                System.enqueueJob(new ProvisionOrderQueueable(chunk));
            }
        }
    }
}
