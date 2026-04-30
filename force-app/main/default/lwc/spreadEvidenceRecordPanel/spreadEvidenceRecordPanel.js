import { LightningElement, api, wire } from 'lwc';
import getEvidenceView from '@salesforce/apex/SpreadEvidenceRecordPageController.getEvidenceView';

export default class SpreadEvidenceRecordPanel extends LightningElement {
    @api recordId;
    view;
    errorMessage;
    isLoading = true;

    @wire(getEvidenceView, { evidenceId: '$recordId' })
    wiredEvidence({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.view = data;
            this.errorMessage = undefined;
            return;
        }

        if (error) {
            this.view = undefined;
            this.errorMessage = error.body?.message || 'Unable to load evidence context.';
        }
    }

    get spreadDocumentUrl() {
        return this.view?.spreadDocumentId ? `/${this.view.spreadDocumentId}` : null;
    }

    get spreadDocumentLabel() {
        return this.view?.spreadDocumentName || 'Open Spread Document';
    }

    get sourceFileUrl() {
        return this.view?.contentDocumentId ? `/lightning/r/ContentDocument/${this.view.contentDocumentId}/view` : null;
    }

    get rawText() {
        return this.view?.rawText || 'No extracted text was captured.';
    }

    get rawTableMarkdown() {
        return this.view?.rawTableMarkdown || 'No table markdown was captured.';
    }

    openSourceFile() {
        if (this.sourceFileUrl) {
            window.open(this.sourceFileUrl, '_blank', 'noopener,noreferrer');
        }
    }
}
