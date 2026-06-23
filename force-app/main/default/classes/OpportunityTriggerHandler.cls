public without sharing class OpportunityTriggerHandler extends TriggerHandler {

    public OpportunityTriggerHandler() {
        super('Opportunity');
    }

    public override void afterUpdate(){
        if(checkFeature('Rollup_Active_Account_Licenses')) {
            rollUpActiveAccountLicenses();
        }
        if(checkFeature('Opportunity_Key_Provisioning')) {
            provisionKeys();
        }
    }

    private void provisionKeys() {
        List<Provisioning_Event__e> opportunitiesToProvision = new List<Provisioning_Event__e>();
        List<Opportunity> closedWonOpportunities = filterClosedWonOpportunities(Trigger.new, Trigger.old);

        for(Opportunity opportunity : closedWonOpportunities) {
            opportunitiesToProvision.add(new Provisioning_Event__e(
                Opportunity_Id__c = opportunity.Id
            ));
        }

        // Publish any opportunities flipped to "Closed Won" as a Provisioning_Event__e to handle outside of 
        // the transaction context. This allows for the callout to the provisioning API to be made asynchronously 
        // and avoids hitting governor limits.
            EventBus.publish(opportunitiesToProvision);
        }

    private void rollUpActiveAccountLicenses() {
        List<Opportunity> closedWonOpportunities = filterClosedWonOpportunities(Trigger.new, Trigger.old);
        if (closedWonOpportunities.isEmpty()) return;

        Map<Id, Account> accountsToUpdateMap = new Map<Id, Account>();
        for(Opportunity opportunity : closedWonOpportunities) {
            // Easy way to collect account IDs and initialize the map with zero values for active licenses. We'll update these values in the next step.
            accountsToUpdateMap.put(opportunity.AccountId, new Account(Id = opportunity.AccountId, Active_Licenses_Count__c = 0));
        }

        for(AggregateResult result : [  SELECT SUM(Quantity) activeLicenses, Opportunity.AccountId accountId
                                        FROM OpportunityLineItem
                                        WHERE Opportunity.AccountId IN :accountsToUpdateMap.keySet()
                                        AND Opportunity.Start_Date__c <= TODAY AND Opportunity.End_Date__c >= TODAY
                                        AND Opportunity.StageName = 'Closed Won'
                                        GROUP BY Opportunity.AccountId]) {
            accountsToUpdateMap.put((Id)result.get('accountId'), new Account(Id = (Id)result.get('accountId'), Active_Licenses_Count__c = (Decimal)result.get('activeLicenses')));
        }

        if(!accountsToUpdateMap.isEmpty()) {
            database.update(accountsToUpdateMap.values());
        }
    }

    // Filters the list of new and old opportunities to return only those that have changed to the "Closed Won" stage.
    private static List<Opportunity> filterClosedWonOpportunities(List<Opportunity> newList, List<Opportunity> oldList) {
        List<Opportunity> closedWon = new List<Opportunity>();
        for(Integer i = 0, size = newList.size(); i < size; i++) {
            if(newList[i].get('StageName') == 'Closed Won' && oldList[i].get('StageName') != 'Closed Won') {
                closedWon.add(newList[i]);
            }
        }
        return closedWon;
    }
}
