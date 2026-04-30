// Restarts the Docling keep-warm scheduler without touching unrelated jobs.
// Run with: sf apex run --file scripts/startDoclingScheduler.apex --target-org <alias>

List<CronTrigger> existingJobs = [
    SELECT Id, CronJobDetail.Name
    FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'Docling Keep Warm%'
    LIMIT 100
];
for (CronTrigger job : existingJobs) {
    System.abortJob(job.Id);
    System.debug('Aborted existing Docling keep-warm job: ' + job.CronJobDetail.Name + ' (' + job.Id + ')');
}

List<Integer> minutes = new List<Integer>{ 0, 10, 20, 30, 40, 50 };
for (Integer minute : minutes) {
    String minuteText = String.valueOf(minute).leftPad(2, '0');
    String cron = '0 ' + minute + ' * * * ?';
    String jobName = 'Docling Keep Warm ' + minuteText;
    Id jobId = System.schedule(jobName, cron, new DoclingKeepWarmSchedulable());
    System.debug('Scheduled ' + jobName + ' with cron ' + cron + ' (' + jobId + ')');
}

System.debug('Docling keep-warm scheduler restarted. Active cadence: every 10 minutes.');
