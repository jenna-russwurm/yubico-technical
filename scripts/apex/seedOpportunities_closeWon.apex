/*  Script to flip the generated set of seed opportunities for testing purposes. 
    This script moves all opportunities in the "Prospecting" stage to the "Closed Won" stage.
*/

List<Opportunity> opps = [
    SELECT StageName
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
database.update(opps);

System.debug('Moved ' + opps.size() + ' opportunities to Closed Won.');
