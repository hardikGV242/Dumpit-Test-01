import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getActiveClients from '@salesforce/apex/TimesheetController.getActiveClients';
import getActiveProjects from '@salesforce/apex/TimesheetController.getActiveProjects';
import getActiveJobs from '@salesforce/apex/TimesheetController.getActiveJobs';
import getTimeEntries from '@salesforce/apex/TimesheetController.getTimeEntries';
import saveTimeEntries from '@salesforce/apex/TimesheetController.saveTimeEntries';
import deleteProjectEntries from '@salesforce/apex/TimesheetController.deleteProjectEntries';
import getJobEntryId from '@salesforce/apex/TimesheetController.getJobEntryId';

export default class TimesheetApp extends LightningElement {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (this._recordId && this.selectedMonth) {
            this.loadExistingTimeEntries();
        }
    }

    selectedMonth; // Format 'YYYY-MM'
    selectedClientId = '';
    selectedProjectId = '';
    selectedJobId = '';
    currentJobEntryId = '';

    clientOptions = [];
    projectOptions = [];
    jobOptions = [];

    @track monthDays = []; 
    @track matrixRows = []; 
    @track columnTotals = []; 
    grandTotal = '0.00';
    
    // Key: `${jobEntryId}_${date}`, Value: `Time_Log_Entry__c.Id`
    existingEntryIds = new Map();

    connectedCallback() {
        const today = new Date();
        const year = today.getFullYear();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        this.selectedMonth = `${year}-${month}`;
        
        this.generateMonthDays();

        if (this._recordId) {
            this.loadExistingTimeEntries();
        }
    }

    generateMonthDays() {
        const [year, month] = this.selectedMonth.split('-').map(Number);
        const daysInMonth = new Date(year, month, 0).getDate();
        const days = [];
        const dayNames = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

        for (let day = 1; day <= daysInMonth; day++) {
            const dateObj = new Date(year, month - 1, day);
            const dayOfWeekIndex = dateObj.getDay();
            const isWeekend = dayOfWeekIndex === 0 || dayOfWeekIndex === 6;

            const formattedDate = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;

            days.push({
                date: formattedDate,
                dayNumber: day,
                dayOfWeek: dayNames[dayOfWeekIndex],
                isWeekend: isWeekend,
                cellClass: isWeekend ? 'weekend-cell' : 'weekday-cell'
            });
        }
        this.monthDays = days;
    }

    async loadExistingTimeEntries() {
        if (!this._recordId || !this.selectedMonth) return;

        const [year, month] = this.selectedMonth.split('-').map(Number);
        const startDate = `${year}-${String(month).padStart(2, '0')}-01`;
        const lastDay = new Date(year, month, 0).getDate();
        const endDate = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;

        try {
            const entries = await getTimeEntries({ 
                contactId: this._recordId, 
                startDate: startDate, 
                endDate: endDate 
            });
            
            this.buildMatrixFromEntries(entries);
        } catch (error) {
            this.showToast('Error', 'Error loading time entries: ' + (error.body?.message || error), 'error');
        }
    }

    buildMatrixFromEntries(entries) {
        const projectMap = new Map();
        this.existingEntryIds.clear();

        entries.forEach(entry => {
            const timeEntryKey = `${entry.Job_Entry__c}_${entry.Date__c}`;
            this.existingEntryIds.set(timeEntryKey, entry.Id);

            const projectKey = `${entry.Job_Entry__c}`;

            if (!projectMap.has(projectKey)) {
                projectMap.set(projectKey, {
                    projectId: entry.Job_Entry__r?.Job__r?.Project__c,
                    projectName: entry.Job_Entry__r?.Job__r?.Project__r ? entry.Job_Entry__r.Job__r.Project__r.Name : 'Project',
                    jobId: entry.Job_Entry__r?.Job__c,
                    jobName: entry.Job_Entry__r?.Job__r?.Name || 'Job',
                    jobEntryId: entry.Job_Entry__c,
                    entriesByDate: {}
                });
            }
            projectMap.get(projectKey).entriesByDate[entry.Date__c] = entry.Hours__c;
        });

        const rows = [];
        projectMap.forEach(project => {
            const days = this.monthDays.map(dayInfo => ({
                ...dayInfo,
                hours: project.entriesByDate[dayInfo.date] !== undefined ? String(project.entriesByDate[dayInfo.date]) : ''
            }));

            rows.push({
                projectId: project.projectId,
                projectName: project.projectName,
                jobId: project.jobId,
                jobName: project.jobName,
                jobEntryId: project.jobEntryId,
                days: days,
                rowTotal: '0.00'
            });
        });

        this.matrixRows = rows;
        this.recalculateTotals();
    }

    @wire(getActiveClients, {contactId: '$_recordId'})
    wiredClients({ error, data }) {
        if (data) {
            this.clientOptions = data.map(c => ({ label: c.Name, value: c.Id }));
        } else if (error) {
            this.clientOptions = [];
        }
    }

    @wire(getActiveProjects, { clientId: '$selectedClientId' , contactId: '$_recordId'})
    wiredProjects({ error, data }) {
        if (data) {
            this.projectOptions = data.map(p => ({ label: p.Name, value: p.Id }));
        } else {
            this.projectOptions = [];
        }
    }
    
    @wire(getActiveJobs, { contactId: '$_recordId', selectedProjectId: '$selectedProjectId'})
    wiredJobs({ error, data }) {
        if (data) {
            this.jobOptions = data.map(j => ({ label: j.Name, value: j.Id }));
        } else {
            this.jobOptions = [];
        }
    }

    @wire(getJobEntryId, {contactId: '$_recordId', jobId: '$selectedJobId'})
    wiredJobEntry({error, data}){
        if (data) {
            this.currentJobEntryId = data;
        } else {
            this.currentJobEntryId = '';
        }
    }

    handleMonthChange(event) {
        this.selectedMonth = event.target.value;
        this.generateMonthDays();
        this.loadExistingTimeEntries();
    }

    handleClientChange(event) {
        this.selectedClientId = event.detail.value;
        this.selectedProjectId = '';
        this.selectedJobId = '';
        this.currentJobEntryId = '';
        this.projectOptions = [];
        this.jobOptions = [];
    }

    handleProjectChange(event) {
        this.selectedProjectId = event.detail.value;
        this.selectedJobId = '';
        this.currentJobEntryId = '';
        this.jobOptions = [];
    }

    handleJobChange(event){
        this.selectedJobId = event.detail.value;
        this.currentJobEntryId = '';
    }

    async handleAddProject() {
        if (!this.selectedProjectId || !this.selectedJobId) {
            this.showToast('Warning', 'Please select both a Project and a Job.', 'warning');
            return;
        }

        if (!this.currentJobEntryId) {
            this.showToast('Warning', 'No Job Entry assignment found for the selected Job and Contact.', 'warning');
            return;
        }

        const jobEntryId = this.currentJobEntryId;

        const exists = this.matrixRows.some(row => row.jobEntryId === jobEntryId);
        if (exists) {
            this.showToast('Warning', 'This Job is already added to the timesheet.', 'warning');
            return;
        }

        const selectedProjectObj = this.projectOptions.find(p => p.value === this.selectedProjectId);
        const selectedJobObj = this.jobOptions.find(j => j.value === this.selectedJobId);

        const newRow = {
            projectId: this.selectedProjectId,
            projectName: selectedProjectObj ? selectedProjectObj.label : 'Project',
            jobId: this.selectedJobId,
            jobName: selectedJobObj ? selectedJobObj.label : 'Job',
            jobEntryId: jobEntryId,
            rowTotal: '0.00',
            days: this.monthDays.map(dayInfo => ({
                ...dayInfo,
                hours: ''
            }))
        };

        this.matrixRows = [...this.matrixRows, newRow];
        this.recalculateTotals();

        // Reset picklists
        this.selectedClientId = '';
        this.selectedProjectId = '';
        this.selectedJobId = '';
        this.currentJobEntryId = '';
        this.projectOptions = [];
        this.jobOptions = [];
    }

    async handleRemoveProject(event) {
        const jobEntryIdToRemove = event.target.dataset.jobentryid;
        const [year, month] = this.selectedMonth.split('-').map(Number);
        const startDate = `${year}-${String(month).padStart(2, '0')}-01`;
        const lastDay = new Date(year, month, 0).getDate();
        const endDate = `${year}-${String(month).padStart(2, '0')}-${String(lastDay).padStart(2, '0')}`;

        try {
            await deleteProjectEntries({
                jobEntryId: jobEntryIdToRemove,
                startDate: startDate,
                endDate: endDate
            });

            this.matrixRows = this.matrixRows.filter(row => row.jobEntryId !== jobEntryIdToRemove);
            this.showToast('Success', 'Project entries deleted successfully.', 'success');

            await this.loadExistingTimeEntries();
        } catch (error) {
            this.showToast('Error', 'Failed to delete project entries: ' + (error.body?.message || error), 'error');
        }
    }

    handleHoursChange(event) {
        const jobEntryId = event.target.dataset.jobentryid;
        const date = event.target.dataset.date;
        let valueStr = event.target.value;
        const valueNum = parseFloat(valueStr);

        // 1. Single Cell Validation: Check for values > 24 or < 0
        if (!isNaN(valueNum) && valueNum > 24) {
            this.showToast('Validation Error', 'Single entry cannot exceed 24 hours.', 'error');
            event.target.value = '';
            valueStr = '';
        } else if (!isNaN(valueNum) && valueNum < 0) {
            this.showToast('Validation Error', 'Logged hours cannot be negative.', 'error');
            event.target.value = '';
            valueStr = '';
        }

        // 2. Update model state
        this.matrixRows = this.matrixRows.map(row => {
            if (row.jobEntryId === jobEntryId) {
                const updatedDays = row.days.map(day => {
                    if (day.date === date) {
                        return { ...day, hours: valueStr };
                    }
                    return day;
                });
                return { ...row, days: updatedDays };
            }
            return row;
        });

        // 3. Recalculate totals
        this.recalculateTotals();

        // 4. Real-time Day Total Check: Warn user if day total exceeds 24
        const dayIndex = this.monthDays.findIndex(d => d.date === date);
        if (dayIndex !== -1 && this.columnTotals[dayIndex]) {
            const dayTotal = this.columnTotals[dayIndex].rawVal;
            if (dayTotal > 24) {
                this.showToast('Warning', `Total hours logged for ${date} exceed 24 hours (${dayTotal.toFixed(2)} hrs).`, 'warning');
            }
        }
    }

    async handleSave() {
        // Validation Check: Prevent save if any single day total exceeds 24 hours
        const invalidDay = this.columnTotals.find(col => col.rawVal > 24);
        if (invalidDay) {
            const invalidDate = this.monthDays[invalidDay.key]?.date;
            this.showToast(
                'Validation Error',
                `Total hours for ${invalidDate} (${invalidDay.val} hrs) exceed the maximum limit of 24 hours. Please correct this before saving.`,
                'error'
            );
            return;
        }

        const entriesToSave = [];
        const entriesToDelete = [];

        this.matrixRows.forEach(row => {
            if (!row.jobEntryId) return;

            row.days.forEach(day => {
                const hoursNum = parseFloat(day.hours);
                const lookupKey = `${row.jobEntryId}_${day.date}`;
                const existingId = this.existingEntryIds.get(lookupKey);

                if (!isNaN(hoursNum) && hoursNum > 0) {
                    const record = {
                        sobjectType: 'Time_Log_Entry__c',
                        Job_Entry__c: row.jobEntryId,
                        Date__c: day.date,
                        Hours__c: hoursNum
                    };

                    if (existingId) {
                        record.Id = existingId;
                    }
                    
                    entriesToSave.push(record);
                } else if (existingId && (isNaN(hoursNum) || hoursNum === 0)) {
                    entriesToDelete.push(existingId);
                }
            });
        });

        if (entriesToSave.length === 0 && entriesToDelete.length === 0) {
            this.showToast('Info', 'No changes detected to save.', 'info');
            return;
        }

        try {
            await saveTimeEntries({ entriesToSave: entriesToSave, entriesToDelete: entriesToDelete });
            this.showToast('Success', 'Timesheet saved successfully!', 'success');
            
            await this.loadExistingTimeEntries();
        } catch (error) {
            this.showToast('Error', 'Failed to save timesheet: ' + (error.body?.message || error), 'error');
        }
    }

    recalculateTotals() {
        let totalSum = 0;
        const colSums = Array(this.monthDays.length).fill(0);

        this.matrixRows.forEach(row => {
            let rowSum = 0;
            row.days.forEach((day, index) => {
                const hrs = parseFloat(day.hours) || 0;
                rowSum += hrs;
                colSums[index] += hrs;
            });
            row.rowTotal = rowSum.toFixed(2);
            totalSum += rowSum;
        });

        this.columnTotals = colSums.map((val, indx) => {
            const isExceeded = val > 24;
            return {
                val: val > 0 ? val.toFixed(2) : '—',
                rawVal: val,
                cellClass: isExceeded 
                    ? 'bg-footer slds-text-align_center slds-text-title_bold total-text slds-text-color_error slds-theme_alert-texture' 
                    : 'bg-footer slds-text-align_center slds-text-title_bold total-text',
                key: indx
            };
        });
        this.grandTotal = totalSum.toFixed(2);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get isProjectDisabled() {
        return !this.selectedClientId;
    }

    get isJobDisabled(){
        return !this.selectedClientId || !this.selectedProjectId;
    }
}