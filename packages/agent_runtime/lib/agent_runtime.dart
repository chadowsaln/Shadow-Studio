export 'src/agent_context.dart';
export 'src/agent_context_assembler.dart';
export 'src/agent_controller.dart';
export 'src/agent_events.dart';
export 'src/agent_limits.dart';
export 'src/execution_loop.dart';
export 'src/planner.dart';
export 'src/recovery_manager.dart';
export 'src/task_scheduler.dart';
export 'src/default_brain.dart';
export 'src/multi_agent/agent_message.dart';
export 'src/provider_agent_brain.dart';
export 'src/multi_agent/agent_role.dart';
export 'src/multi_agent/multi_agent_coordinator.dart';
export 'src/multi_agent/shared_task_state.dart';
export 'src/multi_agent/specialized_agent.dart';

// Re-exported contracts so existing `package:shadow_agent_runtime` consumers keep working.
export 'package:shadow_contracts/shadow_contracts.dart'
    show
        AgentPlan,
        PlanStep,
        PlanStepStatus,
        Planner,
        AgentDecision,
        CompleteDecision,
        ToolCallsDecision,
        ReplanDecision,
        FailDecision,
        AgentBrain,
        ToolCallExecutor,
        ApprovalGate,
        AgentCheckpoint,
        CheckpointStore;
