public with sharing class TimesheetController {
    
    @AuraEnabled(cacheable=true)
    public static List<Account> getActiveClients(Id contactId) {
        List<Job__c> assignedJobEntries = [
            SELECT Project__r.Client__c
            FROM Job__c
            WHERE Id IN (SELECT Job__c FROM Job_Entry__c WHERE Contact__c = :contactId)
        ];
        
        Set<Id> clientIds = new Set<Id>();
        for (Job__c job : assignedJobEntries) {
            if (job.Project__r.Client__c != null) {
                clientIds.add(job.Project__r.Client__c);
            }
        }
        
        return [
            SELECT Id, Name 
            FROM Account 
            WHERE Id IN :clientIds
            ORDER BY Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getActiveProjects(Id clientId, Id contactId) {
        if (clientId == null || contactId == null) {
            return new List<Project__c>();
        }
        
        List<Job__c> assignedJobEntries = [
            SELECT Project__c
            FROM Job__c
            WHERE Id IN (SELECT Job__c FROM Job_Entry__c WHERE Contact__c = :contactId)
        ];
        
        Set<Id> projectIds = new Set<Id>();
        for (Job__c job : assignedJobEntries) {
            if (job.Project__c != null) {
                projectIds.add(job.Project__c);
            }
        }
        
        return [
            SELECT Id, Name 
            FROM Project__c 
            WHERE Client__c = :clientId 
            AND Active__c = true 
            AND Id IN :projectIds
            ORDER BY Name
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Job__c> getActiveJobs(Id contactId, Id selectedProjectId) {
        if (contactId == null || selectedProjectId == null) {
            return new List<Job__c>();
        }
        
        return [
            SELECT Id, Name
            FROM Job__c 
            WHERE Id IN (SELECT Job__c FROM Job_Entry__c WHERE Contact__c = :contactId)
            AND Project__c = :selectedProjectId 
            ORDER BY Name
        ];
    }
    
    @AuraEnabled
    public static List<Time_Log_Entry__c> getTimeEntries(Id contactId, Date startDate, Date endDate) {
        if (contactId == null || startDate == null || endDate == null) {
            return new List<Time_Log_Entry__c>();
        }
        
        return [
            SELECT Id, Date__c, Hours__c, Job_Entry__r.Job__c, Job_Entry__r.Job__r.Name, Job_Entry__r.Job__r.Project__c, Job_Entry__r.Job__r.Project__r.Name, Job_Entry__c
            FROM Time_Log_Entry__c 
            WHERE Job_Entry__c IN (SELECT Id FROM Job_Entry__c WHERE Contact__c = :contactId)
            AND Date__c >= :startDate 
            AND Date__c <= :endDate
        ];
    }
    
    @AuraEnabled(cacheable=true)
    public static String getJobEntryId(Id contactId, Id jobId){
        if (contactId == null || jobId == null) {
            return null;
        }
        
        try {
            List<Job_Entry__c> jobEntries = [
                SELECT Id
                FROM Job_Entry__c
                WHERE Job__c = :jobId
                AND Contact__c = :contactId
                LIMIT 1
            ];
            
            return !jobEntries.isEmpty() ? (String)jobEntries[0].Id : null;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Job Entry: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void saveTimeEntries(List<Time_Log_Entry__c> entriesToSave, List<Id> entriesToDelete) {
        try {
            if (entriesToDelete != null && !entriesToDelete.isEmpty()) {
                delete [SELECT Id FROM Time_Log_Entry__c WHERE Id IN :entriesToDelete];
            }
            if (entriesToSave != null && !entriesToSave.isEmpty()) {
                upsert entriesToSave;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error saving timesheet: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void deleteProjectEntries(Id jobEntryId, Date startDate, Date endDate) {
        if (jobEntryId == null || startDate == null || endDate == null) {
            return;
        }
        
        try {
            List<Time_Log_Entry__c> entriesToDelete = [
                SELECT Id 
                FROM Time_Log_Entry__c 
                WHERE Job_Entry__c = :jobEntryId
                AND Date__c >= :startDate 
                AND Date__c <= :endDate
            ];
            
            if (!entriesToDelete.isEmpty()) {
                delete entriesToDelete;
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting project entries: ' + e.getMessage());
        }
    }
}