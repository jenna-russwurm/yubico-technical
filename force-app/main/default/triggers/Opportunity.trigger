trigger opportunity on Opportunity (after update) {
    new OpportunityTriggerHandler().run();
}