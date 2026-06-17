Account acc = [SELECT Id, Name FROM Account ORDER BY CreatedDate ASC LIMIT 1];

List<PricebookEntry> pbes = [
    SELECT Id, UnitPrice, Pricebook2Id
    FROM PricebookEntry
    WHERE Product2.Name LIKE 'YubiEnterprise Subscription%'
    AND Pricebook2Id = '01saj00000KWWndAAH'
    AND IsActive = true
];

if (pbes.isEmpty()) {
    System.debug('ERROR: No active YubiEnterprise Subscription products found in the standard pricebook.');
    return;
}

List<Opportunity> opps = new List<Opportunity>();
for (Integer i = 1; i <= 500; i++) {
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
insert opps;

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
insert items;

System.debug('Created 500 Prospecting opportunities for: ' + acc.Name);
