@IsTest
private class CR_ActionsTest {
  // Synthetic data only. Orders are private: a user sees only the orders they own.

  private static User newUser(
    String alias,
    String profileName,
    Boolean withPermSet
  ) {
    Profile p = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
    User u = new User(
      Alias = alias,
      Email = alias + '@example.com',
      Username = alias + '.' + Crypto.getRandomInteger() + '@example.com.poc',
      LastName = alias,
      ProfileId = p.Id,
      TimeZoneSidKey = 'Asia/Kolkata',
      LocaleSidKey = 'en_IN',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    // Users and permission sets are setup objects: create them in their own runAs block to avoid mixed DML.
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insert u;
      if (withPermSet) {
        PermissionSet ps = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'CR_Agent_User'
        ];
        insert new PermissionSetAssignment(
          AssigneeId = u.Id,
          PermissionSetId = ps.Id
        );
      }
    }
    return u;
  }

  private static CR_Order__c order(
    String num,
    String status,
    Integer deliveredDaysAgo,
    Decimal total
  ) {
    return new CR_Order__c(
      Name = num,
      Order_Number__c = num,
      Status__c = status,
      Total__c = total,
      Product__c = 'Desk lamp',
      Delivered_On__c = deliveredDaysAgo == null
        ? null
        : Date.today().addDays(-deliveredDaysAgo)
    );
  }

  @TestSetup
  static void setup() {
    User owner = newUser('crowner', 'Standard User', true);
    newUser('crother', 'Standard User', true);
    // Orders come from the order system, not from the customer: insert them here and make the customer the owner.
    List<CR_Order__c> orders = new List<CR_Order__c>{
      order('ORD-1001', 'Delivered', 5, 120),
      order('ORD-1002', 'Delivered', 60, 80),
      order('ORD-1003', 'Shipped', null, 50)
    };
    for (CR_Order__c o : orders)
      o.OwnerId = owner.Id;
    Database.insert(orders, AccessLevel.SYSTEM_MODE);
  }

  private static User user(String alias) {
    return [SELECT Id FROM User WHERE Alias = :alias LIMIT 1];
  }

  private static CR_GetOrderStatus.Response status(String num) {
    CR_GetOrderStatus.Request r = new CR_GetOrderStatus.Request();
    r.orderNumber = num;
    return CR_GetOrderStatus.run(new List<CR_GetOrderStatus.Request>{ r })[0];
  }

  private static CR_ProposeResolution.Response propose(
    String num,
    String category
  ) {
    CR_ProposeResolution.Request r = new CR_ProposeResolution.Request();
    r.orderNumber = num;
    r.category = category;
    return CR_ProposeResolution.run(
      new List<CR_ProposeResolution.Request>{ r }
    )[0];
  }

  private static CR_RequestResolution.Response request(
    String num,
    String type,
    Decimal amount,
    String key
  ) {
    CR_RequestResolution.Request r = new CR_RequestResolution.Request();
    r.orderNumber = num;
    r.type = type;
    r.amount = amount;
    r.reason = 'Arrived with a cracked base';
    r.idempotencyKey = key;
    return CR_RequestResolution.run(
      new List<CR_RequestResolution.Request>{ r }
    )[0];
  }

  @IsTest
  static void ownerSeesOwnOrder() {
    System.runAs(user('crowner')) {
      CR_GetOrderStatus.Response r = status('ORD-1001');
      Assert.areEqual('SUCCESS', r.outcome);
      Assert.areEqual('Delivered', r.status);
      Assert.areEqual('ORDER_RECORD', r.source);
      Assert.isNotNull(r.correlationId);
    }
  }

  @IsTest
  static void anotherCustomersOrderLooksLikeAMadeUpOne() {
    System.runAs(user('crother')) {
      Assert.areEqual(
        'NOT_FOUND',
        status('ORD-1001').outcome,
        'must not reveal that the order exists'
      );
      Assert.areEqual('NOT_FOUND', status('ORD-9999').outcome);
      Assert.areEqual(
        'NOT_FOUND',
        request('ORD-1001', 'Refund', 10, 'k-other').outcome
      );
    }
  }

  @IsTest
  static void userWithoutAccessIsRefused() {
    User noAccess = newUser('crnone', 'Minimum Access - Salesforce', false);
    System.runAs(noAccess) {
      Assert.areEqual('NOT_AUTHORIZED', status('ORD-1001').outcome);
    }
  }

  @IsTest
  static void expiredPolicyIsNeverUsed() {
    CR_GetPolicy.Request r = new CR_GetPolicy.Request();
    r.category = 'Late';
    CR_GetPolicy.Response res = CR_GetPolicy.run(
      new List<CR_GetPolicy.Request>{ r }
    )[0];
    Assert.areEqual('POLICY_EXPIRED', res.outcome);
    Assert.isNull(res.policyText, 'expired policy text must not be returned');
    System.runAs(user('crowner')) {
      Assert.areEqual('ESCALATE', propose('ORD-1001', 'Late').recommendedPath);
    }
  }

  @IsTest
  static void validPolicyIsReturned() {
    CR_GetPolicy.Request r = new CR_GetPolicy.Request();
    r.category = 'Damaged';
    CR_GetPolicy.Response res = CR_GetPolicy.run(
      new List<CR_GetPolicy.Request>{ r }
    )[0];
    Assert.areEqual('SUCCESS', res.outcome);
    Assert.areEqual(30, res.claimWindowDays);
  }

  @IsTest
  static void resolutionRules() {
    System.runAs(user('crowner')) {
      CR_ProposeResolution.Response damaged = propose('ORD-1001', 'Damaged');
      Assert.areEqual('REPLACEMENT', damaged.recommendedPath);
      Assert.isTrue(damaged.allowedPaths.contains('REFUND_NEEDS_APPROVAL'));
      Assert.areEqual(
        'ESCALATE',
        propose('ORD-1002', 'Damaged').recommendedPath,
        'outside the 30-day window'
      );
      Assert.areEqual(
        'INVESTIGATE_WITH_CARRIER',
        propose('ORD-1001', 'Not Received').recommendedPath
      );
      Assert.areEqual(
        'ESCALATE',
        propose('ORD-1003', 'Damaged').recommendedPath,
        'not delivered yet'
      );
      Assert.areEqual('NOT_FOUND', propose('ORD-9999', 'Damaged').outcome);
    }
  }

  @IsTest
  static void refundsWaitForApprovalAndRetriesAreSafe() {
    System.runAs(user('crowner')) {
      CR_RequestResolution.Response first = request(
        'ORD-1001',
        'Refund',
        120,
        'case-42-refund'
      );
      Assert.areEqual('SUCCESS', first.outcome);
      Assert.areEqual(
        'Pending Approval',
        first.status,
        'refunds are never executed by the agent'
      );
      CR_RequestResolution.Response retry = request(
        'ORD-1001',
        'Refund',
        120,
        'case-42-refund'
      );
      Assert.areEqual('DUPLICATE', retry.outcome);
      Assert.areEqual(first.reference, retry.reference);
      Assert.areEqual(
        'VALIDATION_ERROR',
        request('ORD-1001', 'Refund', 500, 'case-42-too-much').outcome
      );
      Assert.areEqual(
        'VALIDATION_ERROR',
        request('ORD-1001', 'Gift card', 5, 'case-42-odd').outcome
      );
      Assert.areEqual(
        'Open',
        request('ORD-1001', 'Escalation', null, 'case-42-esc').status
      );
    }
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM CR_Resolution_Request__c
        WHERE Type__c = 'Refund'
        WITH SYSTEM_MODE
      ]
    );
  }

  @IsTest
  static void everyActionIsAudited() {
    System.runAs(user('crowner')) {
      status('ORD-1001');
      propose('ORD-1001', 'Damaged');
    }
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM CR_Agent_Action_Log__c
        WHERE Correlation_Id__c != NULL
        WITH SYSTEM_MODE
      ]
    );
  }
}
