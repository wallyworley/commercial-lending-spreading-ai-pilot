import { LightningElement, track } from 'lwc';
import getPilotRuns from '@salesforce/apex/SpreadWorkbenchController.getPilotRuns';
import getMaterialErrors from '@salesforce/apex/SpreadWorkbenchController.getMaterialErrors';
import getSpreadReviewPage from '@salesforce/apex/SpreadWorkbenchController.getSpreadReviewPage';
import getRunSummary from '@salesforce/apex/SpreadScorecardService.getRunSummary';
import calculateForRun from '@salesforce/apex/SpreadScorecardService.calculateForRun';
import certifyPathResults from '@salesforce/apex/SpreadCertificationService.certifyPathResults';
import rejectPathResults from '@salesforce/apex/SpreadCertificationService.rejectPathResults';
import onUpload from '@salesforce/apex/SpreadDocumentService.onUpload';
import getDocuments from '@salesforce/apex/SpreadDocumentService.getDocuments';
import retryExtraction from '@salesforce/apex/SpreadDocumentService.retryExtraction';

const SCORECARD_COLUMNS = [
    { label: 'Path', fieldName: 'pathLabel' },
    { label: 'Decision', fieldName: 'decisionLabel' },
    { label: 'Exact Match', fieldName: 'exactMatchLabel' },
    { label: 'Dollar Accuracy', fieldName: 'dollarAccuracyLabel' },
    { label: 'Time Reduction', fieldName: 'timeReductionLabel' },
    { label: 'Certification', fieldName: 'certificationRateLabel' },
    { label: 'Uncaught Material Errors', fieldName: 'uncaughtMaterialErrors', type: 'number' },
    { label: 'Lines', fieldName: 'lineItemCount', type: 'number' }
];

const ERROR_COLUMNS = [
    { label: 'Borrower', fieldName: 'borrowerName' },
    { label: 'Document', fieldName: 'documentName' },
    { label: 'Path', fieldName: 'pathKey' },
    { label: 'Spread Line', fieldName: 'normalizedLine' },
    { label: 'Manual', fieldName: 'manualValue', type: 'currency' },
    { label: 'Candidate', fieldName: 'candidateValue', type: 'currency' },
    { label: 'Variance', fieldName: 'varianceAmount', type: 'currency' },
    { label: 'Status', fieldName: 'certificationStatus' }
];

const PATH_LABELS = {
    manual_ncino_control: 'Manual nCino Control',
    ncino_automated_spreading: 'nCino Automated Spreading',
    salesforce_native_staging: 'Salesforce Native Staging'
};

const PAGE_SIZE = 25;

export default class CommercialSpreadingPilotWorkbench extends LightningElement {
    scorecardColumns = SCORECARD_COLUMNS;
    errorColumns = ERROR_COLUMNS;
    runOptions = [];
    selectedRunId;
    @track selectedRun;
    @track scorecards = [];
    @track materialErrors = [];
    isLoading = false;
    isCalculating = false;
    message;
    errorMessage;

    activeTab = 'overview';

    @track reviewRows = [];
    pathColumns = [];
    reviewTotalCount = 0;
    reviewOffset = 0;
    materialOnly = false;
    isLoadingReview = false;
    @track selectedLineIds = {};

    isDialogOpen = false;
    dialogTitle = '';
    dialogBody = '';
    dialogLines = [];
    _pendingAction = null;
    _pendingIds = [];

    @track documents = [];
    isUploadingDocs = false;
    _pollingInterval = null;

