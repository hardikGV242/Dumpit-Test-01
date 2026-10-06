global with sharing class LeadTableResult {

    global class Request {
        @InvocableVariable(
            label='Max Rows'
            description='Maximum number of leads to return (1-25). Defaults to 10.'
            required=false
        )
        global Integer maxRows;

        @InvocableVariable(
            label='Status'
            description='Optional lead status filter, for example Open - Not Contacted. Leave empty for all statuses.'
            required=false
        )
        global String status;
    }

    global class LeadRow {
        @AuraEnabled @InvocableVariable global String name;
        @AuraEnabled @InvocableVariable global String company;
        @AuraEnabled @InvocableVariable global String status;
        @AuraEnabled @InvocableVariable global String email;
    }

    global class LeadTable {
        @AuraEnabled @InvocableVariable global Integer totalShown;
        @AuraEnabled @InvocableVariable global List<LeadRow> rows;
    }

    global class Output {
        @InvocableVariable(label='Lead Info')
        global LeadTable leadInfo;
    }

    @InvocableMethod(
        label='Get Lead Table'
        description='Returns the most recent leads so they can be shown in a table widget.'
    )
    global static List<Output> getLeads(List<Request> requests) {
        Request req = (requests != null && !requests.isEmpty()) ? requests[0] : new Request();

        Integer rowLimit = (req.maxRows == null || req.maxRows < 1) ? 10 : Math.min(req.maxRows, 25);

        String soql = 'SELECT Name, Company, Status, Email FROM Lead';
        Map<String, Object> binds = new Map<String, Object>();
        if (!String.isBlank(req.status)) {
            soql += ' WHERE Status = :statusFilter';
            binds.put('statusFilter', req.status);
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT ' + rowLimit;

        List<Lead> leads = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);

        LeadTable table = new LeadTable();
        table.rows = new List<LeadRow>();
        for (Lead l : leads) {
            LeadRow r = new LeadRow();
            r.name    = l.Name;
            r.company = l.Company;
            r.status  = l.Status;
            r.email   = l.Email;
            table.rows.add(r);
        }
        table.totalShown = table.rows.size();

        Output o = new Output();
        o.leadInfo = table;
        return new List<Output>{ o };
    }
}