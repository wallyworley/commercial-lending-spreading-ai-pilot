@IsTest
private class SpreadingPolicyServiceTest {

    // ─── Mock selector ───────────────────────────────────────────────────────

    private class MockPolicySelector extends SpreadPolicySelector {
        public List<Spreading_Policy__c> activePolicies = new List<Spreading_Policy__c>();
        public List<Spreading_Threshold__c> thresholds = new List<Spreading_Threshold__c>();
        public Spreading_Policy__c policyById;

        public override List<Spreading_Policy__c> getActivePolicies(Date effectiveDate) {
            return activePolicies;
        }
        public override List<Spreading_Threshold__c> getThresholdsForPolicy(Id policyId) {
            return thresholds;
        }
        public override Spreading_Policy__c getById(Id policyId) {
            return policyById;
        }
    }

    // ─── SpreadPolicyRules ───────────────────────────────────────────────────

    @IsTest
    static void mostSpecific_returnsNullForEmptyList() {
        Spreading_Policy__c result = SpreadPolicyRules.mostSpecific(
            new List<Spreading_Policy__c>(), 'C&I', null, null
        );
        Assert.isNull(result);
    }

    @IsTest
    static void mostSpecific_prefersPortfolioMatch() {
        Spreading_Policy__c broad   = makePolicy('broad',   null,  null, null);
        Spreading_Policy__c matched = makePolicy('matched', 'C&I', null, null);

        Spreading_Policy__c winner = SpreadPolicyRules.mostSpecific(
            new List<Spreading_Policy__c>{ broad, matched }, 'C&I', null, null
        );
        Assert.areEqual(matched.Id, winner.Id);
    }

    @IsTest
    static void mostSpecific_portfolioPlusIndustryBeatsPortfolioAlone() {
        Spreading_Policy__c portfolioOnly = makePolicy('p',  'C&I', null,         null);
        Spreading_Policy__c fullMatch     = makePolicy('f',  'C&I', 'Manufacturing', null);

        Spreading_Policy__c winner = SpreadPolicyRules.mostSpecific(
            new List<Spreading_Policy__c>{ portfolioOnly, fullMatch }, 'C&I', 'Manufacturing', null
        );
        Assert.areEqual(fullMatch.Id, winner.Id);
    }

    @IsTest
    static void isFailed_greaterThanOrEqual_passesWhenMet() {
        Spreading_Threshold__c t = makeThreshold('DSCR', '>=', 1.25, null);
        Assert.isFalse(SpreadPolicyRules.isFailed(t, 1.25));
        Assert.isFalse(SpreadPolicyRules.isFailed(t, 2.00));
        Assert.isTrue(SpreadPolicyRules.isFailed(t, 1.00));
    }

    @IsTest
    static void isFailed_lessThan_failsWhenAtBoundary() {
        Spreading_Threshold__c t = makeThreshold('Uncaught Material Errors', '<', null, 1.0);
        Assert.isTrue(SpreadPolicyRules.isFailed(t, 1.0));
        Assert.isFalse(SpreadPolicyRules.isFailed(t, 0.0));
    }

    @IsTest
    static void isFailed_between_failsOutsideRange() {
        Spreading_Threshold__c t = makeThreshold('Current Ratio', 'Between', 1.0, 3.0);
        Assert.isFalse(SpreadPolicyRules.isFailed(t, 1.5));
        Assert.isTrue(SpreadPolicyRules.isFailed(t, 0.5));
        Assert.isTrue(SpreadPolicyRules.isFailed(t, 3.5));
    }

    @IsTest
    static void isFailed_nullMeasuredValueReturnsFalse() {
        Spreading_Threshold__c t = makeThreshold('DSCR', '>=', 1.25, null);
        Assert.isFalse(SpreadPolicyRules.isFailed(t, null));
    }

    @IsTest
    static void isDualApproved_requiresBothApprovers() {
        Spreading_Policy__c p = makePolicy('p', 'C&I', null, null);

        Assert.isFalse(SpreadPolicyRules.isDualApproved(p));

        p.Approved_By__c = UserInfo.getUserId();
        p.Approved_At__c = Datetime.now();
        Assert.isFalse(SpreadPolicyRules.isDualApproved(p));

        p.Secondary_Approved_By__c = UserInfo.getUserId();
        p.Secondary_Approved_At__c = Datetime.now();
        Assert.isTrue(SpreadPolicyRules.isDualApproved(p));
    }

