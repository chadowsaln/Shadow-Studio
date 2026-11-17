/// Stable error codes defined by SS-ARCH-002 and agent-boundary appendix.
abstract final class ShadowErrorCode {
  // Agent
  static const agentBudgetExceeded = 'AGENT_BUDGET_EXCEEDED';
  static const agentLoopDetected = 'AGENT_LOOP_DETECTED';
  static const agentTimeout = 'AGENT_TIMEOUT';
  static const agentCancelled = 'AGENT_CANCELLED';
  static const agentNoTools = 'AGENT_NO_TOOLS';
  static const agentInvalidPlan = 'AGENT_INVALID_PLAN';
  static const agentCheckpointMissing = 'AGENT_CHECKPOINT_MISSING';

  // Provider
  static const providerAuth = 'PROVIDER_AUTH';
  static const providerRateLimit = 'PROVIDER_RATE_LIMIT';
  static const providerUnsupported = 'PROVIDER_UNSUPPORTED';
  static const providerBudgetExceeded = 'PROVIDER_BUDGET_EXCEEDED';
  static const providerStreamBroken = 'PROVIDER_STREAM_BROKEN';
  static const providerToolCallMalformed = 'PROVIDER_TOOL_CALL_MALFORMED';

  // Tool
  static const toolInvalidArgs = 'TOOL_INVALID_ARGS';
  static const toolNotFound = 'TOOL_NOT_FOUND';
  static const toolFailed = 'TOOL_FAILED';
  static const toolSchemaInvalid = 'TOOL_SCHEMA_INVALID';
  static const toolDuplicateName = 'TOOL_DUPLICATE_NAME';
  static const toolResultTooLarge = 'TOOL_RESULT_TOO_LARGE';
  static const toolNotIdempotentRetry = 'TOOL_NOT_IDEMPOTENT_RETRY';
  static const toolTimeout = 'TOOL_TIMEOUT';
  static const toolOutputInvalid = 'TOOL_OUTPUT_INVALID';

  // Permission
  static const permApprovalRequired = 'PERM_APPROVAL_REQUIRED';
  static const permApprovalInvalid = 'PERM_APPROVAL_INVALID';
  static const permApprovalTimeout = 'PERM_APPROVAL_TIMEOUT';
  static const permPathEscape = 'PERM_PATH_ESCAPE';
  static const permPolicyUnknown = 'PERM_POLICY_UNKNOWN';
  static const permPolicyDenied = 'PERM_POLICY_DENIED';
  static const permShellBlocked = 'PERM_SHELL_BLOCKED';
  static const permInvalidArgument = 'PERM_INVALID_ARGUMENT';

  // Editing
  static const editRevisionMismatch = 'EDIT_REVISION_MISMATCH';
  static const editInvalidOperation = 'EDIT_INVALID_OPERATION';

  // Media
  static const mediaAssetMissing = 'MEDIA_ASSET_MISSING';
  static const mediaUnsupported = 'MEDIA_UNSUPPORTED';
  static const mediaCorrupt = 'MEDIA_CORRUPT';
  static const mediaEngineCrash = 'MEDIA_ENGINE_CRASH';
  static const mediaWorkerUnavailable = 'MEDIA_WORKER_UNAVAILABLE';

  // Store
  static const storeCorrupt = 'STORE_CORRUPT';
  static const storeDiskFull = 'STORE_DISK_FULL';
}
