/** Order status for the person asking. Another customer's order number gets the same NOT_FOUND as a made-up one. */
public with sharing class CR_GetOrderStatus {
    public class Request {
        @InvocableVariable(label='Order number' description='The order number the customer gave, e.g. ORD-10027' required=true)
        public String orderNumber;
    }
    public class Response {
        @InvocableVariable(label='Outcome' description='SUCCESS, NOT_FOUND or NOT_AUTHORIZED')
        public String outcome;
        @InvocableVariable(label='Status') public String status;
        @InvocableVariable(label='Product') public String product;
        @InvocableVariable(label='Delivered on') public Date deliveredOn;
        @InvocableVariable(label='Total') public Decimal total;
        @InvocableVariable(label='Source' description='Where the facts came from') public String source;
        @InvocableVariable(label='As of') public Datetime asOf;
        @InvocableVariable(label='Correlation id') public String correlationId;
    }

    @InvocableMethod(label='Get Order Status' description='Looks up an order the current customer is allowed to see. Never reveals whether other customers\' orders exist.')
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request r : requests) {
            Long t0 = System.currentTimeMillis();
            Response res = new Response();
            res.correlationId = CR_Support.newCorrelationId();
            try {
                CR_Order__c o = CR_Support.visibleOrder(r.orderNumber);
                if (o == null) {
                    res.outcome = CR_Support.NOT_FOUND;
                } else {
                    res.outcome = CR_Support.SUCCESS;
                    res.status = o.Status__c;
                    res.product = o.Product__c;
                    res.deliveredOn = o.Delivered_On__c;
                    res.total = o.Total__c;
                    res.source = 'ORDER_RECORD';
                    res.asOf = Datetime.now();
                }
            } catch (CR_Support.AccessException e) {
                res.outcome = CR_Support.NOT_AUTHORIZED;
            }
            CR_Support.audit('GetOrderStatus', res.outcome, r.orderNumber, res.correlationId, t0);
            out.add(res);
        }
        return out;
    }
}