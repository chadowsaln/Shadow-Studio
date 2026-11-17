import 'package:shadow_agent_runtime/agent_runtime.dart';
import 'package:shadow_contracts/shadow_contracts.dart';
import 'package:test/test.dart';

import 'test_support.dart';

/// A brain that calls [toolName] once and then fails the task.
AgentBrain _toolThenFailBrain(String toolName, String code) {
  var called = false;
  return CallbackAgentBrain(
    onNextDecision:
        ({required plan, required currentStepId, required history}) async {
          if (called) {
            return FailDecision(code, 'tool failed: $toolName');
          }
          called = true;
          return ToolCallsDecision(<AIToolCall>[
            AIToolCall(id: 'call_1', name: toolName, arguments: const {}),
          ]);
        },
  );
}

/// A brain that calls [toolName] once, then completes.
AgentBrain _oneToolBrain(String toolName, Map<String, Object?> args) {
  var called = false;
  return CallbackAgentBrain(
    onNextDecision:
        ({required plan, required currentStepId, required history}) async {
          if (called) {
            return const CompleteDecision(summary: 'done');
          }
          called = true;
          return ToolCallsDecision(<AIToolCall>[
            AIToolCall(id: 'call_1', name: toolName, arguments: args),
          ]);
        },
  );
}