    @IsTest
    static void canActivate_blockedWithoutDualApproval() {
        Spreading_Policy__c p = makePolicy('p', 'C&I', null, null);
        p.Status__c = 'Pending Approval';
        Assert.isFalse(SpreadPolicyRules.canActivate(p));
    }

    @IsTest
    static void canActivate_blockedWhenAlreadyActive() {
        Spreading_Policy__c p = makePolicy('p', 'C&I', null, null);
        p.Status__c = 'Active';
        p.Approved_By__c = UserInfo.getUserId();
        p.Approved_At__c = Datetime.now();
        p.Secondary_Approved_By__c = UserInfo.getUserId();
        p.Secondary_Approved_At__c = Datetime.now();
        Assert.isFalse(SpreadPolicyRules.canActivate(p));
    }

    @IsTest
    static void canActivate_trueWhenDualApprovedAndPending() {
        Spreading_Policy__c p = makePolicy('p', 'C&I', null, null);
        p.Status__c = 'Pending Approval';
        p.Approved_By__c = UserInfo.getUserId();
        p.Approved_At__c = Datetime.now();
        p.Secondary_Approved_By__c = UserInfo.getUserId();
        p.Secondary_Approved_At__c = Datetime.now();
        Assert.isTrue(SpreadPolicyRules.canActivate(p));
    }

    @IsTest
    static void validateThreshold_betweenRequiresBothBounds() {
        Spreading_Threshold__c t = makeThreshold('DSCR', 'Between', 1.0, null);
        String err = SpreadPolicyRules.validateThreshold(t);
        Assert.isNotNull(err);
        Assert.isTrue(err.contains('Minimum Value and Maximum Value'));
    }

    @IsTest
    static void validateThreshold_betweenMinMustBeLessThanMax() {
        Spreading_Threshold__c t = makeThreshold('DSCR', 'Between', 2.0, 1.0);
        String err = SpreadPolicyRules.validateThreshold(t);
        Assert.isNotNull(err);
        Assert.isTrue(err.contains('less than'));
    }

    @IsTest
    static void validateThreshold_validBetweenReturnsNull() {
        Spreading_Threshold__c t = makeThreshold('DSCR', 'Between', 1.0, 3.0);
        Assert.isNull(SpreadPolicyRules.validateThreshold(t));
    }

    @IsTest
    static void validateThreshold_greaterThanOrEqualRequiresMinimum() {
        Spreading_Threshold__c t = makeThreshold('DSCR', '>=', null, null);
        String err = SpreadPolicyRules.validateThreshold(t);
        Assert.isNotNull(err);
        Assert.isTrue(err.contains('Minimum Value'));
    }

    // ─── SpreadingPolicyService ──────────────────────────────────────────────

    @IsTest
    static void resolveActivePolicy_returnsNullWhenNoPolicies() {
        MockPolicySelector mock = new MockPolicySelector();
        SpreadingPolicyService svc = new SpreadingPolicyService(mock);

        Spreading_Policy__c result = svc.resolveActivePolicy('C&I', null, null, Date.today());
        Assert.isNull(result);
    }

    @IsTest
    static void resolveActivePolicy_returnsMostSpecificMatch() {
        Spreading_Policy__c broad   = makePolicy('broad',   null,  null, null);
        Spreading_Policy__c matched = makePolicy('matched', 'C&I', null, null);

        MockPolicySelector mock = new MockPolicySelector();
        mock.activePolicies = new List<Spreading_Policy__c>{ broad, matched };

        SpreadingPolicyService svc = new SpreadingPolicyService(mock);
        Spreading_Policy__c result = svc.resolveActivePolicy('C&I', null, null, Date.today());
        Assert.areEqual(matched.Id, result.Id);
    }

    @IsTest
    static void resolveThresholds_returnsEmptyWhenNoPolicyFound() {
        MockPolicySelector mock = new MockPolicySelector();
        SpreadingPolicyService svc = new SpreadingPolicyService(mock);

        List<Spreading_Threshold__c> results = svc.resolveThresholds('C&I', null, null, Date.today());
        Assert.isTrue(results.isEmpty());
    }

    @IsTest
    static void resolveThresholds_returnsThresholdsForMatchedPolicy() {
        Spreading_Policy__c policy = makePolicy('p', 'C&I', null, null);
        Spreading_Threshold__c t   = makeThreshold('DSCR', '>=', 1.25, null);

        MockPolicySelector mock = new MockPolicySelector();
        mock.activePolicies = new List<Spreading_Policy__c>{ policy };
        mock.thresholds     = new List<Spreading_Threshold__c>{ t };

        SpreadingPolicyService svc = new SpreadingPolicyService(mock);
        List<Spreading_Threshold__c> results = svc.resolveThresholds('C&I', null, null, Date.today());
        Assert.areEqual(1, results.size());
        Assert.areEqual('DSCR', results[0].Metric__c);
    }

