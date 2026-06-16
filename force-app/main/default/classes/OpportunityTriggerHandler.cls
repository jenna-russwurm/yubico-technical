public without sharing class OpportunityTriggerHandler extends TriggerHandler {

    public OpportunityTriggerHandler() {
        super('Opportunity');
    }

    public override void afterUpdate(){
        if(checkFeature('Opportunity_Order_Provisioning')) {
            provisionOrders();
        }
        if(checkFeature('Rollup_Active_Account_Licenses')) {
            rollUpActiveAccountLicenses();
        }
    }

    private void provisionOrders() {
        List<Provisioning_Event__e> opportunitiesToProvision = new List<Provisioning_Event__e>();
        for(Integer i = 0, size = Trigger.new.size(); i < size; i++) {
            if(Trigger.new[i].get('StageName') == 'Closed Won' && Trigger.old[i].get('StageName') != 'Closed Won') {
                opportunitiesToProvision.add(new Provisioning_Event__e(Opportunity_ID__c = Trigger.new[i].Id));
            }
        }
        if(!opportunitiesToProvision.isEmpty()) {
            EventBus.publish(opportunitiesToProvision);
        }
    }

    private void rollUpActiveAccountLicenses() {
        Set<Id> accountIds = new Map<Id, Account>([SELECT Id FROM Account WHERE Id IN (SELECT AccountId FROM Opportunity WHERE Id IN :Trigger.new)]).keySet();

        List<Account> accountsToUpdate = new List<Account>();
        for(AggregateResult result : [  SELECT SUM(Quantity) activeLicenses, Opportunity.AccountId accountId 
                                        FROM OpportunityLineItem 
                                        WHERE Opportunity.AccountId IN :accountIds
                                        AND Opportunity.Start_Date__c <= TODAY AND Opportunity.End_Date__c >= TODAY
                                        AND Opportunity.StageName = 'Closed Won'
                                        GROUP BY Opportunity.AccountId]) {
            accountsToUpdate.add(new Account(Id = (Id)result.get('accountId'), Active_Licenses_Count__c = (Decimal)result.get('activeLicenses')));
        }

        if(!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
        }
    }
}