void main() {
  group('agent roles', () {
    test('declares the six specialized roles with tool scopes', () {
      expect(AgentRole.values, hasLength(6));
      expect(
        AgentRole.values.map((r) => r.id).toSet(),
        containsAll(<String>[
          'project_manager',
          'video_analysis',
          'video_editing',
          'audio_engineering',
          'subtitle',
          'quality_assurance',
        ]),
      );
      expect(AgentRole.videoEditing.defaultTools, contains('timeline_edit'));
      expect(
        AgentRole.videoEditing.defaultTools,
        isNot(contains('media_analysis')),
      );
      expect(AgentRole.videoAnalysis.defaultTools, contains('media_probe'));
      expect(AgentRole.fromId('subtitle'), AgentRole.subtitle);
      expect(AgentRole.fromId('nope'), isNull);
    });
  });

  group('role tool filter', () {
    test('hides tools outside the role scope', () {
      final inner = FakeToolExecutor(<AgentTool>[
        FakeTool(name: 'media_probe'),
        FakeTool(name: 'timeline_edit'),
      ]);
      final filtered = RoleToolFilter(
        delegate: inner,
        allowedTools: AgentRole.videoEditing.defaultTools,
      );

      expect(filtered.resolve('timeline_edit'), isNotNull);
      expect(filtered.resolve('media_analysis'), isNull);
    });

    test('refuses to execute a filtered tool even when forced', () async {
      final tool = FakeTool(name: 'media_probe');
      final filtered = RoleToolFilter(
        delegate: FakeToolExecutor(<AgentTool>[tool]),
        allowedTools: const <String>{'timeline_edit'},
      );

      final result = await filtered.execute(
        call: const AIToolCall(id: 'c1', name: 'media_probe', arguments: {}),
        context: ToolContext(
          taskId: 't1',
          correlationId: 'c1',
          revision: 0,
          workspaceRoot: '.',
          cancel: CancellationToken(),
          audit: MemoryAuditSink(),
        ),
        tool: tool,
      );

      expect(result.success, isFalse);
      expect(result.errorCode, ShadowErrorCode.toolNotFound);
      expect(tool.calls, 0);
    });
  });

  group('specialized agent', () {
    test('runs a sub-task to completion through the shared loop', () async {
      final tool = FakeTool(name: 'media_probe');
      final agent = SpecializedAgent(
        role: AgentRole.videoAnalysis,
        controllerFactory: () => AgentController(
          brain: _oneToolBrain('media_probe', const <String, Object?>{}),
          toolExecutor: FakeToolExecutor(<AgentTool>[tool]),
        ),
      );

      final task = await agent.run(
        request: 'Probe the source video',
        workspaceRoot: '.',
        projectRevision: 0,
      );

      expect(task.state, ManagedTaskState.succeeded);
      expect(tool.calls, 1);
      await agent.dispose();
    });

    test('reports failure instead of pretending success', () async {
      final tool = FakeTool(
        name: 'media_probe',
        handler: (ctx, args) async => const ToolResult.failure(
          code: 'MEDIA_ASSET_MISSING',
          message: 'missing',
        ),
      );
      final agent = SpecializedAgent(
        role: AgentRole.videoAnalysis,
        controllerFactory: () => AgentController(
          brain: _toolThenFailBrain('media_probe', 'MEDIA_ASSET_MISSING'),
          toolExecutor: FakeToolExecutor(<AgentTool>[tool]),
        ),
      );

      final task = await agent.run(
        request: 'Probe a missing file',
        workspaceRoot: '.',
        projectRevision: 0,
      );

      expect(task.state, isNot(ManagedTaskState.succeeded));
      expect(task.errorCode, isNotNull);
      await agent.dispose();
    });

    test('passes inbound messages into the sub-task request', () async {
      final seen = <String>[];
      final agent = SpecializedAgent(
        role: AgentRole.videoEditing,
        controllerFactory: () => AgentController(
          brain: CallbackAgentBrain(
            onNextDecision:
                ({
                  required plan,
                  required currentStepId,
                  required history,
                }) async {
                  seen.add(history.first.content ?? '');
                  return const CompleteDecision(summary: 'ok');
                },
          ),
          toolExecutor: FakeToolExecutor(),
        ),
      );

      await agent.run(
        request: 'Edit the timeline',
        workspaceRoot: '.',
        projectRevision: 0,
        inbound: AgentMessage(
          id: 'm1',
          taskId: 'root',
          from: AgentRole.projectManager,
          to: AgentRole.videoEditing,
          type: AgentMessageType.task,
          content: const <String, Object?>{'shot': 'intro'},
          createdAt: DateTime.utc(2026),
        ),
      );

      expect(seen.single, contains('project_manager -> video_editing'));
      expect(seen.single, contains('shot'));
      await agent.dispose();
    });
  });

  group('multi-agent coordinator', () {
    test('folds artifacts and messages into shared state', () async {
      final analysisTool = FakeTool(
        name: 'media_analysis',
        handler: (ctx, args) async =>
            ToolResult.ok(data: const <String, Object?>{'scene_count': 4}),
      );
      final editTool = FakeTool(
        name: 'timeline_edit',
        handler: (ctx, args) async =>
            ToolResult.ok(data: const <String, Object?>{'revision': 3}),
      );

      AgentBrain brainFor(AgentRole role) => switch (role) {
        AgentRole.videoAnalysis => _oneToolBrain(
          'media_analysis',
          const <String, Object?>{'path': 'intro.mp4'},
        ),
        AgentRole.videoEditing => _oneToolBrain(
          'timeline_edit',
          const <String, Object?>{'revision': 0, 'applied': <Object?>[]},
        ),
        _ => CallbackAgentBrain(
          onNextDecision:
              ({
                required plan,
                required currentStepId,
                required history,
              }) async => const CompleteDecision(summary: 'nothing to do'),
        ),
      };

      final coordinator = MultiAgentCoordinator(
        taskId: 'root',
        goal: 'Ship a 30s ad',
        workspaceRoot: '.',
        projectRevision: 0,
        brainFactory: brainFor,
        toolExecutor: FakeToolExecutor(<AgentTool>[analysisTool, editTool]),
      );
      addTearDown(coordinator.dispose);

      final outcomes = await coordinator.runAll(<AgentAssignment>[
        AgentAssignment(
          role: AgentRole.videoAnalysis,
          request: 'Analyze source',
        ),
        AgentAssignment(
          role: AgentRole.videoEditing,
          request: 'Build timeline',
        ),
      ]);

      expect(outcomes, hasLength(2));
      expect(outcomes.every((o) => o.succeeded), isTrue);
      expect(coordinator.artifacts['video_analysis.summary'], 'done');
      expect(coordinator.projectRevision, 3);
      expect(coordinator.state.messages, isNotEmpty);
      expect(
        coordinator.state.roleState(AgentRole.videoEditing)?.status,
        'completed',
      );
    });

    test('routes structured messages and records them', () {
      final coordinator = MultiAgentCoordinator(
        taskId: 'root',
        goal: 'Ship a 30s ad',
        workspaceRoot: '.',
        projectRevision: 0,
        brainFactory: (_) => CallbackAgentBrain(),
        toolExecutor: FakeToolExecutor(),
      );

      final message = coordinator.send(
        from: AgentRole.projectManager,
        to: AgentRole.audioEngineering,
        type: AgentMessageType.approvalRequested,
        content: const <String, Object?>{'asset': 'vo-take3.wav'},
      );

      expect(coordinator.messages.single.id, message.id);
      expect(coordinator.state.roleState(AgentRole.projectManager), isNotNull);
      expect(message.to, AgentRole.audioEngineering);
    });

    test('rejects messages belonging to another task', () {
      final coordinator = MultiAgentCoordinator(
        taskId: 'root',
        goal: 'Ship a 30s ad',
        workspaceRoot: '.',
        projectRevision: 0,
        brainFactory: (_) => CallbackAgentBrain(),
        toolExecutor: FakeToolExecutor(),
      );

      expect(
        () => coordinator.dispatch(
          AgentMessage(
            id: 'x',
            taskId: 'other',
            from: AgentRole.videoAnalysis,
            type: AgentMessageType.observation,
            content: const <String, Object?>{},
            createdAt: DateTime.utc(2026),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('keeps a failed assignment visible as failed', () async {
      final failing = FakeTool(
        name: 'media_probe',
        handler: (ctx, args) async =>
            const ToolResult.failure(code: 'MEDIA_CORRUPT', message: 'corrupt'),
      );
      final coordinator = MultiAgentCoordinator(
        taskId: 'root',
        goal: 'Ship a 30s ad',
        workspaceRoot: '.',
        projectRevision: 0,
        brainFactory: (_) => _toolThenFailBrain('media_probe', 'MEDIA_CORRUPT'),
        toolExecutor: FakeToolExecutor(<AgentTool>[failing]),
      );
      addTearDown(coordinator.dispose);

      final outcomes = await coordinator.runAll(<AgentAssignment>[
        AgentAssignment(role: AgentRole.videoAnalysis, request: 'Analyze'),
      ]);

      expect(outcomes.single.succeeded, isFalse);
      expect(coordinator.status, SharedTaskStatus.failed);
      expect(
        coordinator.artifacts['video_analysis.error'],
        isA<Map<String, Object?>>(),
      );
    });

    test('stops at the first failure unless told to continue', () async {
      var probeCalls = 0;
      final probe = FakeTool(
        name: 'media_probe',
        handler: (ctx, args) async {
          probeCalls++;
          return const ToolResult.failure(
            code: 'MEDIA_CORRUPT',
            message: 'corrupt',
          );
        },
      );
      final edit = FakeTool(name: 'timeline_edit');

      AgentBrain brainFor(AgentRole role) => role == AgentRole.videoEditing
          ? _oneToolBrain('timeline_edit', const {})
          : _toolThenFailBrain('media_probe', 'MEDIA_CORRUPT');

      final coordinator = MultiAgentCoordinator(
        taskId: 'root',
        goal: 'Ship a 30s ad',
        workspaceRoot: '.',
        projectRevision: 0,
        brainFactory: brainFor,
        toolExecutor: FakeToolExecutor(<AgentTool>[probe, edit]),
      );
      addTearDown(coordinator.dispose);

      final outcomes = await coordinator.runAll(<AgentAssignment>[
        AgentAssignment(role: AgentRole.videoAnalysis, request: 'Analyze'),
        AgentAssignment(role: AgentRole.videoEditing, request: 'Edit'),
      ]);

      expect(outcomes, hasLength(1));
      expect(edit.calls, 0);
      // idempotent tools are retried before the failure is surfaced
      expect(probeCalls, greaterThan(0));
    });
  });
}
