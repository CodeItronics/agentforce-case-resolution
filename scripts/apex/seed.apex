// Synthetic demo orders for the Case Resolution agent, owned by the running user. Safe to re-run.
List<CR_Order__c> orders = new List<CR_Order__c>{
    new CR_Order__c(Name = 'ORD-1001', Order_Number__c = 'ORD-1001', Status__c = 'Delivered', Delivered_On__c = Date.today().addDays(-5), Total__c = 120, Product__c = 'Desk lamp'),
    new CR_Order__c(Name = 'ORD-1002', Order_Number__c = 'ORD-1002', Status__c = 'Delivered', Delivered_On__c = Date.today().addDays(-60), Total__c = 80, Product__c = 'Bookshelf'),
    new CR_Order__c(Name = 'ORD-1003', Order_Number__c = 'ORD-1003', Status__c = 'Shipped', Total__c = 50, Product__c = 'Mouse pad')
};
// Needs the CR_Data_Admin permission set (create access on orders).
Database.upsert(orders, CR_Order__c.Order_Number__c, false);
System.debug('Seeded ' + orders.size() + ' demo orders');
