public without sharing class ProvisionKeyHandler extends ServiceHandler {

    private static final String SERVICE_TYPE = 'Provision_Key';

    public ProvisionKeyRequest request;
    public Id resolvedErrorId;
    public API_Key__c apiKeyToInsert;

    public class ProvisionKeyResponse {
        public String api_key;
        public String provisioned_at;
    }

    public ProvisionKeyHandler() {
        super('Provision_Key');
    }

    // Build the HMAC signature for the request body and service type, then send the request to the Provisioning API.
    public void provisionKey(Id opportunityId, Id errorId){
        this.request = new ProvisionKeyRequest(opportunityId);
        String HMACSignature = buildHMACSignature(JSON.serialize(request), 'Provision_Key');
        sendRequest('POST', 'callout:Provisioning_API', JSON.serialize(request), HMACSignature, errorId);
    }

    // Handle the successful response and insert the API key as a related record the opportunity. 
    // If the request was a retry, mark the error log as resolved.
    public override void handleSuccess(HttpResponse res, Id errorId) {
        ProvisionKeyResponse provisionResponse = (ProvisionKeyResponse)JSON.deserialize(res.getBody(), ProvisionKeyResponse.class);
        this.apiKeyToInsert = new API_Key__c(
            Opportunity__c = this.request.opportunityId,
            API_Key__c = provisionResponse.api_key,
            Provisioned_Date_Time__c = Datetime.valueOfGmt(provisionResponse.provisioned_at)
        );
        if (errorId != null) {
            this.resolvedErrorId = errorId;
        }
    }
}
