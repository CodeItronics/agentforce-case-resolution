/**
 * Records a resolution for a person to act on. It never moves money: refunds are created as Pending Approval.
 * The idempotency key makes retries safe: the same key returns the first request instead of creating another.
 */
public with sharing class CR_RequestResolution {
    public class Request {
        @InvocableVariable(label='Order number' required=true) public String orderNumber;
        @InvocableVariable(label='Type' description='Refund, Replacement or Escalation' required=true) public String type;
        @InvocableVariable(label='Amount' description='Refund amount; must not exceed the order total') public Decimal amount;
        @InvocableVariable(label='Reason' required=true) public String reason;
        @InvocableVariable(label='Idempotency key' description='Same key for retries of the same request' required=true) public String idempotencyKey;
        @InvocableVariable(label='Case id') public Id caseId;
    }
    public class Response {
        @InvocableVariable(label='Outcome' description='SUCCESS, DUPLICATE, NOT_FOUND, NOT_AUTHORIZED or VALIDATION_ERROR') public String outcome;
        @InvocableVariable(label='Reference') public String reference;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Message') public String message;
        @InvocableVariable(label='Correlation id') public String correlationId;
    }

    private static final Set<String> TYPES = new Set<String>{ 'Refund', 'Replacement', 'Escalation' };

    @InvocableMethod(label='Request Resolution' description='Creates a refund (pending supervisor approval), replacement or escalation request. Never executes a refund.')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Long t0 = System.currentTimeMillis();
            Response res = new Response();
            res.correlationId = CR_Support.newCorrelationId();
            try {
                create(r, res);
            } catch (CR_Support.AccessException e) {
                res.outcome = CR_Support.NOT_AUTHORIZED;
            }
            CR_Support.audit('RequestResolution', res.outcome, r.idempotencyKey, res.correlationId, t0);
            out.add(res);
        }
        return out;
    }

    private static void create(Request r, Response res) {
        if (!TYPES.contains(r.type) || String.isBlank(r.idempotencyKey) || String.isBlank(r.reason)) {
            res.outcome = CR_Support.VALIDATION_ERROR;
            res.message = 'Type, reason and idempotency key are required.';
            return;
        }
        List<CR_Resolution_Request__c> existing = [
            SELECT Name, Status__c FROM CR_Resolution_Request__c WHERE Idempotency_Key__c = :r.idempotencyKey WITH USER_MODE LIMIT 1
        ];
        if (!existing.isEmpty()) {
            res.outcome = CR_Support.DUPLICATE;
            res.reference = existing[0].Name;
            res.status = existing[0].Status__c;
            res.message = 'This request was already recorded.';
            return;
        }
        CR_Order__c o = CR_Support.visibleOrder(r.orderNumber);
        if (o == null) {
            res.outcome = CR_Support.NOT_FOUND;
            return;
        }
        if (r.type == 'Refund' && (r.amount == null || r.amount <= 0 || (o.Total__c != null && r.amount > o.Total__c))) {
            res.outcome = CR_Support.VALIDATION_ERROR;
            res.message = 'The refund amount must be more than zero and no more than the order total.';
            return;
        }
        CR_Resolution_Request__c rr = new CR_Resolution_Request__c(
            Order__c = o.Id, Case__c = r.caseId, Type__c = r.type, Amount__c = r.type == 'Refund' ? r.amount : null,
            Reason__c = r.reason, Idempotency_Key__c = r.idempotencyKey,
            Status__c = r.type == 'Refund' ? 'Pending Approval' : 'Open'
        );
        Database.insert(rr, AccessLevel.USER_MODE);
        rr = [SELECT Name, Status__c FROM CR_Resolution_Request__c WHERE Id = :rr.Id WITH USER_MODE];
        res.outcome = CR_Support.SUCCESS;
        res.reference = rr.Name;
        res.status = rr.Status__c;
        res.message = r.type == 'Refund' ? 'Sent to a supervisor for approval. No money has moved.' : 'Recorded for the team.';
    }
}