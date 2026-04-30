import { api, LightningElement, track } from 'lwc';
import getPilotRuns from '@salesforce/apex/SpreadWorkbenchController.getPilotRuns';
import getOrCreatePilotRunForLoan from '@salesforce/apex/SpreadWorkbenchController.getOrCreatePilotRunForLoan';
import getMaterialErrors from '@salesforce/apex/SpreadWorkbenchController.getMaterialErrors';
import getSpreadReviewPage from '@salesforce/apex/SpreadWorkbenchController.getSpreadReviewPage';
import getActivePolicyThresholds from '@salesforce/apex/SpreadWorkbenchController.getActivePolicyThresholds';
import getRunSummary from '@salesforce/apex/SpreadScorecardService.getRunSummary';
import calculateForRun from '@salesforce/apex/SpreadScorecardService.calculateForRun';
import certifyPathResults from '@salesforce/apex/SpreadCertificationService.certifyPathResults';
import rejectPathResults from '@salesforce/apex/SpreadCertificationService.rejectPathResults';
import setManualBaseline from '@salesforce/apex/SpreadManualBaselineService.setManualBaseline';
import setReviewedValue from '@salesforce/apex/SpreadAnalystOverrideService.setReviewedValue';
import onUpload from '@salesforce/apex/SpreadDocumentService.onUpload';
import getDocuments from '@salesforce/apex/SpreadDocumentService.getDocuments';
import parseDocument from '@salesforce/apex/SpreadDocumentService.parseDocument';
import parseReadyDocuments from '@salesforce/apex/SpreadDocumentService.parseReadyDocuments';
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
    { label: 'Path', fieldName: 'pathLabel' },
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

const HIDDEN_UI_PATH_KEYS = new Set([
    'manual_ncino_control',
    'ncino_automated_spreading'
]);

const PAGE_SIZE = 25;

export default class CommercialSpreadingPilotWorkbench extends LightningElement {
    @api recordId;
    @api objectApiName;
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

    activeTab = 'corpus';
    selectedReviewDocumentId = '';

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
    isBaselineDialogOpen = false;
    baselinePathResultId = null;
    baselineAmount = null;
    baselineReason = '';
    baselineLineLabel = '';
    baselinePeriodLabel = '';
    isOverrideDialogOpen = false;
    overridePathResultId = null;
    overrideAmount = null;
    overrideReason = '';
    overrideLineLabel = '';
    overridePeriodLabel = '';

    @track documents = [];
    reviewDocumentOptions = [{ label: 'All Documents', value: '' }];
    isUploadingDocs = false;
    _pollingInterval = null;

    @track thresholds = [];
    activePolicy = null;
    isLoadingPolicy = false;