    connectedCallback() {
        this.loadRuns();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    renderedCallback() {
        if (this.isDialogOpen) {
            const confirmBtn = this.template.querySelector('.slds-modal__footer lightning-button[label="Confirm"]');
            if (confirmBtn) {
                confirmBtn.focus();
            }
        }
    }

    get hasRuns() {
        return this.runOptions.length > 0;
    }

    get hasScorecards() {
        return this.scorecards.length > 0;
    }

    get hasMaterialErrors() {
        return this.materialErrors.length > 0;
    }

    get hasReviewRows() {
        return this.reviewRows.length > 0 && !this.isLoadingReview;
    }

    get isReviewEmpty() {
        return !this.isLoadingReview && this.reviewRows.length === 0 && this.activeTab === 'review';
    }

    get selectedRunSummary() {
        if (!this.selectedRun) {
            return 'No pilot run selected.';
        }
        const documentText = this.selectedRun.documentCount === 1 ? 'document' : 'documents';
        const lineText = this.selectedRun.lineItemCount === 1 ? 'line' : 'lines';
        return `${this.selectedRun.status || 'Unspecified'} | ${this.selectedRun.portfolio || 'No portfolio'} | ${this.selectedRun.documentCount} ${documentText} | ${this.selectedRun.lineItemCount} ${lineText}`;
    }

    get reviewCountLabel() {
        return `${this.reviewTotalCount} line${this.reviewTotalCount === 1 ? '' : 's'} total`;
    }

    get selectedLineCount() {
        return Object.keys(this.selectedLineIds).filter((k) => this.selectedLineIds[k]).length;
    }

    get hasSelectedLines() {
        return this.selectedLineCount > 0;
    }

    get selectedCountLabel() {
        const n = this.selectedLineCount;
        return `${n} line${n === 1 ? '' : 's'} selected`;
    }

    get allSelected() {
        return this.reviewRows.length > 0 && this.reviewRows.every((row) => this.selectedLineIds[row.lineItemId]);
    }

    get reviewRowsWithSelection() {
        return this.reviewRows.map((row) => ({
            ...row,
            isSelected: !!this.selectedLineIds[row.lineItemId]
        }));
    }

    get pageLabel() {
        if (this.reviewTotalCount === 0) {
            return '0 results';
        }
        const start = this.reviewOffset + 1;
        const end = Math.min(this.reviewOffset + this.reviewRows.length, this.reviewTotalCount);
        return `${start}–${end} of ${this.reviewTotalCount}`;
    }

    get isPrevDisabled() {
        return this.reviewOffset === 0 || this.isLoadingReview;
    }

    get isNextDisabled() {
        return this.reviewOffset + PAGE_SIZE >= this.reviewTotalCount || this.isLoadingReview;
    }

    async loadRuns() {
        this.isLoading = true;
        this.clearMessages();
        try {
            const runs = await getPilotRuns();
            this.runOptions = runs.map((run) => ({
                label: run.label,
                value: run.id,
                detail: run
            }));

            if (this.runOptions.length > 0) {
                this.selectedRunId = this.selectedRunId || this.runOptions[0].value;
                this.setSelectedRun();
                await this.loadSelectedRunData();
            }
        } catch (error) {
            this.handleError(error, 'Unable to load pilot runs.');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRunChange(event) {
        this.selectedRunId = event.detail.value;
        this.setSelectedRun();
        this.resetReviewState();
        await this.loadSelectedRunData();
        if (this.activeTab === 'review') {
            await this.loadReviewPage();
        }
    }

    async handleRefresh() {
        await this.loadRuns();
        if (this.activeTab === 'review') {
            this.resetReviewState();
            await this.loadReviewPage();
        }
    }

    async handleCalculate() {
        if (!this.selectedRunId) {
            return;
        }

        this.isCalculating = true;
        this.clearMessages();
        try {
            const summaries = await calculateForRun({ pilotRunId: this.selectedRunId });
            this.scorecards = this.formatScorecards(summaries);
            this.materialErrors = this.formatMaterialErrors(
                await getMaterialErrors({ pilotRunId: this.selectedRunId })
            );
            this.message = 'Scorecards recalculated from current path results.';
        } catch (error) {
            this.handleError(error, 'Unable to calculate scorecards.');
        } finally {
            this.isCalculating = false;
        }
    }

    async handleTabSelect(event) {
        const tab = event.detail.value;
        this.activeTab = tab;
        if (tab === 'review' && this.selectedRunId && this.reviewRows.length === 0) {
            await this.loadReviewPage();
        }
    }

    async handleMaterialToggle(event) {
        this.materialOnly = event.target.checked;
        this.reviewOffset = 0;
        this.selectedLineIds = {};
        await this.loadReviewPage();
    }

    async handlePrevPage() {
        this.reviewOffset = Math.max(0, this.reviewOffset - PAGE_SIZE);
        this.selectedLineIds = {};
        await this.loadReviewPage();
    }

    async handleNextPage() {
        this.reviewOffset = this.reviewOffset + PAGE_SIZE;
        this.selectedLineIds = {};
        await this.loadReviewPage();
    }

    handleRowSelect(event) {
        const lineId = event.target.dataset.lineId;
        const checked = event.target.checked;
        this.selectedLineIds = { ...this.selectedLineIds, [lineId]: checked };
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        const updated = { ...this.selectedLineIds };
        this.reviewRows.forEach((row) => {
            updated[row.lineItemId] = checked;
        });
        this.selectedLineIds = updated;
    }

    handleRowCertify(event) {
        const lineId = event.currentTarget.dataset.lineId;
        const row = this.reviewRows.find((r) => r.lineItemId === lineId);
        const ids = row ? row.pathCells.map((c) => c.pathResultId).filter(Boolean) : [];
        this.openDialog('certify', ids, row ? [row.normalizedLine] : []);
    }

    handleRowReject(event) {
        const lineId = event.currentTarget.dataset.lineId;
        const row = this.reviewRows.find((r) => r.lineItemId === lineId);
        const ids = row ? row.pathCells.map((c) => c.pathResultId).filter(Boolean) : [];
        this.openDialog('reject', ids, row ? [row.normalizedLine] : []);
    }

    handleBulkCertify() {
        const { ids, lines } = this.getSelectedPathResultIds();
        this.openDialog('certify', ids, lines);
    }

    handleBulkReject() {
        const { ids, lines } = this.getSelectedPathResultIds();
        this.openDialog('reject', ids, lines);
    }

    openDialog(action, ids, lines) {
        if (!ids.length) {
            return;
        }
        this._pendingAction = action;
        this._pendingIds = ids;
        this.dialogLines = lines;
        if (action === 'certify') {
            this.dialogTitle = 'Confirm Certification';
            this.dialogBody = `Certify path results for ${lines.length} line${lines.length === 1 ? '' : 's'}?`;
        } else {
            this.dialogTitle = 'Confirm Rejection';
            this.dialogBody = `Reject path results for ${lines.length} line${lines.length === 1 ? '' : 's'}?`;
        }
        this.isDialogOpen = true;
    }

    async handleDialogConfirm() {
        this.isDialogOpen = false;
        const action = this._pendingAction;
        const ids = this._pendingIds;
        this._pendingAction = null;
        this._pendingIds = [];

        this.isLoadingReview = true;
        this.clearMessages();
        try {
            if (action === 'certify') {
                await certifyPathResults({ pathResultIds: ids });
                this.message = `${ids.length} path result${ids.length === 1 ? '' : 's'} certified.`;
            } else {
                await rejectPathResults({ pathResultIds: ids });
                this.message = `${ids.length} path result${ids.length === 1 ? '' : 's'} rejected.`;
            }
            this.selectedLineIds = {};
            await this.loadReviewPage();
        } catch (error) {
            this.handleError(error, 'Unable to update certification status.');
        } finally {
            this.isLoadingReview = false;
        }
    }

    handleDialogCancel() {
        this.isDialogOpen = false;
        this._pendingAction = null;
        this._pendingIds = [];
    }

    handleDialogKeydown(event) {
        if (event.key === 'Escape') {
            this.handleDialogCancel();
        } else if (event.key === 'Enter') {
            this.handleDialogConfirm();
        }
    }

    async loadSelectedRunData() {
        if (!this.selectedRunId) {
            this.scorecards = [];
            this.materialErrors = [];
            return;
        }

        this.isLoading = true;
        this.clearMessages();
        try {
            const [summaries, errors] = await Promise.all([
                getRunSummary({ pilotRunId: this.selectedRunId }),
                getMaterialErrors({ pilotRunId: this.selectedRunId })
            ]);
            this.scorecards = this.formatScorecards(summaries);
            this.materialErrors = this.formatMaterialErrors(errors);
        } catch (error) {
            this.handleError(error, 'Unable to load selected pilot run.');
        } finally {
            this.isLoading = false;
        }
    }

    async loadReviewPage() {
        if (!this.selectedRunId) {
            return;
        }
        this.isLoadingReview = true;
        try {
            const result = await getSpreadReviewPage({
                pilotRunId: this.selectedRunId,
                pageSize: PAGE_SIZE,
                pageOffset: this.reviewOffset,
                materialOnly: this.materialOnly
            });
            this.reviewTotalCount = result.totalCount;
            this.pathColumns = result.pathKeys.map((k) => PATH_LABELS[k] || k);
            this.reviewRows = this.buildReviewRows(result.lines, result.pathKeys);
        } catch (error) {
            this.handleError(error, 'Unable to load spread review page.');
        } finally {
            this.isLoadingReview = false;
        }
    }

    buildReviewRows(lines, pathKeys) {
        return lines.map((line) => {
            const resultByPath = {};
            (line.pathResults || []).forEach((pr) => {
                resultByPath[pr.pathKey] = pr;
            });

            const pathCells = pathKeys.map((key) => {
                const pr = resultByPath[key];
                if (!pr) {
                    return { pathKey: key, pathResultId: null, manualFormatted: '—', candidateFormatted: '—', varianceFormatted: '—', varianceClass: 'path-cell__value', certificationStatus: '—', statusClass: 'cert-status--none' };
                }
                const variance = pr.varianceAmount ?? 0;
                return {
                    pathKey: key,
                    pathResultId: pr.pathResultId,
                    manualFormatted: this.formatCurrency(pr.manualValue),
                    candidateFormatted: this.formatCurrency(pr.candidateValue),
                    varianceFormatted: this.formatCurrency(variance),
                    varianceClass: variance > 0 ? 'path-cell__value variance--positive' : variance < 0 ? 'path-cell__value variance--negative' : 'path-cell__value',
                    certificationStatus: pr.certificationStatus || 'Pending',
                    statusClass: this.certStatusClass(pr.certificationStatus)
                };
            });

            return {
                lineItemId: line.lineItemId,
                normalizedLine: line.normalizedLine || 'Unmapped',
                fiscalPeriod: line.fiscalPeriod || '—',
                material: line.material,
                pathCells
            };
        });
    }

    getSelectedPathResultIds() {
        const ids = [];
        const lines = [];
        this.reviewRows.forEach((row) => {
            if (this.selectedLineIds[row.lineItemId]) {
                lines.push(row.normalizedLine);
                row.pathCells.forEach((cell) => {
                    if (cell.pathResultId) {
                        ids.push(cell.pathResultId);
                    }
                });
            }
        });
        return { ids, lines };
    }

    resetReviewState() {
        this.reviewRows = [];
        this.pathColumns = [];
        this.reviewTotalCount = 0;
        this.reviewOffset = 0;
        this.selectedLineIds = {};
        this.materialOnly = false;
    }

    setSelectedRun() {
        const option = this.runOptions.find((item) => item.value === this.selectedRunId);
        this.selectedRun = option ? option.detail : undefined;
    }

    formatScorecards(summaries) {
        return summaries.map((summary) => ({
            ...summary,
            pathLabel: PATH_LABELS[summary.pathKey] || summary.pathKey,
            decisionLabel: summary.passed ? 'Pass' : 'Block',
            exactMatchLabel: this.formatPercent(summary.exactMatchRate),
            dollarAccuracyLabel: this.formatPercent(summary.dollarWeightedAccuracy),
            timeReductionLabel: this.formatPercent(summary.timeReduction),
            certificationRateLabel: this.formatPercent(summary.certificationRate)
        }));
    }

    formatMaterialErrors(errors) {
        return errors.map((error) => ({
            ...error,
            borrowerName: error.borrowerName || 'Unassigned',
            documentName: error.documentName || 'Unassigned',
            normalizedLine: error.normalizedLine || 'Unmapped'
        }));
    }

    formatPercent(value) {
        if (value === null || value === undefined) {
            return '0.00%';
        }
        return `${(Number(value) * 100).toFixed(2)}%`;
    }

    formatCurrency(value) {
        if (value === null || value === undefined) {
            return '—';
        }
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(Number(value));
    }

    certStatusClass(status) {
        if (!status) {
            return 'cert-status--none';
        }
        const map = {
            Certified: 'cert-status--certified',
            Rejected: 'cert-status--rejected',
            'Exception Approved': 'cert-status--exception',
            Pending: 'cert-status--none'
        };
        return map[status] || 'cert-status--none';
    }

    clearMessages() {
        this.message = undefined;
        this.errorMessage = undefined;
    }

    handleError(error, fallback) {
        this.errorMessage = error?.body?.message || error?.message || fallback;
        this.message = undefined;
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    async handleTabSelect(event) {
        const tab = event.detail.value;
        this.activeTab = tab;
        if (tab === 'review' && this.selectedRunId && this.reviewRows.length === 0) {
            await this.loadReviewPage();
        }
        if (tab === 'corpus' && this.selectedRunId) {
            await this.loadDocuments();
        }
    }

    async handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (!uploadedFiles || uploadedFiles.length === 0) {
            return;
        }

        this.isUploadingDocs = true;
        this.clearMessages();
        try {
            const contentDocumentIds = uploadedFiles.map((f) => f.contentDocumentId);
            await onUpload({ pilotRunId: this.selectedRunId, contentDocumentIds });
            this.message = `Uploaded ${uploadedFiles.length} document(s). Processing...`;
            await this.loadDocuments();
            this.startPolling();
        } catch (error) {
            this.handleError(error, 'Upload failed.');
        } finally {
            this.isUploadingDocs = false;
        }
    }

    async loadDocuments() {
        if (!this.selectedRunId) {
            this.documents = [];
            return;
        }

        try {
            const docs = await getDocuments({ pilotRunId: this.selectedRunId });
            this.documents = docs || [];
        } catch (error) {
            this.handleError(error, 'Unable to load documents.');
            this.documents = [];
        }
    }

    async handleRetryExtraction(event) {
        const docId = event.currentTarget.dataset.docId;
        this.isUploadingDocs = true;
        this.clearMessages();
        try {
            await retryExtraction({ spreadDocumentId: docId });
            this.message = 'Extraction retried.';
            await this.loadDocuments();
            this.startPolling();
        } catch (error) {
            this.handleError(error, 'Retry failed.');
        } finally {
            this.isUploadingDocs = false;
        }
    }

    startPolling() {
        if (this._pollingInterval) {
            this.stopPolling();
        }
        this._pollingInterval = setInterval(async () => {
            await this.loadDocuments();
            const allTerminal = this.documents.every((doc) =>
                doc.extractionStatus === 'Complete' ||
                doc.extractionStatus === 'Failed' ||
                doc.extractionStatus === 'Needs Review'
            );
            if (allTerminal) {
                this.stopPolling();
            }
        }, 5000);
    }

    stopPolling() {
        if (this._pollingInterval) {
            clearInterval(this._pollingInterval);
            this._pollingInterval = null;
        }
    }

    getStatusClass(status) {
        if (!status) return 'slds-badge';
        if (status === 'Complete') return 'slds-badge slds-badge_success';
        if (status === 'Failed') return 'slds-badge slds-badge_error';
        if (status === 'Needs Review') return 'slds-badge slds-badge_warning';
        if (status === 'Pending' || status === 'In Progress') return 'slds-badge slds-badge_lighten';
        return 'slds-badge';
    }

    isFailedStatus(status) {
        return status === 'Failed';
    }
}
