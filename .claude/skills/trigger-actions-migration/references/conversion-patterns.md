# Conversion Patterns

How to go from "one trigger + one sprawling helper class" or "one record-triggered flow with
several decision branches" to a set of small, independently-ordered trigger actions. This is
where judgment matters most — the mechanical parts (mdt field names, flow variable contract) are
in the other two reference files.

## Why decompose at all

The whole point of the framework is the *Single-responsibility* and *Open-closed* principles: to
add or change one piece of automation later, someone should be able to touch one small class or
flow and one metadata record, without reading or risking the rest of the object's automation.
A conversion that produces one giant Apex class implementing every interface (just to avoid
splitting the file) defeats the purpose just as much as leaving the original trigger alone would.
So the target granularity is **one class or flow per distinct piece of business logic**, not one
per trigger context and definitely not one per object.

## Finding the seams

Read the source trigger/helper or flow start to finish and write down each distinct thing it
does, independent of how the source code happens to group them. Concretely, look for these seam
markers:

- **Separate `if`/`else if` branches keyed on different conditions** — almost always separate
  actions. `ClosedOpportunityTrigger`'s "insert a follow-up Task when Stage = Closed Won" logic
  is one action; if the same trigger also validated Amount on insert, that would be a second,
  independent action even though it's the same trigger context.
- **Separate helper methods**, even if called from the same trigger context — each method is
  usually its own action already; the "decomposition" work is mostly extracting it into its own
  class rather than inventing new boundaries.
- **The same logic repeated across contexts** (e.g. the same validation on both before-insert and
  before-update) — implement it once, as a class implementing both interfaces (or a flow invoked
  from two `Trigger_Action__mdt` records, one per context), rather than duplicating it.
- **A leading condition that gates a whole block** (e.g. `if (Trigger.isAfter && Trigger.isInsert)`
  around a large chunk) — this is a context split the framework already gives you for free
  (separate before/after, insert/update mdt records); don't also carry the `if` into the class.
- **A narrower condition inside that block** (e.g. `if (opp.StageName == 'Closed Won')`) — this is
  either an `Entry_Criteria__c` formula (preferred, if it only touches fields directly on the
  record) or a guard clause at the top of the method (if it needs related-object fields or is too
  complex for the formula grammar).

## Apex vs. Flow: preserve the original implementation choice

Don't rewrite Apex logic as a flow or flow logic as Apex during this conversion — that's a
separate decision with its own tradeoffs and the user hasn't asked for it. The migration is about
*where the logic lives and how it's ordered*, not what language it's written in. So:

- Trigger/helper-class logic → one or more Apex classes implementing `TriggerAction.*`.
- Record-triggered flow logic → one or more auto-launched flows, each satisfying the `record` /
  `recordPrior` variable contract.

The only exception: if a single record-triggered flow has multiple independent decision branches
that don't share elements, splitting it into multiple auto-launched flows (one per branch) is
usually a straight, low-risk mechanical split — the same recombination the framework does for
Apex. If branches share flow variables, subflows, or complex intermediate state, don't force a
split; flag it for manual review instead (see "What not to auto-convert" below).

## Ordering

`Order__c` must reproduce the order the original code ran in — this is not cosmetic. If the
source trigger executed validation before task creation, or one helper method before another, the
generated `Trigger_Action__mdt.Order__c` values need to preserve that sequence within the same
context. When in doubt, order matches source order top-to-bottom. Leave gaps (10, 20, 30 instead
of 1, 2, 3) so a later manual insertion doesn't require renumbering everything.

## Naming convention

The framework's own convention, used throughout its README and examples, is:

```
TA_<Object>_<WhatItDoes>
```

e.g. `TA_Opportunity_StageInsertRules`, `TA_Opportunity_RecalculateCategory`. Use this for
generated Apex class names and for generated flow API names, unless the target project already
has its own trigger-action naming pattern — **check for existing `Trigger_Action__mdt` records or
classes implementing `TriggerAction.*` in the target project first**, and match whatever pattern
is already established there instead of introducing a second convention side-by-side.

## Retiring the old artifacts

Once the new actions and metadata exist and cover everything the original code did:

- **Old trigger**: the framework requires exactly one trigger per sObject anyway (the bootstrap
  trigger that calls `new MetadataTriggerHandler().run();`). So "retiring" the old trigger usually
  means *replacing its body* with that bootstrap call — it doesn't disappear, it becomes the
  entry point. Make sure the trigger's event list (`before insert, after insert, ...`) covers
  every context now driven by metadata.
