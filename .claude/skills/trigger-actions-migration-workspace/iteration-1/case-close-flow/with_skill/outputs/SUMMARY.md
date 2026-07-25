# Conversion Summary: Case_Set_Default_Description_On_Close

Converted the native record-triggered flow `Case_Set_Default_Description_On_Close`
(Case, `RecordAfterSave`) into the Trigger Actions Framework.

## Old artifact -> New artifact(s)

| Old | Context | New | Context / Config |
|---|---|---|---|
| `flows/Case_Set_Default_Description_On_Close.flow-meta.xml` (native record-triggered flow, Decision `Check_If_Status_Became_Closed` + Assignment `Set_Default_Description`) | Native `RecordAfterSave` binding on Case | `flows/TA_Case_SetDefaultDescriptionOnClose.flow-meta.xml` (auto-launched flow, single Assignment `Set_Default_Description`) | Invoked by the framework via `Trigger_Action.Case_SetDefaultDescriptionOnClose`, **Before Update**, `Order__c = 10` |
| (none - logic lived only in the flow) | - | `customMetadata/Trigger_Action.Case_SetDefaultDescriptionOnClose.md-meta.xml` | `Apex_Class_Name__c = TriggerActionFlow`, `Flow_Name__c = TA_Case_SetDefaultDescriptionOnClose`, `Before_Update__c = Case`, `Entry_Criteria__c = record.Status = "Closed" && recordPrior.Status != "Closed"` |
| (none) | - | `customMetadata/sObject_Trigger_Setting.Case.md-meta.xml` | `Object_API_Name__c = Case`, `TriggerRecord_Class_Name__c = CaseTriggerRecord` (new - no Case setting existed yet) |
| (none) | - | `classes/CaseTriggerRecord.cls` + `.cls-meta.xml` | `global` `TriggerRecord` subclass required so `Entry_Criteria__c` can reference `record.Status` / `recordPrior.Status` |
| (none - Case had no bootstrap trigger in this project) | - | `triggers/CaseTrigger.trigger` | `trigger CaseTrigger on Case (before update) { new MetadataTriggerHandler().run(); }` - trimmed to just `before update` since that's the only context any action currently uses |
| `flows/Case_Set_Default_Description_On_Close.flow-meta.xml` | - | *same file, retained* | `<status>` changed `Active` -> `Draft` (deactivated, not deleted); comment added explaining the replacement and that final deletion is a separate manual step |

## Decisions / reasoning

- **Before Update, not After Update.** `TriggerActionFlow.cls` only calls
  `applyFieldValuesDuringBefore(...)` from `beforeInsert`/`beforeUpdate` - an `afterUpdate` flow's
  output changes to `record` are *not* written back automatically (no extra `Update Records` DML
  exists in this flow, matching the original's direct-assignment style). Binding to
  `Before_Update__c` was required to reproduce the original "set Description on save" behavior
  without adding a second DML statement the source never had.
- **Update-only, no insert context.** The condition inherently compares to a prior value
  ("was not Closed before"), which only makes sense on update; `recordPrior` isn't a meaningful
  concept on insert. The bootstrap trigger and the `Trigger_Action__mdt` record are both scoped to
  `before update` only.
- **Decision element replaced with `Entry_Criteria__c`.** The entire source flow was one
  Decision + one Assignment, both keyed directly on top-level `record`/`recordPrior` fields with
  no related-object traversal - exactly the case `references/framework-overview.md` calls out as
  preferable to express as `Entry_Criteria__c` rather than an in-flow Decision element. This
  required adding `CaseTriggerRecord` (global, extends `TriggerRecord`) and setting
  `TriggerRecord_Class_Name__c` on the new `sObject_Trigger_Setting.Case` record, since none
  existed for Case yet.
- **New bootstrap trigger created.** This project had no existing Apex trigger on Case (the
  original automation was 100% flow-based), so `CaseTrigger.trigger` is new, not a modification -
  needed or the `MetadataTriggerHandler` never runs for Case at all.
- **Flow API name.** Followed the framework's `TA_<Object>_<WhatItDoes>` naming convention since
  no existing `Trigger_Action__mdt` records or naming pattern exist in this project yet to match.
- **Old flow deactivated via `Draft`**, per `conversion-patterns.md` guidance (safer/more
  reversible than `Obsolete`), left in place rather than deleted.

## Uncertainties / flagged for manual review

- The original flow's `<start>` had `triggerType>RecordAfterSave` with no explicit
  `recordTriggerType` (Create/Update/CreateAndUpdate) restricting it - in a real org that
  combination would technically also fire on record creation, where `recordPrior` is null. Taken
  at face value, "Status became Closed" is an update-transition concept, so this conversion
  treats it as update-only; if the org actually relies on this also firing at Case creation with
  `Status = 'Closed'` set on insert, that would need a second `Trigger_Action__mdt` record
  (`After_Insert__c` or `Before_Insert__c`, no `recordPrior`/no entry-criteria-on-prior) pointing
  at a variant flow - flagging this rather than guessing, since it changes behavior.
- No other automation currently references the old flow or exists on Case in this project, so
  nothing else needed to be bypassed to avoid duplicate side effects - but this should be
  re-verified against the real org before deploying, since this scratch project only contains the
  framework + this one flow.
