public virtual class ServiceHandler {

    public string serviceType;

    // Error logs accumulated during this handler's callouts. The CALLER is
    // responsible for upserting these AFTER all callouts in the transaction
    // have completed. Doing DML between callouts causes "uncommitted work
    // pending" on the next callout.
    public List<Integration_Error_Log__c> errorLogs = new List<Integration_Error_Log__c>();
    // Pre-populated by ProvisionKeyQueueable before the callout loop to avoid N+1 SOQL queries on retry paths.
    public Map<Id, Integration_Error_Log__c> cachedErrorLogs = new Map<Id, Integration_Error_Log__c>();

    public ServiceHandler(string serviceType) {
        this.serviceType = serviceType;
    }

    // re-usable method to send an HTTP request to the specified endpoint with the given payload and signature. The caller is responsible for handling the response and any errors that may occur.
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
                // successful response, do nothing.
                this.handleSuccess(res, errorId);
            }
                // retryable errors (429 Too Many Requests, 503 Service Unavailable) are logged and retried by the ProvisioningRetryScheduler.
            when 429, 503 {
                this.handleRetryError(res, req, statusCode, errorId);
            }
            when else {
                // fatal errors (400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 500 Internal Server Error) are logged and require manual review.
                this.handleFatalError(res, req, statusCode, errorId);
            }
        }
        return '';
    }

    // Handles a retryable error response. Retryables errors are retried 3x by the ProvisioningRetryScheduler. Can be overridden by subclasses to implement custom behavior.
    public void handleRetryError(HttpResponse res, HttpRequest req, Integer statusCode, Id errorId) {
        Integration_Error_Log__c errorLog = logError(res, req, statusCode, errorId);
        errorLog.High_Priority__c = false;
        errorLog.Retry_Eligible__c = true;
        errorLog.Error_Message__c = statusCode == 429 ? 'Too Many Requests - retrying eligible' : 'Server Unavailable - retrying eligible';
        // Defer DML - caller will bulk-upsert errorLogs after all callouts.
        this.errorLogs.add(errorLog);
    }

    // Handles a fatal error response. Fatal errors are not retried and require manual review. Can be overridden by subclasses to implement custom behavior.
    public void handleFatalError(HttpResponse res, HttpRequest req, Integer statusCode, Id errorId) {
        Integration_Error_Log__c errorLog = logError(res, req, statusCode, errorId);
        errorLog.High_Priority__c = true;
        errorLog.Retry_Eligible__c = false;
        errorLog.Error_Message__c = 'Non-retryable error - manual review required';
        // Defer DML - caller will bulk-upsert errorLogs after all callouts.
        this.errorLogs.add(errorLog);
    }

    // Creates the Integration_Error_Log__c base record for a failed callout. The caller is responsible for upserting the record after all callouts in the transaction have completed.
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
        if (cachedErrorLogs.containsKey(errorId)) return cachedErrorLogs.get(errorId);
        return [SELECT Id FROM Integration_Error_Log__c WHERE Id = :errorId];
    }

    // Read the HMAC secret key from the custom metadata type. Throws a ServiceException if the key cannot be retrieved.
    public string readHMACSecretKey(string keyName) {
        try{
            return (string)HMAC_Secret_Keys__mdt.getInstance(keyName).Key__c;
        } catch (Exception e) {
            throw new ServiceException('Error retrieving secret: ' + e.getMessage());
        }
    }

    // Builds an HMAC signature using the specified payload and secret key. Throws a ServiceException if the signature cannot be generated.
    public string buildHMACSignature(string payload, string keyName) {
        try {
            string secret = readHMACSecretKey(keyName);
            Blob mac = Crypto.generateMac('HMACSHA256', Blob.valueOf(payload), Blob.valueOf(secret));
            return EncodingUtil.convertToHex(mac);
        } catch (Exception e) {
            throw new ServiceException('Error generating HMAC signature: ' + e.getMessage());
        }
    }

    // Handles a successful HTTP response. Can be overridden by subclasses to implement custom behavior.
    protected virtual void handleSuccess(HttpResponse res, Id errorId) {}

    public class ServiceException extends Exception {}

}