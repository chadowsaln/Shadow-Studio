import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:shadow_contracts/shadow_contracts.dart';

import 'agent_context.dart';
import 'agent_context_assembler.dart';
import 'agent_events.dart';
import 'agent_limits.dart';
import 'recovery_manager.dart';

class _PendingApprovalTracker {
  int pending = 0;
}

@immutable
class LoopOutcome {
  const LoopOutcome._(
    this.state, {
    this.summary,
    this.errorCode,
    this.errorMessage,
    this.result = const <String, Object?>{},
  });
  const LoopOutcome.completed(
    String summary, {
    Map<String, Object?> result = const <String, Object?>{},
  }) : this._(AgentTaskState.succeeded, summary: summary, result: result);
  const LoopOutcome.failed(String code, String message)
    : this._(
        AgentTaskState.failed,
        errorCode: code,
        errorMessage: message,
        result: const <String, Object?>{},
      );
  const LoopOutcome.cancelled([String? reason])
    : this._(
        AgentTaskState.cancelled,
        errorMessage: reason,
        result: const <String, Object?>{},
      );

  final AgentTaskState state;
  final String? summary;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, Object?> result;
}

class ExecutionLoop {
  ExecutionLoop({
    required this.limits,
    required this.brain,
    required this.toolExecutor,
    required this.recoveryManager,
    required this.emit,
    this.approvalGate,
    this.contextAssembler,
    this.contextHolder,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final AgentRuntimeLimits limits;
  final AgentBrain brain;
  final ToolCallExecutor toolExecutor;
  final RecoveryManager recoveryManager;
  final void Function(AgentRuntimeEvent event) emit;
  final ApprovalGate? approvalGate;
  final AgentContextAssembler? contextAssembler;
  final AgentContextHolder? contextHolder;
  final DateTime Function() _now;

  Future<LoopOutcome> run({
    required String taskId,
    required String request,
    required AgentContext context,
    required CancellationToken cancel,
    required AuditSink audit,
  }) async {
    final startedAt = _now();
    var toolCallCount = 0;
    String? lastSignature;
    var consecutiveIdentical = 0;
    final history = <AIMessage>[
      AIMessage(role: AIMessageRole.user, content: request),
    ];
    final recentObservations = <ToolResult>[];
    final pendingApprovals = _PendingApprovalTracker();

    void checkTime() {
      if (_now().difference(startedAt) > limits.maxDuration) {
        throw TaskBudgetExceededException(
          ShadowErrorCode.agentTimeout,
          'Task exceeded max duration ${limits.maxDuration}',
        );
      }
    }

    void checkCancellation() {
      if (cancel.isCancelled) throw CancelledException(reason: cancel.reason);
    }

    try {
      checkCancellation();
      checkTime();
      var plan = await brain.plan(request: request, taskId: taskId);
      emit(
        PlanUpdated(
          taskId: taskId,
          timestamp: _now(),
          steps: plan.steps,
          revision: plan.revision,
        ),
      );

      while (true) {
        checkCancellation();
        checkTime();

        final next = plan.steps.where((s) => !s.isTerminal).toList();
        if (next.isEmpty) {
          // A plan whose only steps failed must not be reported as completed:
          // replanning can leave nothing pending, and silence would look like
          // success to the caller.
          final failed = plan.steps.where(
            (s) => s.status == PlanStepStatus.failed,
          );
          if (failed.isNotEmpty) {
            final message =
                failed.first.error ?? 'Step failed without a recovery step';
            emit(
              TaskFailed(
                taskId: taskId,
                timestamp: _now(),
                code: ShadowErrorCode.toolFailed,
                message: message,
              ),
            );
            return LoopOutcome.failed(ShadowErrorCode.toolFailed, message);
          }
          final summary = plan.completedSteps.isNotEmpty
              ? 'All planned steps completed.'
              : 'Task completed.';
          emit(
            TaskCompleted(taskId: taskId, timestamp: _now(), summary: summary),
          );
          return LoopOutcome.completed(summary);
        }

        final step = next.first;
        if (step.status == PlanStepStatus.pending) {
          plan = plan.updateStep(
            step.id,
            (s) => s.copyWith(status: PlanStepStatus.inProgress),
          );
          emit(
            StepStarted(
              taskId: taskId,
              timestamp: _now(),
              stepId: step.id,
              description: step.description,
              index: plan.steps.indexWhere((s) => s.id == step.id),
            ),
          );
        }

        final decision = await brain.nextDecision(
          plan: plan,
          currentStepId: step.id,
          history: List<AIMessage>.unmodifiable(history),
        );
        checkCancellation();
        checkTime();

        switch (decision) {
          case CompleteDecision(:final summary, :final result):
            plan = plan.updateStep(
              step.id,
              (s) => s.copyWith(
                status: PlanStepStatus.completed,
                resultSummary: summary,
              ),
            );
            emit(
              TaskCompleted(
                taskId: taskId,
                timestamp: _now(),
                summary: summary,
                result: result,
              ),
            );
            return LoopOutcome.completed(summary, result: result);

          case FailDecision(:final code, :final message, :final retryable):
            plan = plan.updateStep(
              step.id,
              (s) => s.copyWith(status: PlanStepStatus.failed, error: message),
            );
            emit(
              TaskFailed(
                taskId: taskId,
                timestamp: _now(),
                code: code,
                message: message,
                retryable: retryable,
              ),
            );
            return LoopOutcome.failed(code, message);

          case ReplanDecision(:final reason):
            plan = await brain.replan(
              currentPlan: plan,
              taskId: taskId,
              failureReason: reason,
              recentObservations: List<ToolResult>.unmodifiable(
                recentObservations,
              ),
            );
            emit(
              PlanUpdated(
                taskId: taskId,
                timestamp: _now(),
                steps: plan.steps,
                revision: plan.revision,
                reason: reason,
              ),
            );
            continue;

          case ToolCallsDecision(:final calls):
            if (calls.isEmpty) {
              history.add(
                const AIMessage(
                  role: AIMessageRole.assistant,
                  content: 'No tool calls.',
                ),
              );
              continue;
            }
            var replanned = false;
            for (final call in calls) {
              checkCancellation();
              checkTime();

              if (toolCallCount >= limits.maxToolCalls) {
                throw TaskBudgetExceededException(
                  ShadowErrorCode.agentBudgetExceeded,
                  'Exceeded max tool calls (${limits.maxToolCalls})',
                );
              }

              final signature = _toolSignature(call.name, call.arguments);
              if (signature == lastSignature) {
                consecutiveIdentical++;
              } else {
                lastSignature = signature;
                consecutiveIdentical = 1;
              }
              if (consecutiveIdentical >=
                  limits.maxConsecutiveIdenticalToolCalls) {
                throw LoopDetectedException(
                  'Detected ${limits.maxConsecutiveIdenticalToolCalls} consecutive identical tool calls: ${call.name}',
                );
              }

              emit(
                ToolCallRequested(
                  taskId: taskId,
                  timestamp: _now(),
                  callId: call.id,
                  toolName: call.name,
                  arguments: call.arguments,
                  stepId: step.id,
                ),
              );

              final tool = toolExecutor.resolve(call.name);
              if (tool == null) {
                throw TaskBudgetExceededException(
                  ShadowErrorCode.toolNotFound,
                  'Tool not found: ${call.name}',
                );
              }

              ApprovalToken? approval;
              if (_requiresApproval(tool)) {
                if (pendingApprovals.pending >= limits.maxPendingApprovals) {
                  emit(
                    TaskFailed(
                      taskId: taskId,
                      timestamp: _now(),
                      code: ShadowErrorCode.permApprovalRequired,
                      message: 'Only one pending approval allowed at a time',
                    ),
                  );
                  return const LoopOutcome.failed(
                    ShadowErrorCode.permApprovalRequired,
                    'Only one pending approval allowed at a time',
                  );
                }
                pendingApprovals.pending++;
                emit(
                  ApprovalRequested(
                    taskId: taskId,
                    timestamp: _now(),
                    callId: call.id,
                    toolName: call.name,
                    arguments: call.arguments,
                    riskLevel: tool.riskLevel,
                  ),
                );
                try {
                  approval = await approvalGate?.requestApproval(
                    taskId: taskId,
                    callId: call.id,
                    tool: tool,
                    arguments: call.arguments,
                  );
                } finally {
                  pendingApprovals.pending--;
                }
                if (approval == null) {
                  const msg = 'Approval denied or timed out';
                  final tr = ToolResult(
                    success: false,
                    errorCode: ShadowErrorCode.permApprovalRequired,
                    errorMessage: msg,
                  );
                  recentObservations.add(tr);
                  history.add(
                    AIMessage(
                      role: AIMessageRole.tool,
                      toolCallId: call.id,
                      name: call.name,
                      content: jsonEncode(tr.toJson()),
                    ),
                  );
                  continue;
                }
              }

              final result = await _executeWithRetries(
                taskId: taskId,
                call: call,
                tool: tool,
                context: context,
                cancel: cancel,
                audit: audit,
                approval: approval,
                checkCancellation: checkCancellation,
                checkTime: checkTime,
              );

              toolCallCount++;
              recentObservations.add(result);
              history.add(
                AIMessage(
                  role: AIMessageRole.tool,
                  toolCallId: call.id,
                  name: call.name,
                  content: jsonEncode(result.toJson()),
                ),
              );

              _updateContext(
                taskId: taskId,
                context: context,
                result: result,
                recentObservations: recentObservations,
              );

              await recoveryManager.saveAfterToolCall(
                taskId: taskId,
                context: context,
                plan: plan,
                toolCallCount: toolCallCount,
                pendingStepId: step.id,
                toolName: call.name,
                toolIdempotent: tool.idempotent,
                argumentsHash: _argsHash(call.arguments),
              );

              emit(
                TaskProgress(
                  taskId: taskId,
                  timestamp: _now(),
                  message: 'Completed tool ${call.name}',
                  completedSteps: plan.completedSteps.length,
                  totalSteps: plan.steps.length,
                  toolCallsUsed: toolCallCount,
                ),
              );

              if (!result.success) {
                plan = plan.updateStep(
                  step.id,
                  (s) => s.copyWith(
                    status: PlanStepStatus.failed,
                    error: result.errorMessage ?? result.errorCode,
                  ),
                );
                plan = await brain.replan(
                  currentPlan: plan,
                  taskId: taskId,
                  failureReason:
                      result.errorMessage ?? result.errorCode ?? 'Tool failed',
                  recentObservations: List<ToolResult>.unmodifiable(
                    recentObservations,
                  ),
                );
                emit(
                  PlanUpdated(
                    taskId: taskId,
                    timestamp: _now(),
                    steps: plan.steps,
                    revision: plan.revision,
                    reason: result.errorCode ?? 'tool_failure',
                  ),
                );
                replanned = true;
                break;
              }
            }
            if (replanned) continue;
            // stay on same in-progress step so brain can observe tool results and decide
            continue;
        }
      }
    } on CancelledException catch (e) {
      emit(
        TaskCancelled(
          taskId: taskId,
          timestamp: _now(),
          reason: e.reason ?? cancel.reason,
        ),
      );
      return LoopOutcome.cancelled(e.reason ?? cancel.reason);
    } on TaskBudgetExceededException catch (e) {
      emit(
        TaskFailed(
          taskId: taskId,
          timestamp: _now(),
          code: e.code,
          message: e.message,
        ),
      );
      return LoopOutcome.failed(e.code, e.message);
    } on LoopDetectedException catch (e) {
      emit(
        TaskFailed(
          taskId: taskId,
          timestamp: _now(),
          code: ShadowErrorCode.agentLoopDetected,
          message: e.message,
        ),
      );
      return LoopOutcome.failed(ShadowErrorCode.agentLoopDetected, e.message);
    } catch (e) {
      emit(
        TaskFailed(
          taskId: taskId,
          timestamp: _now(),
          code: ShadowErrorCode.toolFailed,
          message: e.toString(),
        ),
      );
      return LoopOutcome.failed(ShadowErrorCode.toolFailed, e.toString());
    }
  }

  /// Rebuilds the budgeted context snapshot after every tool result so the
  /// model always sees a bounded, deterministic view of the task.
  void _updateContext({
    required String taskId,
    required AgentContext context,
    required ToolResult result,
    required List<ToolResult> recentObservations,
  }) {
    final assembler = contextAssembler;
    final holder = contextHolder;
    if (assembler == null || holder == null) return;
    final snapshot = assembler.build(
      projectId: taskId,
      projectRevision: context.projectRevision,
      workspaceRoot: context.workspaceRoot,
      mediaAssets:
          (context.metadata['media_assets'] as List<Object?>?)
              ?.whereType<Map<String, Object?>>()
              .toList(growable: false) ??
          const <Map<String, Object?>>[],
      currentTaskProgress: <String, Object?>{
        'tool_calls': recentObservations.length,
        'last_tool': result.data['tool'] ?? 'unknown',
        'last_success': result.success,
      },
      previousToolResults: recentObservations
          .map(
            (r) => <String, Object?>{
              'success': r.success,
              'data': r.data,
              'error_code': r.errorCode,
            },
          )
          .toList(growable: false),
    );
    holder.snapshot = snapshot;
    emit(ContextUpdated(taskId: taskId, timestamp: _now(), snapshot: snapshot));
  }

  Future<ToolResult> _executeWithRetries({
    required String taskId,
    required AIToolCall call,
    required AgentTool tool,
    required AgentContext context,
    required CancellationToken cancel,
    required AuditSink audit,
    required ApprovalToken? approval,
    required void Function() checkCancellation,
    required void Function() checkTime,
  }) async {
    final maxAttempts = 1 + limits.maxRetriesPerTool;
    ToolResult? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      checkCancellation();
      checkTime();
      emit(
        ToolExecutionStarted(
          taskId: taskId,
          timestamp: _now(),
          callId: call.id,
          toolName: call.name,
          attempt: attempt,
        ),
      );
      try {
        final ctx = ToolContext(
          taskId: taskId,
          correlationId: call.id,
          revision: context.projectRevision,
          workspaceRoot: context.workspaceRoot,
          cancel: cancel,
          audit: audit,
          approval: approval,
        );
        last = await toolExecutor.execute(call: call, context: ctx, tool: tool);
      } catch (e) {
        last = ToolResult(
          success: false,
          errorCode: ShadowErrorCode.toolFailed,
          errorMessage: e.toString(),
        );
      }
      emit(
        ToolExecutionCompleted(
          taskId: taskId,
          timestamp: _now(),
          callId: call.id,
          toolName: call.name,
          result: last,
          attempt: attempt,
        ),
      );
      if (last.success) return last;
      if (attempt >= maxAttempts) return last;
      // do not retry non-idempotent tools without fresh explicit approval path
      if (!tool.idempotent) return last;
    }
    return last ??
        const ToolResult(
          success: false,
          errorCode: ShadowErrorCode.toolFailed,
          errorMessage: 'Unknown tool failure',
        );
  }

  bool _requiresApproval(AgentTool tool) =>
      tool.riskLevel != ToolRiskLevel.safe;

  static String _toolSignature(String name, Map<String, Object?> args) =>
      '$name:${_argsHash(args)}';
  static String _argsHash(Map<String, Object?> args) {
    final s = jsonEncode(_canonicalize(args));
    return _fnv1a64Hex(s);
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      return <String, Object?>{
        for (final k in keys) k: _canonicalize(value[k]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  static String _fnv1a64Hex(String input) {
    const int fnvOffset = 0xcbf29ce484222325;
    const int fnvPrime = 0x100000001b3;
    const int mask64 = 0xFFFFFFFFFFFFFFFF;
    var hash = fnvOffset;
    for (final code in utf8.encode(input)) {
      hash ^= code;
      hash = (hash * fnvPrime) & mask64;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
