public virtual class ServiceHandler {

    public string serviceType;

    // Error logs accumulated during this handler's callouts. The CALLER is
    // responsible for upserting these AFTER all callouts in the transaction
    // have completed. Doing DML between callouts causes "uncommitted work
    // pending" on the next callout.
    public List<Integration_Error_Log__c> pendingErrorLogs = new List<Integration_Error_Log__c>();

    public ServiceHandler(string serviceType) {
        this.serviceType = serviceType;
    }

    public void sendRequest(string method, string endpoint, string payload, string signature, Id errorId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(payload);
        req.setTimeout(10000);
        if(signature != null) {
            req.setHeader('X-Secure-Signature', signature);
        }
        handleResponse(new Http().send(req), req, errorId);
    }

    public string handleResponse(HttpResponse res, httpRequest req, Id errorId) {
        Integer statusCode = res.getStatusCode();

        switch on statusCode {
            when 200 {
                this.handleSuccess(res, errorId);
            }
            when 429, 503 {
                this.handleRetryError(res, req, statusCode, errorId);
            }
            when else {
                this.handleFatalError(res, req, statusCode, errorId);
            }
        }
        return '';
    }

    public void handleRetryError(HttpResponse res, HttpRequest req, Integer statusCode, Id errorId) {
        Integration_Error_Log__c errorLog = logError(res, req, statusCode, errorId);
        errorLog.High_Priority__c = true;
        errorLog.Retry_Eligible__c = true;
        errorLog.Error_Message__c = statusCode == 429 ? 'Too Many Requests - retrying eligible' : 'Server Unavailable - retrying eligible';
        // Defer DML - caller will bulk-upsert pendingErrorLogs after all callouts.
        this.pendingErrorLogs.add(errorLog);
    }

    public void handleFatalError(HttpResponse res, HttpRequest req, Integer statusCode, Id errorId) {
        Integration_Error_Log__c errorLog = logError(res, req, statusCode, errorId);
        errorLog.High_Priority__c = true;
        errorLog.Retry_Eligible__c = false;
        errorLog.Error_Message__c = 'Non-retryable error - manual review required';
        // Defer DML - caller will bulk-upsert pendingErrorLogs after all callouts.
        this.pendingErrorLogs.add(errorLog);
    }

    public Integration_Error_Log__c logError(HttpResponse res, HttpRequest req, Integer statusCode, Id errorId) {
        Integration_Error_Log__c errorLog = errorId != null ? getErrorLog(errorId) : new Integration_Error_Log__c();
        errorLog.Endpoint__c = req.getEndpoint();
        errorLog.Type__c = this.serviceType;
        errorLog.Request_Body__c = req.getBody();
        errorLog.Status_Code__c = statusCode;
        errorLog.Response_Body__c = res.getBody();
        errorLog.Resolved__c = false;
        return errorLog;
    }

    public Integration_Error_Log__c getErrorLog(Id errorId) {
        return [SELECT Id FROM Integration_Error_Log__c WHERE Id = :errorId];
    }

    public string readHMACSecretKey(string keyName) {
        try{
            return (string)HMAC_Secret_Keys__mdt.getInstance(keyName).Key__c;
        } catch (Exception e) {
            throw new ServiceException('Error retrieving secret: ' + e.getMessage());
        }
    }

    public string buildHMACSignature(string payload, string keyName) {
        try {
            string secret = readHMACSecretKey(keyName);
            Blob mac = Crypto.generateMac('HMACSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
            return EncodingUtil.convertToHex(mac);
        } catch (Exception e) {
            throw new ServiceException('Error generating HMAC signature: ' + e.getMessage());
        }
    }

    protected virtual void handleSuccess(HttpResponse res, Id errorId) {}

    public class ServiceException extends Exception {}

}