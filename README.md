# C&I Financial Spreading AI Evidence Pilot

This project is a standalone evidence pilot for a $25B commercial lending bank evaluating whether AI-assisted financial spreading is accurate, governable, and safe enough for production use with Salesforce and nCino.

The pilot does not assume that automated spreading should be purchased. It compares three paths:

1. nCino Automated Spreading as the vendor benchmark.
2. Salesforce-native document extraction and staging patterns.
3. nCino Document Manager and Spreads with improved manual workflow as the control case.

The default operating model is draft-only AI prefill with human certification. No AI-generated value should affect underwriting, covenant analysis, risk rating, or credit memo output until a credit user certifies the material line items.

## Project Contents

| Path | Purpose |
| --- | --- |
| `docs/pilot-charter.md` | Scope, decision gates, roles, and operating assumptions. |
| `docs/architecture.md` | Salesforce/nCino-supported architecture for the three pilot paths. |
| `docs/control-framework.md` | Security, compliance, audit, model-risk, and vendor-evidence controls. |
| `docs/test-plan.md` | Test corpus, adversarial scenarios, validation flow, and acceptance gates. |
| `docs/commercial-lending-spreading-primer.md` | Credit analyst primer for spreading, repayment capacity, ratios, collateral, and AI failure modes. |
| `docs/salesforce-agentforce-architecture-plan.md` | Salesforce implementation plan comparing Agent Script, LWC, React, Apex, and Flow. |
| `docs/source-register.md` | Official Salesforce and nCino source register. |
| `schemas/spread-staging-record.schema.json` | Draft-only spread staging record schema. |
| `schemas/pilot-scorecard-row.schema.json` | Scorecard row schema for measured pilot results. |
| `data/templates/*.csv` | Data collection templates for corpus, baseline, extraction, and scorecard. |
| `src/scorecard.js` | Local pass/fail scoring utility for pilot measurements. |
| `test/scorecard.test.js` | Tests for scoring calculations and gate behavior. |

## Quick Start

If you are using the project for the first time, start with:

- `docs/how-to-use.md`
- `docs/pilot-charter.md`
- `docs/test-plan.md`

```bash
npm install
npm test
npm run scorecard -- data/templates/pilot-scorecard.csv
```

To create fake borrower documents and pilot data for demos:

```bash
npm run generate:synthetic
npm run scorecard -- data/synthetic/pilot-scorecard.csv --no-exit-code
npm run report -- data/synthetic/pilot-scorecard.csv
```

The scorecard command reads pilot results from CSV and evaluates the gates from the pilot charter:

- At least 98% exact line-item match.
- At least 99.5% dollar-weighted accuracy.
- Zero uncaught material errors.
- At least 30% analyst-time reduction.
- Draft values must have human certification where required.

## Decision Posture

Production use is blocked until:

- Pilot evidence passes all gates.
- Credit leadership accepts the human certification process.
- Information security approves the data movement and vendor controls.
- Model risk approves the evaluation evidence.
- Salesforce/nCino owners approve the implementation path.
- Legal/procurement obtains required private nCino documentation under NDA.
