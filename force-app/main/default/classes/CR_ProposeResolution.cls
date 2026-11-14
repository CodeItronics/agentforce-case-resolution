/**
 * Deterministic resolution rules. The agent explains the result; it does not decide it.
 * Damaged within the claim window: replacement (customer confirms) or refund (supervisor approves).
 * Delivered but "not received": carrier investigation before any refund. Anything else, or an expired policy: escalate.
 */
public with sharing class CR_ProposeResolution {
    public class Request {
        @InvocableVariable(label='Order number' required=true) public String orderNumber;
        @InvocableVariable(label='Category' description='Damaged, Late or Not Received' required=true) public String category;
    }
    public class Response {
        @InvocableVariable(label='Outcome') public String outcome;
        @InvocableVariable(label='Recommended path' description='REPLACEMENT, REFUND_NEEDS_APPROVAL, INVESTIGATE_WITH_CARRIER or ESCALATE') public String recommendedPath;
        @InvocableVariable(label='Allowed paths' description='Comma-separated') public String allowedPaths;
        @InvocableVariable(label='Reason') public String reason;
        @InvocableVariable(label='Policy version') public String policyVersion;
        @InvocableVariable(label='Correlation id') public String correlationId;
    }

    @InvocableMethod(label='Propose Resolution' description='Applies the resolution policy to an order the customer can see and returns the allowed paths with a reason.')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Long t0 = System.currentTimeMillis();
            Response res = new Response();
            res.correlationId = CR_Support.newCorrelationId();
            try {
                decide(r, res);
            } catch (CR_Support.AccessException e) {
                res.outcome = CR_Support.NOT_AUTHORIZED;
            }
            CR_Support.audit('ProposeResolution', res.outcome + ':' + res.recommendedPath, r.orderNumber, res.correlationId, t0);
            out.add(res);
        }
        return out;
    }

    private static void decide(Request r, Response res) {
        CR_Order__c o = CR_Support.visibleOrder(r.orderNumber);
        if (o == null) {
            res.outcome = CR_Support.NOT_FOUND;
            return;
        }
        CR_Policy__mdt p = CR_Support.policyFor(r.category);
        res.outcome = CR_Support.SUCCESS;
        if (p == null || !CR_Support.isValid(p)) {
            escalate(res, p == null ? 'No policy covers this problem.' : 'The policy for this problem has expired.');
            return;
        }
        res.policyVersion = p.Version__c;
        Integer age = o.Delivered_On__c == null ? null : o.Delivered_On__c.daysBetween(Date.today());
        Boolean inWindow = age != null && p.Claim_Window_Days__c != null && age <= p.Claim_Window_Days__c;

        if (r.category == 'Damaged' && o.Status__c == 'Delivered' && inWindow) {
            res.recommendedPath = 'REPLACEMENT';
            res.allowedPaths = 'REPLACEMENT,REFUND_NEEDS_APPROVAL,ESCALATE';
            res.reason = 'Delivered ' + age + ' days ago, within the ' + p.Claim_Window_Days__c.intValue() + '-day window of policy ' + p.Version__c + '.';
        } else if (r.category == 'Not Received' && o.Status__c == 'Delivered') {
            res.recommendedPath = 'INVESTIGATE_WITH_CARRIER';
            res.allowedPaths = 'INVESTIGATE_WITH_CARRIER,ESCALATE';
            res.reason = 'Tracking says delivered; the policy requires a carrier investigation before any refund.';
        } else {
            escalate(res, inWindow ? 'The order status does not match this problem.' : 'Outside the claim window or no delivery date.');
        }
    }

    private static void escalate(Response res, String why) {
        res.recommendedPath = 'ESCALATE';
        res.allowedPaths = 'ESCALATE';
        res.reason = why;
    }
}