    @IsTest
    static void activatePolicy_returnsErrorWhenPolicyNotFound() {
        MockPolicySelector mock = new MockPolicySelector();
        mock.policyById = null;

        SpreadingPolicyService svc = new SpreadingPolicyService(mock);
        String result = svc.activatePolicy(getFakeId(Spreading_Policy__c.SObjectType));
        Assert.areEqual('Policy not found.', result);
    }

    @IsTest
    static void activatePolicy_returnsErrorWithoutDualApproval() {
        Spreading_Policy__c policy = makePolicy('p', 'C&I', null, null);
        policy.Status__c = 'Pending Approval';

        MockPolicySelector mock = new MockPolicySelector();
        mock.policyById     = policy;
        mock.activePolicies = new List<Spreading_Policy__c>();
        mock.thresholds     = new List<Spreading_Threshold__c>();

        SpreadingPolicyService svc = new SpreadingPolicyService(mock);
        String result = svc.activatePolicy(policy.Id);
        Assert.isNotNull(result);
        Assert.isTrue(result.contains('dual approval'));
    }

    @IsTest
    static void recordFirstApproval_blocksIfAlreadyRecorded() {
        Spreading_Policy__c policy = makePolicy('p', 'C&I', null, null);
        policy.Status__c = 'Draft';
        policy.Approved_By__c = UserInfo.getUserId();

        MockPolicySelector mock = new MockPolicySelector();
        mock.policyById = policy;

        SpreadingPolicyService svc = new SpreadingPolicyService(mock);
        String result = svc.recordFirstApproval(policy.Id, UserInfo.getUserId());
        Assert.areEqual('First approval already recorded.', result);
    }

    @IsTest
    static void recordSecondApproval_blocksIfFirstMissing() {
        Spreading_Policy__c policy = makePolicy('p', 'C&I', null, null);
        policy.Status__c = 'Draft';

        MockPolicySelector mock = new MockPolicySelector();
        mock.policyById = policy;

        SpreadingPolicyService svc = new SpreadingPolicyService(mock);
        String result = svc.recordSecondApproval(policy.Id, UserInfo.getUserId());
        Assert.areEqual('First approval must be recorded before second.', result);
    }

    @IsTest
    static void recordSecondApproval_blocksSameApprover() {
        Id userId = UserInfo.getUserId();
        Spreading_Policy__c policy = makePolicy('p', 'C&I', null, null);
        policy.Status__c = 'Draft';
        policy.Approved_By__c = userId;
        policy.Approved_At__c = Datetime.now();

        MockPolicySelector mock = new MockPolicySelector();
        mock.policyById = policy;

        SpreadingPolicyService svc = new SpreadingPolicyService(mock);
        String result = svc.recordSecondApproval(policy.Id, userId);
        Assert.areEqual('The same user cannot provide both approvals.', result);
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    private static Spreading_Policy__c makePolicy(
        String name, String portfolio, String industry, String borrowerSize
    ) {
        Spreading_Policy__c p = new Spreading_Policy__c();
        p.Id              = getFakeId(Spreading_Policy__c.SObjectType);
        p.Name            = name;
        p.Status__c       = 'Draft';
        p.Portfolio__c    = portfolio;
        p.Industry__c     = industry;
        p.Borrower_Size__c = borrowerSize;
        return p;
    }

    private static Spreading_Threshold__c makeThreshold(
        String metric, String operator, Decimal minVal, Decimal maxVal
    ) {
        Spreading_Threshold__c t = new Spreading_Threshold__c();
        t.Id               = getFakeId(Spreading_Threshold__c.SObjectType);
        t.Metric__c        = metric;
        t.Operator__c      = operator;
        t.Minimum_Value__c = minVal;
        t.Maximum_Value__c = maxVal;
        t.Severity_When_Failed__c = 'Warning';
        return t;
    }

    private static Integer fakeIdCounter = 1;
    private static Id getFakeId(SObjectType sot) {
        String prefix = sot.getDescribe().getKeyPrefix();
        String num    = String.valueOf(fakeIdCounter++).leftPad(12, '0');
        return (Id)(prefix + '0AA' + num);
    }
}
