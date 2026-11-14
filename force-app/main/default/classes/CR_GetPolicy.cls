/** The current resolution policy for a problem category. An expired policy is reported as POLICY_EXPIRED, never used. */
public with sharing class CR_GetPolicy {
    public class Request {
        @InvocableVariable(label='Category' description='Damaged, Late or Not Received' required=true)
        public String category;
    }
    public class Response {
        @InvocableVariable(label='Outcome' description='SUCCESS, POLICY_EXPIRED or NOT_FOUND') public String outcome;
        @InvocableVariable(label='Policy text') public String policyText;
        @InvocableVariable(label='Version') public String version;
        @InvocableVariable(label='Claim window (days)') public Integer claimWindowDays;
        @InvocableVariable(label='Valid until') public Date validUntil;
        @InvocableVariable(label='Correlation id') public String correlationId;
    }

    @InvocableMethod(label='Get Resolution Policy' description='Returns the approved policy text and version for a problem category, or POLICY_EXPIRED.')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Long t0 = System.currentTimeMillis();
            Response res = new Response();
            res.correlationId = CR_Support.newCorrelationId();
            CR_Policy__mdt p = CR_Support.policyFor(r.category);
            if (p == null) {
                res.outcome = CR_Support.NOT_FOUND;
            } else {
                res.version = p.Version__c;
                res.validUntil = p.Valid_Until__c;
                if (CR_Support.isValid(p)) {
                    res.outcome = CR_Support.SUCCESS;
                    res.policyText = p.Policy_Text__c;
                    res.claimWindowDays = p.Claim_Window_Days__c == null ? null : p.Claim_Window_Days__c.intValue();
                } else {
                    res.outcome = CR_Support.POLICY_EXPIRED;
                }
            }
            CR_Support.audit('GetPolicy', res.outcome, r.category, res.correlationId, t0);
            out.add(res);
        }
        return out;
    }
}