@RestResource(urlMapping='/mock-provisioning/issue-api-key')
global class MockProvisioningAPI {

    @HttpPost
    global static void issueKey() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String signature = req.headers.get('X-Secure-Signature');
        if (String.isBlank(signature)) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"error": "Missing signature"}');
            return;
        }

        String secret = (String)HMAC_Secret_Keys__mdt.getInstance('Provision_Order').Key__c;
        String body = req.requestBody.toString();
        Blob expectedMac = Crypto.generateMac('HMACSHA256', Blob.valueOf(body), Blob.valueOf(secret));
        String expectedSignature = EncodingUtil.convertToHex(expectedMac);

        if (signature != expectedSignature) {
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('{"error": "Invalid signature"}');
            return;
        }

        Integer roll = Math.mod(Math.abs(Crypto.getRandomInteger()), 5);
        if (roll == 0) {
            res.statusCode = 429;
            res.responseBody = Blob.valueOf('{"error": "Too Many Requests"}');
            return;
        }

        roll = Math.mod(Math.abs(Crypto.getRandomInteger()), 5);
        if (roll == 0) {
            res.statusCode = 503;
            res.responseBody = Blob.valueOf('{"error": "server is temporarily busy or undergoing maintenance"}');
            return;
        }

        String mockKey = 'yubi_mock_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 16);

        res.statusCode = 200;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, String>{
            'api_key' => mockKey,
            'provisioned_at' => DateTime.now().formatGmt('yyyy-MM-dd HH:mm:ss')
        }));
    }
}
