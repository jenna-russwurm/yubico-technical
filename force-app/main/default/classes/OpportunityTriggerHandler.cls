public without sharing class OpportunityTriggerHandler extends TriggerHandler {

    public OpportunityTriggerHandler() {
        super('Opportunity');
    }

    public override void afterUpdate(){
        if(checkFeature('Rollup_Active_Account_Licenses')) {
            rollUpActiveAccountLicenses();
        }
        if(checkFeature('Opportunity_Order_Provisioning')) {
            provisionOrders();
        }
    }

    private void provisionOrders() {
        List<Provisioning_Event__e> opportunitiesToProvision = new List<Provisioning_Event__e>();
        List<Opportunity> closedWonOpportunities = filterClosedWonOpportunities(Trigger.new, Trigger.old);

        for(Opportunity opportunity : closedWonOpportunities) {
            opportunitiesToProvision.add(new Provisioning_Event__e(
                Opportunity_Id__c = opportunity.Id
            ));
        }

        if(!opportunitiesToProvision.isEmpty()) {
            EventBus.publish(opportunitiesToProvision);
        }
    }

    private void rollUpActiveAccountLicenses() {
        List<Opportunity> closedWonOpportunities = filterClosedWonOpportunities(Trigger.new, Trigger.old);
        if (closedWonOpportunities.isEmpty()) return;

        Map<Id, Account> accountsToUpdateMap = new Map<Id, Account>();
        for(Opportunity opportunity : closedWonOpportunities) {
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
            update accountsToUpdateMap.values();
        }
    }

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
