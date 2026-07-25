trigger CaseTrigger on Case (
    before update
) {
    new MetadataTriggerHandler().run();
}
