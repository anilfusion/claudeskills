// Enables Entry_Criteria__c formulas on Trigger_Action__mdt records for the Case sObject.
// Referenced by sObject_Trigger_Setting.Case.md-meta.xml (TriggerRecord_Class_Name__c).
// Created for the Case_Set_Default_Description_On_Close -> Trigger Actions Framework migration.
global class CaseTriggerRecord extends TriggerRecord {
    global Case record {
        get { return (Case) this.newSobject; }
    }
    global Case recordPrior {
        get { return (Case) this.oldSobject; }
    }
}
