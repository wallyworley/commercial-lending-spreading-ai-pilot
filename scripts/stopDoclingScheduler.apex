// Aborts all scheduled and queued jobs so deployment can proceed.
// Run before deploying: sf apex run --file scripts/stopDoclingScheduler.apex --target-org <alias>

List<CronTrigger> scheduled = [SELECT Id, CronJobDetail.Name FROM CronTrigger LIMIT 200];
for (CronTrigger ct : scheduled) {
    try {
        System.abortJob(ct.Id);
        System.debug('Aborted scheduled job: ' + ct.CronJobDetail.Name + ' (' + ct.Id + ')');
    } catch (Exception e) {
        System.debug('Could not abort ' + ct.Id + ': ' + e.getMessage());
    }
}

List<AsyncApexJob> queued = [
    SELECT Id, ApexClass.Name, Status
    FROM AsyncApexJob
    WHERE Status IN ('Queued', 'Holding', 'Preparing')
    LIMIT 200
];
for (AsyncApexJob job : queued) {
    try {
        System.abortJob(job.Id);
        System.debug('Aborted queued job: ' + job.ApexClass.Name + ' (' + job.Id + ')');
    } catch (Exception e) {
        System.debug('Could not abort ' + job.Id + ': ' + e.getMessage());
    }
}

System.debug('Done. Aborted ' + scheduled.size() + ' scheduled and ' + queued.size() + ' queued jobs.');
