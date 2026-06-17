List<Opportunity> opps = [
    SELECT Id, StageName
    FROM Opportunity
    WHERE Name LIKE 'Seed Opportunity %'
    AND StageName = 'Prospecting'
    ORDER BY CreatedDate ASC
];

if (opps.isEmpty()) {
    System.debug('No Prospecting seed opportunities found. Run seedOpportunities_create.apex first.');
    return;
}

for (Opportunity opp : opps) {
    opp.StageName = 'Closed Won';
}
update opps;

System.debug('Moved ' + opps.size() + ' opportunities to Closed Won.');
