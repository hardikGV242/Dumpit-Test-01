@isTest
private class TimesheetControllerTest {
    
    @testSetup
    static void setupTestData() {
        // 1. Create Accounts (Clients)
        Account validClient = new Account(Name = 'Test Client Corp');
        Account excludedClient = new Account(Name = 'GV Mantra');
        insert new List<Account>{ validClient, excludedClient };
        
        // 2. Create Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
        LastName = 'User',
        AccountId = validClient.Id
            );
        insert testContact;
        
        // 3. Create Projects
        Project__c activeProject = new Project__c(
            Name = 'Alpha Project',
        Client__c = validClient.Id,
        Active__c = true
            );
        Project__c inactiveProject = new Project__c(
            Name = 'Beta Project',
        Client__c = validClient.Id,
        Active__c = false
            );
        insert new List<Project__c>{ activeProject, inactiveProject };
        
        // 4. Create Jobs
        Job__c activeJob = new Job__c(
            Name = 'Frontend Development',
        Project__c = activeProject.Id
            );
        Job__c inactiveJob = new Job__c(
            Name = 'Backend Development',
        Project__c = inactiveProject.Id
            );
        insert new List<Job__c>{ activeJob, inactiveJob };
        
        // 5. Create Job Entry
        Job_Entry__c jobEntry = new Job_Entry__c(
            Contact__c = testContact.Id,
        Job__c = activeJob.Id
            );
        insert jobEntry;
        
        // 6. Create Time Log Entry
        Time_Log_Entry__c timeLog = new Time_Log_Entry__c(
            Job_Entry__c = jobEntry.Id,
        Date__c = Date.today(),
        Hours__c = 8.0
            );
        insert timeLog;
    }
    
    @isTest
    static void testGetActiveClients() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<Account> clients = TimesheetController.getActiveClients(con.Id);
        Test.stopTest();
        
        Assert.areEqual(1, clients.size(), 'Should return 1 client, excluding GV Mantra');
        Assert.areEqual('Test Client Corp', clients[0].Name, 'Returned account name should match');
    }
    
    @isTest
    static void testGetActiveProjects() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Client Corp' LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        Test.startTest();
        List<Project__c> projects = TimesheetController.getActiveProjects(acc.Id, con.Id);
        List<Project__c> nullResult = TimesheetController.getActiveProjects(null, con.Id);
        Test.stopTest();
        
        Assert.areEqual(1, projects.size(), 'Should return only active assigned projects');
        Assert.areEqual('Alpha Project', projects[0].Name, 'Project name should match');
        Assert.areEqual(0, nullResult.size(), 'Should return empty list when clientId is null');
    }
    
    @isTest
    static void testGetActiveJobs() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Alpha Project' LIMIT 1];
        
        Test.startTest();
        List<Job__c> jobs = TimesheetController.getActiveJobs(con.Id, proj.Id);
        List<Job__c> nullResult = TimesheetController.getActiveJobs(con.Id, null);
        Test.stopTest();
        
        Assert.areEqual(1, jobs.size(), 'Should return 1 active job for the contact and project');
        Assert.areEqual('Frontend Development', jobs[0].Name, 'Job name should match');
        Assert.areEqual(0, nullResult.size(), 'Should return empty list when projectId is null');
    }
    
    @isTest
    static void testGetTimeEntries() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Date startDate = Date.today().addDays(-1);
        Date endDate = Date.today().addDays(1);
        
        Test.startTest();
        List<Time_Log_Entry__c> entries = TimesheetController.getTimeEntries(con.Id, startDate, endDate);
        List<Time_Log_Entry__c> nullResult = TimesheetController.getTimeEntries(null, startDate, endDate);
        Test.stopTest();
        
        Assert.areEqual(1, entries.size(), 'Should return 1 time entry in the date range');
        Assert.areEqual(8.0, entries[0].Hours__c, 'Hours should match test setup');
        Assert.areEqual(0, nullResult.size(), 'Should return empty list when contactId is null');
    }
    
    @isTest
    static void testGetJobEntryId() {
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Job__c job = [SELECT Id FROM Job__c WHERE Name = 'Frontend Development' LIMIT 1];
        Job_Entry__c expectedJobEntry = [SELECT Id FROM Job_Entry__c LIMIT 1];
        
        Test.startTest();
        String resultId = TimesheetController.getJobEntryId(con.Id, job.Id);
        String nullResult = TimesheetController.getJobEntryId(con.Id, null);
        Test.stopTest();
        
        Assert.areEqual(expectedJobEntry.Id, resultId, 'Job Entry ID should match setup record');
        Assert.isNull(nullResult, 'Should return null when jobId is null');
    }
    
    @isTest
    static void testSaveTimeEntries() {
        Job_Entry__c jobEntry = [SELECT Id FROM Job_Entry__c LIMIT 1];
        Time_Log_Entry__c existingEntry = [SELECT Id FROM Time_Log_Entry__c LIMIT 1];
        
        // 1. Prepare entry to update
        existingEntry.Hours__c = 6.5;
        
        // 2. Prepare new entry to insert
        Time_Log_Entry__c newEntry = new Time_Log_Entry__c(
            Job_Entry__c = jobEntry.Id,
        Date__c = Date.today().addDays(1),
        Hours__c = 4.0
            );
        
        // 3. Prepare entry ID to delete
        Time_Log_Entry__c entryToDelete = new Time_Log_Entry__c(
            Job_Entry__c = jobEntry.Id,
        Date__c = Date.today().addDays(2),
        Hours__c = 2.0
            );
        insert entryToDelete;
        
        Test.startTest();
        TimesheetController.saveTimeEntries(
        new List<Time_Log_Entry__c>{ existingEntry, newEntry },
        new List<Id>{ entryToDelete.Id }
        );
        Test.stopTest();
        
        List<Time_Log_Entry__c> remainingEntries = [SELECT Id, Hours__c FROM Time_Log_Entry__c];
        Assert.areEqual(2, remainingEntries.size(), 'Should have 2 remaining entries after upserts and deletion');
    }
    
    @isTest
    static void testSaveTimeEntriesExceptionHandling() {
        // Pass invalid sObject data to induce an exception and test catch block coverage
        Time_Log_Entry__c invalidEntry = new Time_Log_Entry__c(
            Date__c = Date.today() // Missing required Job_Entry__c master-detail lookup
            );
        
        Boolean exceptionCaught = false;
        Test.startTest();
        try {
            TimesheetController.saveTimeEntries(new List<Time_Log_Entry__c>{ invalidEntry }, null);
        } catch (AuraHandledException e) {
            exceptionCaught = true;
        }
        Test.stopTest();
        
        Assert.isTrue(exceptionCaught, 'AuraHandledException should be thrown on insert failure');
    }
    
    @isTest
    static void testDeleteProjectEntries() {
        Job_Entry__c jobEntry = [SELECT Id FROM Job_Entry__c LIMIT 1];
        Date startDate = Date.today().addDays(-1);
        Date endDate = Date.today().addDays(1);
        
        Test.startTest();
        TimesheetController.deleteProjectEntries(jobEntry.Id, startDate, endDate);
        Test.stopTest();
        
        List<Time_Log_Entry__c> entries = [SELECT Id FROM Time_Log_Entry__c WHERE Job_Entry__c = :jobEntry.Id];
        Assert.areEqual(0, entries.size(), 'Time entries for job entry should be deleted');
    }
}