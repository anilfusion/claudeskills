# Trigger Actions Framework — Concept Reference

Condensed from the framework's own README (Mitch Spano's `trigger-actions-framework`,
https://github.com/mitchspano/trigger-actions-framework). This is the source of truth for
*how the framework behaves at runtime* — read this before generating any converted artifact,
because getting the contract wrong (wrong interface, wrong flow variable names, wrong mdt
field) produces code that deploys cleanly but silently does nothing.

## The core idea

One Apex trigger per sObject, with an empty body that just delegates:

```apex
trigger OpportunityTrigger on Opportunity (
  before insert, after insert, before update, after update,
  before delete, after delete, after undelete
) {
  new MetadataTriggerHandler().run();
}
```

`MetadataTriggerHandler` reads `Trigger_Action__mdt` custom metadata records at runtime,
figures out which ones apply to this sObject + context, sorts them by `Order__c`, and for each
one dynamically instantiates the named Apex class and casts it to the right `TriggerAction`
interface. Every "before insert does X" or "after update does Y" becomes its own metadata
record pointing at its own class (or flow) — no single trigger handler class ever grows again.

This is why the migration target is never "one big Apex class" — it's **one small class or
flow per discrete unit of behavior**, wired together by metadata instead of by code.

## The `TriggerAction` interfaces

Defined in `TriggerAction.cls`. A converted Apex class implements exactly the interface(s) it
needs — usually just one:

| Interface | Method signature |
|---|---|
| `TriggerAction.BeforeInsert` | `void beforeInsert(List<SObject> triggerNew)` |
| `TriggerAction.AfterInsert` | `void afterInsert(List<SObject> triggerNew)` |
| `TriggerAction.BeforeUpdate` | `void beforeUpdate(List<SObject> triggerNew, List<SObject> triggerOld)` |
| `TriggerAction.AfterUpdate` | `void afterUpdate(List<SObject> triggerNew, List<SObject> triggerOld)` |
| `TriggerAction.BeforeDelete` | `void beforeDelete(List<SObject> triggerOld)` |
| `TriggerAction.AfterDelete` | `void afterDelete(List<SObject> triggerOld)` |
| `TriggerAction.AfterUndelete` | `void afterUndelete(List<SObject> triggerNew)` |
| `TriggerAction.DmlFinalizer` | `void execute(FinalizerHandler.Context context)` |

Example (straight from the README):

```apex
public class TA_Opportunity_StageInsertRules implements TriggerAction.BeforeInsert {
  public void beforeInsert(List<Opportunity> triggerNew){
    for (Opportunity opp : triggerNew) {
      if (opp.StageName != 'Prospecting') {
        opp.addError('The Stage must be \'Prospecting\' when an Opportunity is created');
      }
    }
  }
}
```

Note the parameter type is narrowed from `List<SObject>` to the concrete sObject type — that's
allowed and expected; it's what makes the generated class read naturally.

## Flow actions

Converted flows must be **auto-launched flows** (`processType` = `AutoLaunchedFlow`), and they
are invoked by name, not by a direct flow-trigger binding. To be usable, a flow needs specific
resource variables — get these wrong and the flow either won't receive the record or won't be
able to write field changes back:

| Variable | Type | Input | Output | Meaning | Valid contexts |
|---|---|---|---|---|---|
| `record` | record (matching sObject) | yes | yes | the new/current version of the record | insert, update, undelete |
| `recordPrior` | record (matching sObject) | yes | no | the old version of the record | update, delete |

