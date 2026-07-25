trigger ClosedOpportunityTrigger on Opportunity (after insert, after update) {
    List<Task> relatedTaskList = new List<Task>();
    if(Trigger.isAfter && Trigger.isInsert)
    {
        for(Opportunity opp : Trigger.New){
            if(opp.StageName == 'Closed Won'){
                Task relatedTask = new Task();
                relatedTask.Subject = 'Follow Up Test Task';
                relatedTask.WhatId = opp.id;
                relatedTaskList.add(relatedTask);
            }
        }
        insert relatedTaskList;
    }
    if(Trigger.isAfter && Trigger.isUpdate)
    {
        for(Opportunity opp : Trigger.New){
            if(Trigger.OldMap.get(opp.id).StageName != 'Closed Won' && opp.StageName == 'Closed Won'){
                Task relatedTask = new Task();
                relatedTask.Subject = 'Follow Up Test Task';
                relatedTask.WhatId = opp.id;
                relatedTaskList.add(relatedTask);
            }
        }
        insert relatedTaskList;
    }
}