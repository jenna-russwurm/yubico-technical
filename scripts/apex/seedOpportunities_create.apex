/*  Script to generate a set of seed opportunities for testing purposes. 
    This script creates x opportunities in the "Prospecting" stage, each with a random quantity of YubiEnterprise Subscription 
    products from the Standard Licenses pricebook. 
*/

Integer OPPORTUNITY_COUNT = 1000;
String PRICEBOOK_NAME = 'Standard Licenses';

Account acc = [SELECT Id, Name FROM Account ORDER BY CreatedDate ASC LIMIT 1];
List<PricebookEntry> pbes = [
    SELECT UnitPrice, Pricebook2Id
    FROM PricebookEntry
    WHERE Product2.Name LIKE 'YubiEnterprise Subscription%'
    AND Pricebook2.Name = :PRICEBOOK_NAME 
    AND Pricebook2.IsActive = true
    AND IsActive = true
];

if (pbes.isEmpty()) {
    System.debug('ERROR: No active YubiEnterprise Subscription products found in the standard pricebook.');
    return;
}

List<Opportunity> opps = new List<Opportunity>();
for (Integer i = 1; i <= OPPORTUNITY_COUNT; i++) {
    opps.add(new Opportunity(
        Name         = 'Seed Opportunity ' + i,
        AccountId    = acc.Id,
        StageName    = 'Prospecting',
        Start_Date__c    = Date.today().addDays(-30),
        End_Date__c      = Date.today().addDays(60),
        CloseDate    = Date.today().addDays(30),
        Pricebook2Id = pbes[0].Pricebook2Id
    ));
}
database.insert(opps);

List<OpportunityLineItem> items = new List<OpportunityLineItem>();
for (Integer i = 0; i < opps.size(); i++) {
    PricebookEntry pbe = pbes[Math.mod(Math.abs(Crypto.getRandomInteger()), pbes.size())];
    Integer qty = 10 + Math.mod(Math.abs(Crypto.getRandomInteger()), 41);
    items.add(new OpportunityLineItem(
        OpportunityId    = opps[i].Id,
        PricebookEntryId = pbe.Id,
        Quantity         = qty,
        UnitPrice        = pbe.UnitPrice
    ));
}
database.insert(items);

System.debug('Created ' + OPPORTUNITY_COUNT + ' Prospecting opportunities for: ' + acc.Name);
