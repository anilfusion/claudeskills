# Custom Metadata Type Schemas

Exact field API names and types, straight from the framework's own object definitions
(`main/default/objects/*.object-meta.xml` and `docs/custom-objects/*.md` in
`trigger-actions-framework`). Use this as the authoritative field list when generating
`customMetadata` XML records — a typo or wrong type here deploys but silently does nothing at
runtime (or fails deploy with an unhelpful error).

## `Trigger_Action__mdt`

One record per discrete action (one Apex class or one flow, in one trigger context, on one
sObject).

| Field API Name | Type | Required | Purpose |
|---|---|---|---|
| `Apex_Class_Name__c` | Text | **Yes** | The Apex class implementing the action. For a flow action this is literally the string `TriggerActionFlow` (or `TriggerActionFlowChangeEvent` for CDC). |
| `Before_Insert__c` | MetadataRelationship → `sObject_Trigger_Setting__mdt` | one of the 7 context fields | Set to link this action into the before-insert context for the sObject named by that setting record. |
| `After_Insert__c` | MetadataRelationship → `sObject_Trigger_Setting__mdt` | " | After-insert context. |
| `Before_Update__c` | MetadataRelationship → `sObject_Trigger_Setting__mdt` | " | Before-update context. |
| `After_Update__c` | MetadataRelationship → `sObject_Trigger_Setting__mdt` | " | After-update context. |
| `Before_Delete__c` | MetadataRelationship → `sObject_Trigger_Setting__mdt` | " | Before-delete context. |
| `After_Delete__c` | MetadataRelationship → `sObject_Trigger_Setting__mdt` | " | After-delete context. |
| `After_Undelete__c` | MetadataRelationship → `sObject_Trigger_Setting__mdt` | " | After-undelete context. |
| `Order__c` | Number | **Yes** | Execution order within that sObject + context, ascending. **This must reflect the original code's execution order** — reordering changes behavior. |
| `Flow_Name__c` | Text | only for flow actions | API name of the auto-launched flow to invoke. Leave blank for Apex actions. |
| `Allow_Flow_Recursion__c` | Checkbox | no | Only for flow actions; allow recursive execution. Default unchecked. |
| `Entry_Criteria__c` | LongTextArea | no | Formula gating whether this action runs for a given record. Blank = always runs. See `framework-overview.md`. |
| `Bypass_Execution__c` | Checkbox | no | Permanently disables this one action. Default unchecked. |
| `Bypass_Permission__c` | Text | no | Custom permission API name — holders are skipped. |
| `Required_Permission__c` | Text | no | Custom permission API name — only holders run this action. |
| `Description__c` | LongTextArea | no, but strongly recommended | Free text. When converting, always fill this in with what the logic does and where it came from (e.g. "Migrated from OpportunityTrigger before-insert stage validation") so the migration is traceable later. |

**Exactly one** of the seven context fields (`Before_Insert__c` … `After_Undelete__c`) should be
populated per record — one action record = one context. If the original logic ran in multiple
contexts (e.g. a helper method called from both before-insert and before-update), create
**separate** `Trigger_Action__mdt` records per context, both pointing at the same
`Apex_Class_Name__c` if the class implements both interfaces, or at two different classes if you
chose to split it further.

Each context field is a lookup to the **`sObject_Trigger_Setting__mdt` record for the target
sObject** (not to the sObject itself) — in customMetadata XML this is expressed as the
`DeveloperName` of that settings record, as a string value:

```xml
<values>
    <field>Before_Insert__c</field>
    <value xsi:type="xsd:string">Opportunity</value>
</values>
```

## `sObject_Trigger_Setting__mdt`

One record per sObject that has the framework enabled on it. Create this once per object — check
whether it already exists in the target project before generating a duplicate.

| Field API Name | Type | Required | Purpose |
|---|---|---|---|
| `Object_API_Name__c` | Text | **Yes** | API name of the object, e.g. `Opportunity`, `MyObject__c`. Do **not** include a managed-package namespace prefix here. |
| `Object_Namespace__c` | Text | no | Namespace, only for objects from an installed package (see `framework-overview.md`). **Always populate this field explicitly, even with an empty value, for non-namespaced objects — don't omit it.** The field has no `defaultValue`, so an omitted field is NULL, and `MetadataTriggerHandler`'s query filters on `Object_Namespace__c = ''` for non-namespaced objects; leaving the field out risks the query matching zero rows instead of matching on empty string, which would silently disable the framework for that sObject. |
| `TriggerRecord_Class_Name__c` | Text | only if any action on this object uses `Entry_Criteria__c` | API name of the global `TriggerRecord` subclass for this sObject. |
| `Bypass_Execution__c` | Checkbox | no | Disables **every** action on this sObject. |
| `Bypass_Permission__c` | Text | no | Custom permission — holders bypass every action on this sObject. |
| `Required_Permission__c` | Text | no | Custom permission — only holders run any action on this sObject. |

## `DML_Finalizer__mdt`

Only needed for the "runs exactly once at the very end of the transaction" case — see
`framework-overview.md`. Don't generate these for ordinary before/after logic.

| Field API Name | Type | Required | Purpose |
|---|---|---|---|
| `Apex_Class_Name__c` | Text | **Yes** | Class implementing `TriggerAction.DmlFinalizer`. |
| `Order__c` | Number | **Yes** | Execution order relative to other finalizers. |
| `Bypass_Execution__c` | Checkbox | no | Disables this finalizer. |
| `Bypass_Permission__c` | Text | no | Custom permission — holders skip this finalizer. |
| `Required_Permission__c` | Text | no | Custom permission — only holders run this finalizer. |

## `TriggerRecord` subclass (only needed alongside `Entry_Criteria__c`)

```apex
global class OpportunityTriggerRecord extends TriggerRecord {
  global Opportunity record {
    get { return (Opportunity) this.newSObject; }
  }
  global Opportunity recordPrior {
    get { return (Opportunity) this.oldSObject; }
  }
}
```
