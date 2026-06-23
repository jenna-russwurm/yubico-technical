public class ProvisionKeyRequest {
    public Id opportunityId;
    public Id errorId;

    public ProvisionKeyRequest(Id opportunityId) {
        this.opportunityId = opportunityId;
    }

    public ProvisionKeyRequest(Id opportunityId, Id errorId) {
        this.opportunityId = opportunityId;
        this.errorId = errorId;
    }
}
