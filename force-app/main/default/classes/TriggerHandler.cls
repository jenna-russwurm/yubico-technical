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

    public boolean checkTrigger(string triggerName) {
        return String.isBlank(triggerName) ? false : Trigger__mdt.getInstance(triggerName).Active__c;
    }

    public boolean checkFeature(string featureName) {
        return String.isBlank(featureName) ? false : Feature__mdt.getInstance(featureName).Active__c;
    }

    protected virtual void beforeInsert() {}

    protected virtual void beforeUpdate() {}

    protected virtual void beforeDelete() {}

    protected virtual void afterInsert() {}

    protected virtual void afterUpdate() {}

    protected virtual void afterDelete() {}

}