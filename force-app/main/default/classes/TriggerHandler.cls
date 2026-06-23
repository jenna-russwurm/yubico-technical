public virtual class TriggerHandler {

    private string triggerName;

    public TriggerHandler(string triggerName) {
        this.triggerName = triggerName;
    }

    public void run() {

        if (!this.checkTrigger(this.triggerName)) {
            return;
        }

        switch on Trigger.operationType {
            when BEFORE_INSERT {
                this.beforeInsert();
            }
            when BEFORE_UPDATE {
                this.beforeUpdate();
            }
            when BEFORE_DELETE {
                this.beforeDelete();
            }
            when AFTER_INSERT {
                this.afterInsert();
            }
            when AFTER_UPDATE {
                this.afterUpdate();
            }
            when AFTER_DELETE {
                this.afterDelete();
            }
        }
    }

    // Checks the trigger metadata settings to see if the trigger is active. If the trigger name is blank or the record does not exist, it returns false.
    public boolean checkTrigger(string triggerName) {
        if (String.isBlank(triggerName)) return false;
        Trigger__mdt record = Trigger__mdt.getInstance(triggerName);
        return record != null && record.Active__c;
    }

    // Checks the feature metadata settings to see if the feature is active. If the feature name is blank or the record does not exist, it returns false.
    public boolean checkFeature(string featureName) {
        if (String.isBlank(featureName)) return false;
        Feature__mdt record = Feature__mdt.getInstance(featureName);
        return record != null && record.Active__c;
    }

    protected virtual void beforeInsert() {}

    protected virtual void beforeUpdate() {}

    protected virtual void beforeDelete() {}

    protected virtual void afterInsert() {}

    protected virtual void afterUpdate() {}

    protected virtual void afterDelete() {}

}