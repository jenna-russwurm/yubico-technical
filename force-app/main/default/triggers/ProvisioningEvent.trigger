trigger ProvisioningEvent on Provisioning_Event__e (after insert) {
    new ProvisioningEventTriggerHandler().run();
}