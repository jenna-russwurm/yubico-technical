public without sharing class ProvisionOrderHandler extends ServiceHandler {

    public ProvisionOrderRequest request;
    public Id pendingResolvedErrorId;
    public API_Key__c pendingApiKeyInsert;

    public class ProvisionOrderResponse {
        public String api_key;
        public String provisioned_at;
    }

    public ProvisionOrderHandler() {
        super('Provision_Order');
    }

    public void provisionOrder(Id opportunityId, Id errorId){
        this.request = new ProvisionOrderRequest(opportunityId);
        String HMACSignature = buildHMACSignature(JSON.serialize(request), 'Provision_Order');
        sendRequest('POST', 'callout:Provisioning_API', JSON.serialize(request), HMACSignature, errorId);
    }

    public override void handleSuccess(HttpResponse res, Id errorId) {
        ProvisionOrderResponse provisionResponse = (ProvisionOrderResponse)JSON.deserialize(res.getBody(), ProvisionOrderResponse.class);
        this.pendingApiKeyInsert = new API_Key__c(
            Opportunity__c = this.request.opportunityId,
            API_Key__c = provisionResponse.api_key,
            Provisioned_Date_Time__c = Datetime.valueOfGmt(provisionResponse.provisioned_at)
        );
        if (errorId != null) {
            this.pendingResolvedErrorId = errorId;
        }
    }

}