    connectedCallback() {
        this.initializeContext();
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

    get isLoanContext() {
        return this.objectApiName === 'Commercial_Loan__c' && !!this.recordId;
    }

    get showPilotRunPicker() {
        return !this.isLoanContext;
    }

    get workbenchContextLabel() {
        if (this.isLoanContext) {
            return this.selectedRun?.commercialLoanName
                ? `Loan cockpit for ${this.selectedRun.commercialLoanName}`
                : 'Loan cockpit';
        }
        return 'Pilot run workspace';
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

    get isBaselineSaveDisabled() {
        return this.isLoadingReview
            || this.baselineAmount === null
            || this.baselineAmount === undefined
            || !String(this.baselineReason || '').trim();
    }

    get isOverrideSaveDisabled() {
        return this.isLoadingReview
            || this.overrideAmount === null
            || this.overrideAmount === undefined
            || !String(this.overrideReason || '').trim();
    }

    get reviewRowsWithSelection() {
        return this.reviewRows.map((row) => ({
            ...row,
            isSelected: !!this.selectedLineIds[row.lineItemId]
        }));
    }

    get periodColumns() {
        const periods = [...new Set(this.reviewRows.map((row) => row.fiscalPeriod).filter((period) => period && period !== '—'))];
        return periods.sort((left, right) => this.comparePeriods(right, left));
    }

    get analystRowsWithSelection() {
        const periodColumns = this.periodColumns;
        const grouped = new Map();

        this.reviewRows.forEach((row) => {
            const key = [
                row.spreadDocumentId || 'none',
                row.normalizedLine || 'Unmapped',
                row.material ? 'material' : 'nonmaterial'
            ].join('|');

            if (!grouped.has(key)) {
                grouped.set(key, {
                    key,
                    documentName: row.documentName,
                    documentUrl: row.documentUrl,
                    normalizedLine: row.normalizedLine,
                    displayLine: this.formatStoredValue(row.normalizedLine),
                    material: row.material,
                    sourceLineIds: [],
                    sourceRowsByPeriod: {}
                });
            }

            const group = grouped.get(key);
            group.sourceLineIds.push(row.lineItemId);
            group.sourceRowsByPeriod[row.fiscalPeriod] = row;
        });

        return [...grouped.values()].map((group) => {
            const periodCells = periodColumns.map((period) => this.buildAnalystPeriodCell(group.sourceRowsByPeriod[period], period));
            const resultIds = periodCells.map((cell) => cell.pathResultId).filter(Boolean);
            const evidenceUrls = [...new Set(periodCells.map((cell) => cell.evidenceUrl).filter(Boolean))];
            const statuses = periodCells.map((cell) => cell.certificationStatus).filter((status) => status && status !== '—');

            return {
                ...group,
                isSelected: group.sourceLineIds.every((id) => !!this.selectedLineIds[id]),
                periodCells,
                resultIds,
                evidenceUrls,
                statusLabel: this.summarizeStatuses(statuses),
                statusClass: this.certStatusClass(this.summarizeStatuses(statuses)),
                evidenceLabel: evidenceUrls.length > 1 ? `${evidenceUrls.length} evidence links` : 'View Evidence'
            };
        });
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

    async initializeContext() {
        if (this.isLoanContext) {
            await this.loadLoanContext();
        } else {
            await this.loadRuns();
        }
    }

    async loadLoanContext() {
        this.isLoading = true;
        this.clearMessages();
        try {
            const run = await getOrCreatePilotRunForLoan({ commercialLoanId: this.recordId });
            this.selectedRunId = run.id;
            this.selectedRun = run;
            this.runOptions = [{ label: run.label, value: run.id, detail: run }];
            await this.loadSelectedRunData();
        } catch (error) {
            this.handleError(error, 'Unable to initialize loan spreading cockpit.');
        } finally {
            this.isLoading = false;
        }
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
        await this.initializeContext();
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

    handleAnalystRowSelect(event) {
        const rowKey = event.target.dataset.rowKey;
        const checked = event.target.checked;
        const row = this.analystRowsWithSelection.find((item) => item.key === rowKey);
        if (!row) {
            return;
        }

        const updated = { ...this.selectedLineIds };
        row.sourceLineIds.forEach((lineId) => {
            updated[lineId] = checked;
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

    handleAnalystRowCertify(event) {
        const rowKey = event.currentTarget.dataset.rowKey;
        const row = this.analystRowsWithSelection.find((item) => item.key === rowKey);
        this.openDialog('certify', row ? row.resultIds : [], row ? [row.displayLine] : []);
    }

    handleAnalystRowReject(event) {
        const rowKey = event.currentTarget.dataset.rowKey;
        const row = this.analystRowsWithSelection.find((item) => item.key === rowKey);
        this.openDialog('reject', row ? row.resultIds : [], row ? [row.displayLine] : []);
    }

    handleOpenBaselineDialog(event) {
        const pathResultId = event.currentTarget.dataset.pathResultId;
        const manualValue = event.currentTarget.dataset.manualValue;
        const candidateValue = event.currentTarget.dataset.candidateValue;
        const lineLabel = event.currentTarget.dataset.lineLabel;
        const periodLabel = event.currentTarget.dataset.periodLabel;

        this.baselinePathResultId = pathResultId;
        this.baselineAmount = manualValue === undefined || manualValue === null || manualValue === ''
            ? candidateValue
            : manualValue;
        this.baselineReason = '';
        this.baselineLineLabel = lineLabel || '';
        this.baselinePeriodLabel = periodLabel || '';
        this.isBaselineDialogOpen = true;
    }

    handleBaselineAmountChange(event) {
        this.baselineAmount = event.detail.value;
    }

    handleBaselineReasonChange(event) {
        this.baselineReason = event.target.value;
    }

    handleBaselineDialogCancel() {
        this.isBaselineDialogOpen = false;
        this.baselinePathResultId = null;
        this.baselineAmount = null;
        this.baselineReason = '';
        this.baselineLineLabel = '';
        this.baselinePeriodLabel = '';
    }

    handleOpenOverrideDialog(event) {
        const pathResultId = event.currentTarget.dataset.pathResultId;
        const reviewedValue = event.currentTarget.dataset.reviewedValue;
        const candidateValue = event.currentTarget.dataset.candidateValue;
        const lineLabel = event.currentTarget.dataset.lineLabel;
        const periodLabel = event.currentTarget.dataset.periodLabel;

        this.overridePathResultId = pathResultId;
        this.overrideAmount = reviewedValue === undefined || reviewedValue === null || reviewedValue === ''
            ? candidateValue
            : reviewedValue;
        this.overrideReason = '';
        this.overrideLineLabel = lineLabel || '';
        this.overridePeriodLabel = periodLabel || '';
        this.isOverrideDialogOpen = true;
    }

    handleOverrideAmountChange(event) {
        this.overrideAmount = event.detail.value;
    }

    handleOverrideReasonChange(event) {
        this.overrideReason = event.target.value;
    }

    handleOverrideDialogCancel() {
        this.isOverrideDialogOpen = false;
        this.overridePathResultId = null;
        this.overrideAmount = null;
        this.overrideReason = '';
        this.overrideLineLabel = '';
        this.overridePeriodLabel = '';
    }

    async handleOverrideDialogSave() {
        this.isLoadingReview = true;
        this.clearMessages();
        try {
            await setReviewedValue({
                pathResultId: this.overridePathResultId,
                reviewedValue: Number(this.overrideAmount),
                reason: this.overrideReason
            });
            this.message = 'Analyst override saved. The path result is back in Uncertified status until it is reviewed again.';
            this.handleOverrideDialogCancel();
            await this.loadReviewPage();
            this.materialErrors = this.formatMaterialErrors(
                await getMaterialErrors({ pilotRunId: this.selectedRunId })
            );
        } catch (error) {
            this.handleError(error, 'Unable to save analyst override.');
        } finally {
            this.isLoadingReview = false;
        }
    }

    async handleBaselineDialogSave() {
        this.isLoadingReview = true;
        this.clearMessages();
        try {
            await setManualBaseline({
                pathResultId: this.baselinePathResultId,
                manualValue: Number(this.baselineAmount),
                reason: this.baselineReason
            });
            this.message = 'Manual baseline saved. Recalculate scorecards when you are ready to refresh pilot metrics.';
            this.handleBaselineDialogCancel();
            await this.loadReviewPage();
            this.materialErrors = this.formatMaterialErrors(
                await getMaterialErrors({ pilotRunId: this.selectedRunId })
            );
        } catch (error) {
            this.handleError(error, 'Unable to save manual baseline.');
        } finally {
            this.isLoadingReview = false;
        }
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
            this.documents = [];
            this.reviewDocumentOptions = [{ label: 'All Documents', value: '' }];
            return;
        }

        this.isLoading = true;
        this.clearMessages();
        try {
            const [summaries, errors] = await Promise.all([
                getRunSummary({ pilotRunId: this.selectedRunId }),
                getMaterialErrors({ pilotRunId: this.selectedRunId }),
                this.loadDocuments()
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
                materialOnly: this.materialOnly,
                spreadDocumentId: this.selectedReviewDocumentId || null
            });
            this.reviewTotalCount = result.totalCount;
            const visiblePathKeys = result.pathKeys.filter((key) => this.shouldDisplayPath(key));
            this.pathColumns = visiblePathKeys.map((k) => PATH_LABELS[k] || k);
            this.reviewRows = this.buildReviewRows(result.lines, visiblePathKeys);
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
                    return { pathKey: key, pathResultId: null, manualFormatted: '—', candidateFormatted: '—', varianceFormatted: '—', varianceClass: 'path-cell__value', certificationStatus: '—', statusClass: 'cert-status--none', hasManualBaseline: false };
                }
                const hasManualBaseline = pr.manualValue !== null && pr.manualValue !== undefined;
                const variance = pr.varianceAmount ?? 0;
                return {
                    pathKey: key,
                    pathResultId: pr.pathResultId,
                    manualValue: pr.manualValue,
                    candidateValue: pr.candidateValue,
                    reviewedValue: pr.reviewedValue,
                    reviewedReason: pr.reviewedReason,
                    manualFormatted: this.formatCurrency(pr.manualValue),
                    candidateFormatted: this.formatCurrency(pr.candidateValue),
                    reviewedFormatted: this.formatCurrency(pr.reviewedValue),
                    varianceFormatted: hasManualBaseline ? this.formatCurrency(variance) : '—',
                    varianceClass: hasManualBaseline
                        ? (variance > 0 ? 'path-cell__value variance--positive' : variance < 0 ? 'path-cell__value variance--negative' : 'path-cell__value')
                        : 'path-cell__value',
                    certificationStatus: pr.certificationStatus || (hasManualBaseline ? 'Pending' : 'Baseline Needed'),
                    statusClass: this.certStatusClass(pr.certificationStatus),
                    hasManualBaseline,
                    evidenceId: pr.primaryEvidenceId,
                    evidenceUrl: pr.primaryEvidenceId ? `/${pr.primaryEvidenceId}` : null
                };
            });

            return {
                lineItemId: line.lineItemId,
                documentName: line.documentName || 'Unassigned',
                spreadDocumentId: line.spreadDocumentId,
                documentUrl: line.spreadDocumentId ? `/${line.spreadDocumentId}` : null,
                normalizedLine: line.normalizedLine || 'Unmapped',
                displayLine: this.formatStoredValue(line.normalizedLine || 'Unmapped'),
                fiscalPeriod: line.fiscalPeriod || '—',
                material: line.material,
                pathCells
            };
        });
    }

    buildAnalystPeriodCell(row, period) {
        if (!row) {
            return {
                period,
                key: period,
                amountFormatted: '—',
                detailLabel: 'No extracted value',
                certificationStatus: '—',
                statusClass: 'cert-status--none',
                cellClass: 'analyst-amount analyst-amount--empty',
                pathResultId: null,
                evidenceUrl: null
            };
        }

        const cell = row.pathCells.find((pathCell) => pathCell.pathResultId) || row.pathCells[0];
        const hasManualBaseline = !!cell?.hasManualBaseline;
        const hasReviewedOverride = cell?.reviewedValue !== null && cell?.reviewedValue !== undefined;
        const amountFormatted = hasReviewedOverride ? cell?.reviewedFormatted : cell?.candidateFormatted;
        const detailLabel = hasReviewedOverride
            ? `Reviewed from ${cell?.candidateFormatted}`
            : (hasManualBaseline ? 'Extracted | baseline set' : 'Extracted');

        return {
            period,
            key: `${row.lineItemId}-${period}`,
            amountFormatted: amountFormatted || '—',
            detailLabel,
            certificationStatus: cell?.certificationStatus || '—',
            statusClass: cell?.statusClass || 'cert-status--none',
            cellClass: cell?.pathResultId ? 'analyst-amount' : 'analyst-amount analyst-amount--empty',
            pathResultId: cell?.pathResultId,
            evidenceUrl: cell?.evidenceUrl,
            hasManualBaseline,
            manualValue: cell?.manualValue,
            candidateValue: cell?.candidateValue,
            reviewedValue: cell?.reviewedValue,
            reviewedReason: cell?.reviewedReason,
            hasReviewedOverride,
            baselineActionLabel: hasManualBaseline ? 'Edit Baseline' : 'Set Baseline',
            overrideActionLabel: hasReviewedOverride ? 'Edit Override' : 'Set Override'
        };
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

    resetReviewState(resetDocumentFilter = true) {
        this.reviewRows = [];
        this.pathColumns = [];
        this.reviewTotalCount = 0;
        this.reviewOffset = 0;
        this.selectedLineIds = {};
        this.materialOnly = false;
        if (resetDocumentFilter) {
            this.selectedReviewDocumentId = '';
        }
    }

    setSelectedRun() {
        const option = this.runOptions.find((item) => item.value === this.selectedRunId);
        this.selectedRun = option ? option.detail : undefined;
    }

    formatScorecards(summaries) {
        return summaries
            .filter((summary) => this.shouldDisplayPath(summary.pathKey))
            .map((summary) => ({
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
        return errors
            .filter((error) => this.shouldDisplayPath(error.pathKey))
            .map((error) => ({
                ...error,
                pathLabel: PATH_LABELS[error.pathKey] || this.formatStoredValue(error.pathKey),
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

    summarizeStatuses(statuses) {
        if (!statuses.length) {
            return 'Uncertified';
        }
        const uniqueStatuses = [...new Set(statuses)];
        if (uniqueStatuses.length === 1) {
            return uniqueStatuses[0];
        }
        if (uniqueStatuses.includes('Rejected')) {
            return 'Needs Review';
        }
        return 'Mixed';
    }

    comparePeriods(left, right) {
        const leftTime = Date.parse(left);
        const rightTime = Date.parse(right);
        if (!Number.isNaN(leftTime) && !Number.isNaN(rightTime)) {
            return leftTime - rightTime;
        }
        return String(left).localeCompare(String(right));
    }

    shouldDisplayPath(pathKey) {
        return !HIDDEN_UI_PATH_KEYS.has(pathKey);
    }

    clearMessages() {
        this.message = undefined;
        this.errorMessage = undefined;
    }

    handleError(error, fallback) {
        this.errorMessage = error?.body?.message || error?.message || fallback;
        this.message = undefined;
    }

    get hasThresholds() {
        return this.thresholds.length > 0;
    }

    get hasDocuments() {
        return this.documents.length > 0;
    }

    get readyDocumentCount() {
        return this.documents.filter((doc) => doc.canParse).length;
    }

    get hasReadyDocuments() {
        return this.readyDocumentCount > 0;
    }

    get isParseReadyDisabled() {
        return this.isUploadingDocs || !this.hasReadyDocuments;
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
        if (tab === 'policy') {
            await this.loadThresholds();
        }
    }

    async loadThresholds() {
        const portfolio = this.selectedRun?.portfolio || 'C&I';
        this.isLoadingPolicy = true;
        this.clearMessages();
        try {
            const result = await getActivePolicyThresholds({ portfolio });
            this.activePolicy = result;
            this.thresholds = (result?.thresholds || []).map((t) => ({
                ...t,
                severityClass: this.severityBadgeClass(t.severity),
                materialLabel: t.appliesToMaterialLine ? 'Yes' : 'No',
                exceptionLabel: t.requiresExceptionApproval ? 'Yes' : 'No'
            }));
        } catch (error) {
            this.handleError(error, 'Unable to load policy thresholds.');
            this.thresholds = [];
            this.activePolicy = null;
        } finally {
            this.isLoadingPolicy = false;
        }
    }

    severityBadgeClass(severity) {
        if (severity === 'Hard Stop') return 'slds-badge slds-badge_error';
        if (severity === 'Policy Exception') return 'slds-badge slds-badge_warning';
        if (severity === 'Warning') return 'slds-badge';
        return 'slds-badge';
    }

    async handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;
        if (!uploadedFiles || uploadedFiles.length === 0) {
            return;
        }

        this.isUploadingDocs = true;
        this.clearMessages();
        try {
            const contentDocumentIds = uploadedFiles
                .map((f) => f.documentId || f.contentDocumentId)
                .filter((id) => !!id);

            if (contentDocumentIds.length === 0) {
                throw new Error('Upload completed, but Salesforce did not return any document IDs.');
            }

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
            this.reviewDocumentOptions = [{ label: 'All Documents', value: '' }];
            return;
        }

        try {
            const docs = await getDocuments({ pilotRunId: this.selectedRunId });
            this.documents = (docs || []).map((doc) => this.decorateDocument(doc));
            this.reviewDocumentOptions = [
                { label: 'All Documents', value: '' },
                ...this.documents.map((doc) => ({ label: doc.name, value: doc.id }))
            ];
        } catch (error) {
            this.handleError(error, 'Unable to load documents.');
            this.documents = [];
            this.reviewDocumentOptions = [{ label: 'All Documents', value: '' }];
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

    async handleParseReadyDocuments() {
        if (!this.selectedRunId) {
            return;
        }

        this.isUploadingDocs = true;
        this.clearMessages();
        try {
            const result = await parseReadyDocuments({
                pilotRunId: this.selectedRunId,
                pathKey: 'salesforce_native_staging'
            });
            const parts = [
                `Parsed ${result?.parsedCount || 0}`,
                `skipped ${result?.skippedCount || 0}`,
                `failed ${result?.failedCount || 0}`
            ];
            if (result?.messages?.length) {
                this.errorMessage = result.messages.join(' | ');
                this.message = undefined;
            } else {
                this.message = parts.join(', ') + '.';
            }

            await Promise.all([
                this.loadDocuments(),
                this.loadSelectedRunData()
            ]);
            const firstParsedOrReadyDocument = this.documents.find((doc) => doc.parsingStatus === 'Complete') ||
                this.documents.find((doc) => doc.canParse);
            this.selectedReviewDocumentId = firstParsedOrReadyDocument ? firstParsedOrReadyDocument.id : '';
            this.activeTab = 'review';
            this.resetReviewState(false);
            await this.loadReviewPage();
        } catch (error) {
            this.handleError(error, 'Bulk parse failed.');
        } finally {
            this.isUploadingDocs = false;
        }
    }

    async handleParseDocument(event) {
        const docId = event.currentTarget.dataset.docId;
        this.isUploadingDocs = true;
        this.clearMessages();
        try {
            const result = await parseDocument({
                spreadDocumentId: docId,
                pathKey: 'salesforce_native_staging'
            });
            if (result?.errorMessage) {
                this.errorMessage = result.errorMessage;
                this.message = undefined;
            } else {
                this.message = `Parsed ${result?.lineItemCount || 0} draft line(s) into ${result?.pathResultCount || 0} path result(s).`;
                this.selectedReviewDocumentId = docId;
                this.activeTab = 'review';
            }
            await Promise.all([
                this.loadDocuments(),
                this.loadSelectedRunData()
            ]);
            this.resetReviewState(false);
            await this.loadReviewPage();
        } catch (error) {
            this.handleError(error, 'Parse failed.');
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
                this.isTerminalStatus(doc.extractionStatus)
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

    statusClass(status) {
        if (!status) return 'slds-badge';
        if (status === 'Complete') return 'slds-badge slds-badge_success';
        if (status === 'Failed') return 'slds-badge slds-badge_error';
        if (status === 'Needs Review') return 'slds-badge slds-badge_warning';
        if (status === 'Pending' || status === 'In Progress') return 'slds-badge slds-badge_lighten';
        return 'slds-badge';
    }

    isTerminalStatus(status) {
        return status === 'Complete' || status === 'Failed' || status === 'Needs Review';
    }

    formatStoredValue(value) {
        if (!value) {
            return '—';
        }

        return String(value)
            .replace(/[_-]+/g, ' ')
            .replace(/\s+/g, ' ')
            .trim()
            .replace(/\b\w/g, (char) => char.toUpperCase());
    }

    decorateDocument(doc) {
        const extractionStatus = doc.extractionStatus || 'Not Started';
        const parsingStatus = doc.parsingStatus || 'Not Started';
        const parsingDisplayStatus = parsingStatus === 'Needs Review' ? 'Complete' : parsingStatus;
        const evidenceCount = doc.evidenceCount || 0;
        const canRetryExtraction = extractionStatus === 'Failed';
        const canParse =
            extractionStatus === 'Complete' &&
            evidenceCount > 0 &&
            parsingStatus !== 'Complete' &&
            parsingStatus !== 'In Progress' &&
            parsingStatus !== 'Needs Review';
        let parseAvailabilityReason = 'Ready to parse';

        if (!canParse) {
            if (extractionStatus === 'Failed') {
                parseAvailabilityReason = 'Extraction failed. Retry extraction.';
            } else if (extractionStatus === 'Needs Review') {
                parseAvailabilityReason = 'Extraction needs review before parse.';
            } else if (extractionStatus !== 'Complete') {
                parseAvailabilityReason = 'Waiting for extraction to finish';
            } else if (evidenceCount === 0) {
                parseAvailabilityReason = 'No extraction evidence found';
            } else if (parsingStatus === 'Complete') {
                parseAvailabilityReason = 'Already parsed';
            } else if (parsingStatus === 'In Progress') {
                parseAvailabilityReason = 'Parsing in progress';
            } else if (parsingStatus === 'Needs Review') {
                parseAvailabilityReason = 'Parsed. Review required.';
            } else {
                parseAvailabilityReason = 'Review document status';
            }
        }

        return {
            ...doc,
            recordUrl: doc.id ? `/${doc.id}` : null,
            documentType: this.formatStoredValue(doc.documentType),
            statementType: this.formatStoredValue(doc.statementType),
            documentStore: this.formatStoredValue(doc.documentStore),
            scenarioType: this.formatStoredValue(doc.scenarioType),
            extractionStatus,
            parsingStatus,
            parsingDisplayStatus,
            evidenceCount,
            extractionStatusClass: this.statusClass(extractionStatus),
            parsingStatusClass: this.statusClass(parsingDisplayStatus),
            canRetryExtraction,
            canParse,
            parseAvailabilityReason
        };
    }

    async handleReviewDocumentChange(event) {
        this.selectedReviewDocumentId = event.detail.value;
        this.reviewOffset = 0;
        this.selectedLineIds = {};
        await this.loadReviewPage();
    }
}
