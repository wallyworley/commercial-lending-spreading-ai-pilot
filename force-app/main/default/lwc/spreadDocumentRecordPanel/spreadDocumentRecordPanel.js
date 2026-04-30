import { LightningElement, api, wire } from 'lwc';
import getDocumentView from '@salesforce/apex/SpreadDocumentRecordPageController.getDocumentView';
import { refreshApex } from '@salesforce/apex';

const HIDDEN_UI_PATH_KEYS = new Set([
    'manual_ncino_control',
    'ncino_automated_spreading'
]);

const EVIDENCE_COLUMNS = [
    {
        label: 'Evidence',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'evidenceName' }, target: '_blank' }
    },
    { label: 'Provider', fieldName: 'providerLabel' },
    { label: 'Engine', fieldName: 'extractionEngineLabel' },
    { label: 'Type', fieldName: 'evidenceTypeLabel' },
    { label: 'Page', fieldName: 'sourcePage', type: 'number' },
    { label: 'Confidence', fieldName: 'confidenceLabel' },
    { label: 'Status', fieldName: 'extractionStatus' }
];

const LINE_ITEM_COLUMNS = [
    {
        label: 'Line Item',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'lineItemName' }, target: '_blank' }
    },
    { label: 'Normalized Line', fieldName: 'normalizedLine' },
    { label: 'Statement', fieldName: 'statementTypeLabel' },
    { label: 'Period', fieldName: 'fiscalPeriod' },
    { label: 'Material', fieldName: 'material', type: 'boolean' },
    { label: 'In Report', fieldName: 'includeInReport', type: 'boolean' },
    { label: 'Evidence', fieldName: 'evidenceUrl', type: 'url', typeAttributes: { label: 'View', target: '_blank' } }
];

const PATH_RESULT_COLUMNS = [
    {
        label: 'Path Result',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'pathResultName' }, target: '_blank' }
    },
    { label: 'Path', fieldName: 'pathLabel' },
    { label: 'Spread Line', fieldName: 'normalizedLine' },
    { label: 'Manual', fieldName: 'manualValue', type: 'currency' },
    { label: 'Candidate', fieldName: 'candidateValue', type: 'currency' },
    { label: 'Variance', fieldName: 'varianceAmount', type: 'currency' },
    { label: 'Status', fieldName: 'certificationStatus' },
    { label: 'Evidence', fieldName: 'evidenceUrl', type: 'url', typeAttributes: { label: 'View', target: '_blank' } }
];

const EXCEPTION_COLUMNS = [
    {
        label: 'Exception',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'exceptionName' }, target: '_blank' }
    },
    { label: 'Severity', fieldName: 'severity' },
    { label: 'Reason', fieldName: 'reason' },
    { label: 'Created', fieldName: 'createdDate', type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } }
];

export default class SpreadDocumentRecordPanel extends LightningElement {
    @api recordId;

    evidenceColumns = EVIDENCE_COLUMNS;
    lineItemColumns = LINE_ITEM_COLUMNS;
    pathResultColumns = PATH_RESULT_COLUMNS;
    exceptionColumns = EXCEPTION_COLUMNS;

    view;
    errorMessage;
    wiredViewResult;

    @wire(getDocumentView, { spreadDocumentId: '$recordId' })
    wiredDocumentView(result) {
        this.wiredViewResult = result;
        const { data, error } = result;

        if (data) {
            this.view = this.decorateView(data);
            this.errorMessage = undefined;
        } else if (error) {
            this.view = undefined;
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load document review context.';
        }
    }

    get summary() {
        return this.view?.summary;
    }

    get evidenceRows() {
        return this.view?.evidences || [];
    }

    get lineItemRows() {
        return this.view?.lineItems || [];
    }

    get pathResultRows() {
        return this.view?.pathResults || [];
    }

    get exceptionRows() {
        return this.view?.exceptions || [];
    }

    get hasEvidence() {
        return this.evidenceRows.length > 0;
    }

    get hasLineItems() {
        return this.lineItemRows.length > 0;
    }

    get hasPathResults() {
        return this.pathResultRows.length > 0;
    }

    get hasExceptions() {
        return this.exceptionRows.length > 0;
    }

    get summaryFacts() {
        if (!this.summary) {
            return [];
        }

        return [
            { label: 'Pilot Run', value: this.summary.pilotRunName || '—', url: this.summary.pilotRunId ? `/${this.summary.pilotRunId}` : null },
            { label: 'Borrower', value: this.summary.borrowerName || 'Unassigned', url: null },
            { label: 'Extraction', value: this.summary.extractionStatus || 'Not Started', url: null },
            { label: 'Parsing', value: this.summary.parsingStatus || 'Not Started', url: null },
            { label: 'Pages', value: this.summary.pageCount ?? '—', url: null },
            { label: 'Extracted', value: this.formatDate(this.summary.extractedAt), url: null },
            { label: 'Parsed', value: this.formatDate(this.summary.parsedAt), url: null }
        ];
    }

    get statBadges() {
        if (!this.summary) {
            return [];
        }

        return [
            { label: 'Evidence', value: this.summary.evidenceCount || 0 },
            { label: 'Spread Lines', value: this.summary.lineItemCount || 0 },
            { label: 'Path Results', value: this.summary.pathResultCount || 0 },
            { label: 'Exceptions', value: this.summary.exceptionCount || 0 }
        ];
    }

    async handleRefresh() {
        if (this.wiredViewResult) {
            await refreshApex(this.wiredViewResult);
        }
    }

    decorateView(data) {
        return {
            ...data,
            evidences: (data.evidences || []).map((row) => ({
                ...row,
                recordUrl: `/${row.evidenceId}`,
                providerLabel: this.formatStoredValue(row.provider),
                extractionEngineLabel: this.formatStoredValue(row.extractionEngine),
                evidenceTypeLabel: this.formatStoredValue(row.evidenceType),
                confidenceLabel: row.extractionConfidence === null || row.extractionConfidence === undefined
                    ? '—'
                    : `${(Number(row.extractionConfidence) * 100).toFixed(0)}%`
            })),
            lineItems: (data.lineItems || []).map((row) => ({
                ...row,
                recordUrl: `/${row.lineItemId}`,
                statementTypeLabel: this.formatStoredValue(row.statementType),
                evidenceUrl: row.primaryEvidenceId ? `/${row.primaryEvidenceId}` : null
            })),
            pathResults: (data.pathResults || [])
                .filter((row) => !HIDDEN_UI_PATH_KEYS.has(row.pathKey))
                .map((row) => ({
                    ...row,
                    recordUrl: `/${row.pathResultId}`,
                    pathLabel: this.pathLabel(row.pathKey),
                    evidenceUrl: row.primaryEvidenceId ? `/${row.primaryEvidenceId}` : null
                })),
            exceptions: (data.exceptions || []).map((row) => ({
                ...row,
                recordUrl: `/${row.exceptionId}`
            }))
        };
    }

    pathLabel(pathKey) {
        const labels = {
            salesforce_native_staging: 'Salesforce Native Staging',
            manual_ncino_control: 'Manual nCino Control',
            ncino_automated_spreading: 'nCino Automated Spreading'
        };
        return labels[pathKey] || this.formatStoredValue(pathKey);
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

    formatDate(value) {
        if (!value) {
            return '—';
        }

        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: 'numeric',
            minute: '2-digit'
        }).format(new Date(value));
    }
}