A `Trigger_Action__mdt` record enables a flow by setting `Apex_Class_Name__c` to the literal
string `TriggerActionFlow` (the framework's built-in flow-runner class) and `Flow_Name__c` to
the flow's own API name. `Allow_Flow_Recursion__c` can be checked to let the flow run
recursively (rarely needed — leave unchecked unless the source logic actually depended on
re-entrant execution).

> Trigger Action Flows run through `Invocable.Action`, which has an **undocumented max
> recursion depth of 3** — lower than the normal Apex trigger depth of 16. If the original logic
> chains DML across multiple objects that each have their own trigger action flows, flag this
> as a manual-review risk rather than silently converting it — define entry criteria wherever
> possible to reduce the chance of hitting the limit.

### Field writes only apply in before-context

`TriggerActionFlow.cls` only copies the flow's output `record` values back onto the actual
trigger record during **before-insert and before-update** (`applyFieldValuesDuringBefore`).
After-insert, after-update, before-delete, after-delete, and after-undelete flows can still call
`addError`, but any field assignment the flow makes to `record` in those contexts is silently
discarded — the flow runs, the assignment happens inside the flow's own transient state, and
nothing is written back.

This matters directly for conversion: if the source record-triggered flow's job is to *set a
field* (the common case — defaulting a value, stamping a status, etc.), the converted
`Trigger_Action__mdt` record must use `Before_Insert__c` or `Before_Update__c`, even if the
original native flow ran on `RecordAfterSave`. Only choose an after-context when the source logic
truly has no field writes to preserve (e.g. it only sends a notification, calls another system,
or adds a validation error). When choosing between before- and after-update for a flow with field
writes, before-update is almost always correct — don't default to after-update just because the
source flow used `RecordAfterSave`.

### Change Data Capture flows

If the source logic is a CDC-triggered flow rather than a record-triggered one, the variable
contract is different (`record` is the change event, `header` is a `FlowChangeEventHeader`
Apex-defined variable, input-only) and the `Apex_Class_Name__c` on the metadata record is
`TriggerActionFlowChangeEvent` instead of `TriggerActionFlow`. This is a distinct, less common
case — confirm with the user before assuming a record-triggered flow is actually CDC-based.

## Entry criteria (declarative filtering, no Apex/flow decision element needed)

`Trigger_Action__mdt.Entry_Criteria__c` holds a formula (evaluated via `FormulaEval`) that gates
whether the action runs *at all* for a given record — this is often a cleaner conversion target
than reproducing an `if` statement or a flow Decision element, because it keeps the filtering
declarative and visible from Setup.

```
record.Name = "Bob" && recordPrior.Name = "Joe"
```

Requirements:
- The sObject must have a corresponding `sObject_Trigger_Setting__mdt.TriggerRecord_Class_Name__c`
  pointing at a global Apex class extending `TriggerRecord` with `global record` / `global
  recordPrior` properties downcast to the concrete sObject type (see
  `custom-metadata-schema.md` for the exact shape). Only generate this class if it doesn't
  already exist for the sObject.
- **Field traversal is shallow only** — `record.StageName` works, `record.Account.Industry`
  does not. If the original condition needs a related-object field, entry criteria can't
  express it; keep that check as a guard clause inside the class/flow instead and say so in the
  conversion notes.
- A blank `Entry_Criteria__c` means "always run" — don't invent a criteria formula for logic
  that was previously unconditional.

## Bypass mechanisms (preserve, don't reinvent)

The framework already gives every action three ways to be turned off, so a converted class or
flow should almost never need its own custom "skip this" flag:

- `Bypass_Execution__c` checkbox on the mdt record (or on `sObject_Trigger_Setting__mdt` for the
  whole object) — permanent, toggled from Setup.
- `Bypass_Permission__c` — if the running user holds this custom permission, the action is
  skipped (typical use: integration/data-load service accounts).
- `Required_Permission__c` — action only runs if the running user holds this permission
  (typical use: staged rollout to a subset of users).
- Transaction-scoped bypasses from Apex/Flow: `TriggerBase.bypass(Schema.X.SObjectType)`,
  `MetadataTriggerHandler.bypass(MyClass.class)`, `TriggerActionFlow.bypass(Flow.Interview.X.class)`.

If the source code being converted contains a hand-rolled bypass/feature-flag check (e.g. a
custom setting lookup that short-circuits the trigger), that's a strong signal it should become
`Bypass_Permission__c` / `Required_Permission__c` / `Bypass_Execution__c` instead of being
carried over as bespoke logic.

## Recursion prevention

For update contexts, use `TriggerBase.idToNumberOfTimesSeenBeforeUpdate` /
`idToNumberOfTimesSeenAfterUpdate` to replicate a "only run once per record per transaction"
guard that the original trigger may have implemented by hand with a static `Set<Id>`:

```apex
if (TriggerBase.idToNumberOfTimesSeenAfterUpdate.get(opp.id) == 1 && ...) { ... }
```

## DML finalizers (only if the source logic truly runs "exactly once, at the very end")

If part of the original trigger/helper logic exists specifically to run once after all DML in
the transaction completes (e.g. enqueuing a single Queueable, writing a single log record even
though the trigger itself may fire multiple times due to bulk DML or cascades), that's a
candidate for `DML_Finalizer__mdt` + a class implementing `TriggerAction.DmlFinalizer`, not a
regular trigger action. This is a narrower, less common case than ordinary before/after logic —
don't reach for it unless the source has that specific "exactly once at the end" shape. See
`custom-objects/DML_Finalizer__mdt` fields in `custom-metadata-schema.md`.

## DML-less testing (`TriggerTestUtility`)

The framework ships a `TriggerTestUtility.getFakeId(Schema.SObjectType)` helper that fabricates a
syntactically valid Id without inserting a record. A generated `TriggerAction` class's test can
call the interface method (e.g. `.beforeInsert(...)`, `.afterUpdate(...)`) directly with
in-memory records built using a fake Id, then assert against `record.hasErrors()` /
`record.getErrors()` or field values — no DML, no org data setup required. This is the
framework's own preferred test style (see `assets/templates/TriggerActionClassTest.cls.template`)
and is significantly faster than round-tripping through real inserts/updates.

## Namespaced / managed-package objects

If converting logic on an object from an installed package (e.g. `Acme__Explosives__c`), the
`sObject_Trigger_Setting__mdt` record splits the namespace out:
`Object_Namespace__c = 'Acme'`, `Object_API_Name__c = 'Explosives__c'`.
