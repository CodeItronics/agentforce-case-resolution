/**
 * Shared helpers for the Case Resolution agent's actions.
 * Every action returns one of the contract outcomes and writes an audit row; none of them trusts identity supplied in chat.
 */
public with sharing class CR_Support {
  public static final String SUCCESS = 'SUCCESS';
  public static final String NOT_FOUND = 'NOT_FOUND';
  public static final String NOT_AUTHORIZED = 'NOT_AUTHORIZED';
  public static final String VALIDATION_ERROR = 'VALIDATION_ERROR';
  public static final String POLICY_EXPIRED = 'POLICY_EXPIRED';
  public static final String DUPLICATE = 'DUPLICATE';

  public class AccessException extends Exception {
  }

  /** The order as the running user may see it (sharing + FLS). Null when it doesn't exist or isn't theirs: callers must not tell the two apart. */
  public static CR_Order__c visibleOrder(String orderNumber) {
    if (String.isBlank(orderNumber))
      return null;
    try {
      List<CR_Order__c> rows = [
        SELECT
          Id,
          Order_Number__c,
          Status__c,
          Delivered_On__c,
          Total__c,
          Product__c,
          Account__c
        FROM CR_Order__c
        WHERE Order_Number__c = :orderNumber.trim()
        WITH USER_MODE
        LIMIT 1
      ];
      return rows.isEmpty() ? null : rows[0];
    } catch (QueryException e) {
      throw new AccessException('No access to orders');
    }
  }

  /** The newest policy row for a category, valid or not (the caller decides what an expired one means). */
  public static CR_Policy__mdt policyFor(String category) {
    if (String.isBlank(category))
      return null;
    List<CR_Policy__mdt> rows = [
      SELECT
        Category__c,
        Version__c,
        Claim_Window_Days__c,
        Valid_Until__c,
        Policy_Text__c
      FROM CR_Policy__mdt
      WHERE Category__c = :category.trim()
      ORDER BY Valid_Until__c DESC
      LIMIT 1
    ];
    return rows.isEmpty() ? null : rows[0];
  }

  public static Boolean isValid(CR_Policy__mdt p) {
    return p != null &&
      (p.Valid_Until__c == null ||
      p.Valid_Until__c >= Date.today());
  }

  public static String newCorrelationId() {
    return 'CORR-' +
      EncodingUtil.convertToHex(Crypto.generateAesKey(128))
        .left(12)
        .toUpperCase();
  }

  /** Audit row, written in system mode so a customer-facing user needs no access to the log object. */
  public static void audit(
    String action,
    String outcome,
    String ref,
    String correlationId,
    Long startedMs
  ) {
    CR_Agent_Action_Log__c log = new CR_Agent_Action_Log__c(
      Action__c = action,
      Outcome__c = outcome,
      Record_Ref__c = ref,
      Correlation_Id__c = correlationId,
      Duration_Ms__c = System.currentTimeMillis() - startedMs
    );
    Database.insert(log, AccessLevel.SYSTEM_MODE);
  }
}
