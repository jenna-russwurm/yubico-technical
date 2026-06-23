trigger Opportunity on Opportunity (after update) {
    new OpportunityTriggerHandler().run();
}