- **Old helper class**: once every method has been migrated into a new `TriggerAction`
  implementation, check whether anything else in the org still calls the helper class directly
  (search for references, don't assume). If nothing else calls it, remove it rather than leaving
  a dead file. If something else still calls it, leave it and note the remaining dependency in
  the conversion summary instead of guessing whether it's safe to delete.
- **Old record-triggered flow**: set it inactive (`<status>Draft</status>` or `Obsolete` in the
  flow's metadata, per the target org's convention — Draft is safer since Obsolete is
  permanent-feeling) rather than deleting it outright, so the change is reversible if the
  conversion turns out to have missed something. Say clearly in the summary that it was
  deactivated, not deleted, and that final deletion is a separate manual cleanup step once the
  new flow is verified in the org.

Never run both the old and new automation active at the same time on the same object/context —
that's a straight path to duplicated side effects (e.g. two Tasks created instead of one).

## Worked example

Source (`ClosedOpportunityTrigger.trigger`, after insert + after update, no helper class):

```apex
trigger ClosedOpportunityTrigger on Opportunity (after insert, after update) {
    List<Task> relatedTaskList = new List<Task>();
    if (Trigger.isAfter && Trigger.isInsert) {
        for (Opportunity opp : Trigger.New) {
            if (opp.StageName == 'Closed Won') {
                Task relatedTask = new Task();
                relatedTask.Subject = 'Follow Up Test Task';
                relatedTask.WhatId = opp.id;
                relatedTaskList.add(relatedTask);
            }
        }
        insert relatedTaskList;
    }
    if (Trigger.isAfter && Trigger.isUpdate) {
        for (Opportunity opp : Trigger.New) {
            if (Trigger.OldMap.get(opp.id).StageName != 'Closed Won' && opp.StageName == 'Closed Won') {
                Task relatedTask = new Task();
                relatedTask.Subject = 'Follow Up Test Task';
                relatedTask.WhatId = opp.id;
                relatedTaskList.add(relatedTask);
            }
        }
        insert relatedTaskList;
    }
}
```

This is one piece of business logic ("create a follow-up Task when an Opportunity becomes Closed
Won") expressed twice — once for insert, once for update — because the source trigger has no
shared action mechanism. That repetition is exactly what the framework removes.

Converted:

- **`TA_Opportunity_CreateFollowUpTask.cls`** implementing both `TriggerAction.AfterInsert` and
  `TriggerAction.AfterUndelete`... no — implementing `TriggerAction.AfterInsert` and
  `TriggerAction.AfterUpdate`, one shared private method for building the Task:

  ```apex
  public class TA_Opportunity_CreateFollowUpTask implements TriggerAction.AfterInsert, TriggerAction.AfterUpdate {
      public void afterInsert(List<Opportunity> triggerNew) {
          insertFollowUpTasks(triggerNew);
      }
      public void afterUpdate(List<Opportunity> triggerNew, List<Opportunity> triggerOld) {
          Map<Id, Opportunity> oldMap = new Map<Id, Opportunity>(triggerOld);
          List<Opportunity> becameClosedWon = new List<Opportunity>();
          for (Opportunity opp : triggerNew) {
              if (oldMap.get(opp.Id).StageName != 'Closed Won' && opp.StageName == 'Closed Won') {
                  becameClosedWon.add(opp);
              }
          }
          insertFollowUpTasks(becameClosedWon);
      }
      private void insertFollowUpTasks(List<Opportunity> opportunities) {
          List<Task> tasks = new List<Task>();
          for (Opportunity opp : opportunities) {
              tasks.add(new Task(Subject = 'Follow Up Test Task', WhatId = opp.Id));
          }
          if (!tasks.isEmpty()) {
              insert tasks;
          }
      }
  }
  ```

  Note the insert-context branch's `StageName == 'Closed Won'` filter is arguably a candidate for
  `Entry_Criteria__c` instead of an in-code check — either is defensible; prefer entry criteria
  when the whole method body would otherwise be a single `if`, prefer an in-code guard when the
  method does other unconditional work first.

- Two `Trigger_Action__mdt` records: one with `After_Insert__c` set, one with `After_Update__c`
  set, both `Apex_Class_Name__c = TA_Opportunity_CreateFollowUpTask`, same `Order__c` tier if
  nothing else on the object needs to run before/after this at a different priority.

- `sObject_Trigger_Setting__mdt` record for `Opportunity` (create only if one doesn't already
  exist in the target project).

- The old `ClosedOpportunityTrigger.trigger` body is replaced with the bootstrap call (or, if an
  `OpportunityTrigger` bootstrap already exists from converting other Opportunity automation,
  `ClosedOpportunityTrigger` is deleted entirely and its context list folded into the existing
  bootstrap trigger — the framework wants exactly one trigger per object).

## What not to auto-convert — flag these for manual review instead

Generate everything you're confident about, then call out anything in this list explicitly in the
conversion summary rather than guessing:

- Flow elements with no direct auto-launched-flow equivalent tied to a specific record (Wait
  elements, scheduled paths, screen elements — record-triggered flows can have these but an
  auto-launched flow invoked synchronously from Apex generally shouldn't).
- Subflows called from the source flow that are themselves record-triggered or that reference
  other objects' automation — converting the outer flow without understanding the subflow risks
  silently changing behavior.
- Any condition needing a related-object field (`record.Account.Industry`) if you were about to
  put it in `Entry_Criteria__c` — that field doesn't support relationship traversal; keep it as
  code/flow-native filtering instead.
- Logic that depends on trigger recursion depth or transaction-wide state in a way that isn't
  already covered by `TriggerBase`'s recursion counters — call out the risk from
  `framework-overview.md` rather than assuming the 1:1 port is safe.
- Anything that isn't actually record-triggered (scheduled Apex, batch, platform events without
  CDC, invocable actions called from Flow Builder screens) — out of scope for this framework.
