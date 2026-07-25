---
name: trigger-actions-migration
description: Converts Salesforce record-triggered flows and Apex trigger/helper-class pairs into the Trigger Actions Framework (Mitch Spano's trigger-actions-framework — MetadataTriggerHandler, TriggerAction interfaces, TriggerActionFlow) — generating small single-responsibility auto-launched flows and Apex TriggerAction classes, wired together with Trigger_Action__mdt / sObject_Trigger_Setting__mdt custom metadata records, and retiring the old automation.
---

# Trigger Actions Framework Migration

Converts existing Salesforce automation on an sObject — a record-triggered flow, or an Apex
trigger plus its helper class(es) — into the shape this framework expects: many small,
independently-ordered, independently-bypassable trigger actions (Apex classes or auto-launched
flows) registered via custom metadata, instead of one large trigger body or one large flow.

Read the three reference files before generating anything — they're short and getting the
contract wrong produces code that deploys cleanly but does nothing at runtime:

- **`references/framework-overview.md`** — how the framework actually works at runtime: the
  `TriggerAction` interfaces, the flow variable contract (`record` / `recordPrior`), entry
  criteria formulas, bypass mechanisms, recursion, DML finalizers. Read this first.
- **`references/custom-metadata-schema.md`** — exact field API names/types for
  `Trigger_Action__mdt`, `sObject_Trigger_Setting__mdt`, `DML_Finalizer__mdt`. Reference while
  generating customMetadata XML.
- **`references/conversion-patterns.md`** — how to find the seams in a monolithic trigger/helper
  or flow, naming convention, ordering rules, how to retire the old artifacts, a worked
  before/after example, and what to flag for manual review instead of guessing at.

`assets/templates/` has ready-to-fill skeletons for every artifact type this skill generates —
start from these rather than free-handing the XML, especially the flow skeleton, since the
`record`/`recordPrior` variable configuration is easy to get subtly wrong by hand.

## Before starting: confirm the framework is actually available

This skill produces code that depends on the framework's own classes (`MetadataTriggerHandler`,
`TriggerAction`, `TriggerActionFlow`, `TriggerBase`, `FormulaFilter`, ...) and custom metadata
types already existing in the target org/project. Check the target SFDX project for these before
generating anything:

```
force-app/main/default/classes/MetadataTriggerHandler.cls
force-app/main/default/objects/Trigger_Action__mdt/
force-app/main/default/objects/sObject_Trigger_Setting__mdt/
```

If they're missing, say so and ask whether the user wants you to also deploy/vendor the framework
itself (it can be added as an unlocked package, or its source copied in — see the framework's own
README for install links) before converting anything. Don't silently invent local copies of the
framework's classes.

## Workflow

1. **Read the source.** Load the full trigger + every helper class it calls, or the full
   record-triggered flow, from the target project. Don't guess at behavior from a partial read —
   trigger bodies are often short but helper classes can hide the real logic several calls deep.

2. **Inventory the distinct pieces of logic**, independent of how the source code currently
   groups them. For each one, note: sObject, trigger context(s) (before/after ×
   insert/update/delete/undelete), the condition that gates it (if any), what it does, and where
   it sits in execution order relative to the rest of the source file. `conversion-patterns.md`
   has heuristics for finding these seams (branch conditions, helper method boundaries, repeated
   logic across contexts).

3. **Decide Apex vs. flow per piece — matching the source's own implementation language.** This
   migration relocates and reorders logic; it doesn't rewrite Apex as declarative flow or vice
   versa unless the user asks for that separately. A record-triggered flow may still split into
   multiple auto-launched flows if it has independent branches (see `conversion-patterns.md` for
   when that split is safe vs. when to flag it instead).

4. **Generate the artifacts**, using `assets/templates/`:
   - One Apex class per Apex-side piece of logic, implementing the narrowest `TriggerAction.*`
     interface(s) it actually needs (`TriggerActionClass.cls.template` +
     `.cls-meta.xml.template`), plus a matching test class
     (`TriggerActionClassTest.cls.template`) that calls the interface method directly with
     in-memory records — the framework's own convention is DML-less trigger testing (see
     `TriggerTestUtility.getFakeId`), which is faster than real DML and doesn't need an org
     connection to run in isolation. Skip the test only if the target project's own existing
     trigger-action classes don't have tests either — match the project's established practice.
   - One auto-launched flow per flow-side piece of logic, with the correct `record`/`recordPrior`
     variables (`AutoLaunchedFlow.flow-meta.xml.template`).
   - One `Trigger_Action__mdt` customMetadata record per piece of logic per context
     (`TriggerAction.md-meta.xml.template`), `Order__c` reflecting the source's original
     execution order, `Entry_Criteria__c` filled in only when the guard condition is expressible
     without related-object field traversal.
   - One `sObject_Trigger_Setting__mdt` record per sObject, only if one doesn't already exist in
     the target project (`sObject_Trigger_Setting.md-meta.xml.template`).
   - A `TriggerRecord` subclass (`TriggerRecord.cls.template`) only for sObjects where some
     action uses `Entry_Criteria__c`.
   - The bootstrap trigger (`BootstrapTrigger.trigger.template`) — trim the context list to only
     what's actually used across all actions on that object, rather than always including all
     seven.

5. **Retire the old automation** per `conversion-patterns.md`: replace the old trigger's body
   with the bootstrap call (it becomes the new entry point, it doesn't disappear), delete the old
   helper class only if nothing else references it, deactivate (don't delete) the old
   record-triggered flow. Never leave old and new automation both active on the same
   object/context — that duplicates side effects.

6. **Write a short conversion summary**: a table of old artifact → new artifact(s) with context
   and order, and a distinct, explicit list of anything skipped or flagged for manual review
   (per the "what not to auto-convert" list in `conversion-patterns.md`) rather than silently
   omitting it. This summary is the deliverable the user actually reviews — make it easy to spot
   what changed and what still needs a human decision.

## Scope check

If what the user is describing isn't actually record-triggered automation on a single sObject
(e.g. scheduled Apex, batch jobs, Flow Builder screen flows, invocable actions called from LWC),
say so rather than forcing it through this framework — it's built specifically for
insert/update/delete/undelete trigger contexts.
