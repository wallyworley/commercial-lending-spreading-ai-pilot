// Seed script: C&I pilot Spreading_Policy__c with first-wave Spreading_Threshold__c records.
// Run via: sf apex run --file scripts/seedPolicyAndThresholds.apex --target-org <alias>
// Creates a Draft policy. Use SpreadingPolicyService.recordFirstApproval / recordSecondApproval
// / activatePolicy (or the Approval Flow) to promote to Active before live pilot runs.

Spreading_Policy__c policy = new Spreading_Policy__c(
    Name                  = 'C&I Pilot Policy v1',
    Version__c            = 'v1',
    Status__c             = 'Draft',
    Portfolio__c          = 'C&I',
    Effective_Start_Date__c = Date.today(),
    Description__c        = 'First-wave threshold policy for the C&I financial spreading AI evidence pilot. ' +
                            'Covers the eight highest-priority metrics per the pilot charter. ' +
                            'Activate after dual approval from Credit Policy and Model Risk.'
);
insert policy;

List<Spreading_Threshold__c> thresholds = new List<Spreading_Threshold__c>{

    // Priority 1: Uncaught Material Errors — hard stop, must be zero
    new Spreading_Threshold__c(
        Name                        = 'Uncaught Material Errors — Zero',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'Uncaught Material Errors',
        Operator__c                 = '<',
        Maximum_Value__c            = 1,
        Severity_When_Failed__c     = 'Hard Stop',
        Applies_To_Material_Line__c = true,
        Requires_Exception_Approval__c = true,
        Narrative_Guidance__c       = 'Any uncaught material error blocks production. ' +
                                      'Classify the failure, request nCino product evidence, and retest.'
    ),

    // Priority 2: Dollar-Weighted Accuracy >= 99.5%
    new Spreading_Threshold__c(
        Name                        = 'Dollar Accuracy — 99.5%',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'Dollar Accuracy',
        Operator__c                 = '>=',
        Minimum_Value__c            = 99.5,
        Severity_When_Failed__c     = 'Hard Stop',
        Applies_To_Material_Line__c = true,
        Requires_Exception_Approval__c = true,
        Narrative_Guidance__c       = 'Dollar-weighted accuracy captures impact of large errors. ' +
                                      'A path can pass exact-match rate but fail here if one large line is wrong.'
    ),

    // Priority 3: Exact Match Rate >= 98%
    new Spreading_Threshold__c(
        Name                        = 'Exact Match Rate — 98%',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'Exact Match Rate',
        Operator__c                 = '>=',
        Minimum_Value__c            = 98.0,
        Severity_When_Failed__c     = 'Policy Exception',
        Applies_To_Material_Line__c = false,
        Requires_Exception_Approval__c = false,
        Narrative_Guidance__c       = 'Basic extraction and mapping reliability. ' +
                                      'Failures here indicate systemic label mapping or OCR issues.'
    ),

    // Priority 4: Certification Rate — 100% for material lines
    new Spreading_Threshold__c(
        Name                        = 'Certification Rate — 100% Material',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'Certification Rate',
        Operator__c                 = '>=',
        Minimum_Value__c            = 100.0,
        Severity_When_Failed__c     = 'Hard Stop',
        Applies_To_Material_Line__c = true,
        Requires_Exception_Approval__c = true,
        Narrative_Guidance__c       = 'All material lines must be certified by a qualified reviewer. ' +
                                      'Uncertified material values may not be used in underwriting output.'
    ),

    // Priority 5: Time Reduction >= 30% (Salesforce native and nCino auto paths only)
    new Spreading_Threshold__c(
        Name                        = 'Analyst Time Reduction — 30%',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'DSCR',
        Operator__c                 = '>=',
        Minimum_Value__c            = 1.20,
        Severity_When_Failed__c     = 'Policy Exception',
        Applies_To_Material_Line__c = true,
        Requires_Exception_Approval__c = false,
        Narrative_Guidance__c       = 'Minimum DSCR threshold for C&I credits in scope of this pilot. ' +
                                      'Bank credit policy determines the specific floor; 1.20x is the pilot default. ' +
                                      'Update before production with bank-approved policy floor.'
    ),

    // Priority 6: Debt / EBITDA — pilot default warning at 5x
    new Spreading_Threshold__c(
        Name                        = 'Debt / EBITDA — Warning at 5x',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'Debt / EBITDA',
        Operator__c                 = '<=',
        Maximum_Value__c            = 5.0,
        Severity_When_Failed__c     = 'Warning',
        Applies_To_Material_Line__c = true,
        Requires_Exception_Approval__c = false,
        Narrative_Guidance__c       = 'Common leverage indicator. Values above 5x warrant discussion in credit memo. ' +
                                      'Industry-specific thresholds should be configured in separate policies.'
    ),

    // Priority 7: Current Ratio — warning below 1.0
    new Spreading_Threshold__c(
        Name                        = 'Current Ratio — Warning Below 1.0',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'Current Ratio',
        Operator__c                 = '>=',
        Minimum_Value__c            = 1.0,
        Severity_When_Failed__c     = 'Warning',
        Applies_To_Material_Line__c = true,
        Requires_Exception_Approval__c = false,
        Narrative_Guidance__c       = 'Current ratio below 1.0 indicates negative working capital. ' +
                                      'Flag for credit memo discussion. Not an automatic decline.'
    ),

    // Priority 8: Debt-to-Worth — warning above 3x
    new Spreading_Threshold__c(
        Name                        = 'Debt-to-Worth — Warning at 3x',
        Spreading_Policy__c         = policy.Id,
        Metric__c                   = 'Debt-to-Worth',
        Operator__c                 = '<=',
        Maximum_Value__c            = 3.0,
        Severity_When_Failed__c     = 'Warning',
        Applies_To_Material_Line__c = true,
        Requires_Exception_Approval__c = false,
        Narrative_Guidance__c       = 'Balance-sheet leverage signal. Values above 3x indicate thin equity cushion. ' +
                                      'Interpret in context of industry norms and collateral coverage.'
    )
};

insert thresholds;

System.debug('Seeded policy: ' + policy.Id + ' with ' + thresholds.size() + ' thresholds.');
System.debug('Policy status: Draft — run SpreadingPolicyService.recordFirstApproval / recordSecondApproval / activatePolicy to promote.');
