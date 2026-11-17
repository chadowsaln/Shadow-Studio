import 'dart:convert';

import 'package:shadow_context_engine/context_engine.dart';
import 'package:test/test.dart';

ContextBuildInput _input({
  List<Map<String, Object?>> mediaAssets = const <Map<String, Object?>>[],
  List<Map<String, Object?>> toolResults = const <Map<String, Object?>>[],
  Map<String, Object?> progress = const <String, Object?>{},
  bool egressConsentGranted = false,
}) {
  return ContextBuildInput(
    projectId: 'p1',
    projectRevision: 7,
    workspaceRoot: '/work/p1',
    mediaAssets: mediaAssets,
    selectedTimelineClipIds: const <String>['c1', 'c2'],
    timelineStructure: const <String, Object?>{
      'tracks': <Map<String, Object?>>[
        {
          'id': 't1',
          'clips': <String>['c1'],
        },
      ],
    },
    availableEditingTools: const <Map<String, Object?>>[
      {'name': 'trim_clip', 'risk': 'low'},
    ],
    environmentCapabilities: const <String, Object?>{'ffmpeg': true},
    currentTaskProgress: progress,
    previousToolExecutionResults: toolResults,
    egressConsentGranted: egressConsentGranted,
  );
}

void main() {
  group('ContextBuilder sanitization', () {
    test('never carries raw media bytes, even when egress is consented', () {
      final manager = ContextManager();
      final snapshot = manager.snapshotFor(
        _input(
          egressConsentGranted: true,
          mediaAssets: const <Map<String, Object?>>[
            {
              'id': 'a1',
              'name': 'clip.mp4',
              'kind': 'video',
              'bytes': 'AAAA',
              'data': <int>[1, 2, 3],
              'blob': 'opaque',
              'fileBytes': <int>[9],
              'inlineContent': 'huge',
            },
          ],
        ),
      );

      final encoded = jsonEncode(snapshot.toJson());
      for (final blocked in const <String>[
        '"bytes"',
        '"data"',
        '"blob"',
        '"fileBytes"',
        '"inlineContent"',
      ]) {
        expect(encoded.contains(blocked), isFalse, reason: 'blocked $blocked');
      }
      expect(snapshot.mediaAssets.single['id'], 'a1');
      expect(snapshot.mediaAssets.single['egressConsentGranted'], isTrue);
    });

    test('clamps oversized tool result payloads', () {
      final manager = ContextManager();
      final snapshot = manager.snapshotFor(
        _input(
          toolResults: <Map<String, Object?>>[
            {'success': true, 'data': 'x' * 9000},
          ],
        ),
      );
      final data =
          snapshot.previousToolExecutionResults.single['data'] as String;
      expect(data.length, lessThanOrEqualTo(4100));
      expect(data, endsWith('[truncated]'));
    });
  });

  group('ContextTrimmer budgeting', () {
    test('drops oldest tool results before project context', () {
      final manager = ContextManager(defaultTokenBudget: 120);
      final snapshot = manager.snapshotFor(
        _input(
          toolResults: <Map<String, Object?>>[
            {'success': true, 'data': 'old-' * 40},
            {'success': true, 'data': 'new-' * 40},
          ],
        ),
      );

      expect(snapshot.estimatedTokens, lessThanOrEqualTo(snapshot.tokenBudget));
      expect(
        snapshot.truncatedSections,
        contains('previousToolExecutionResults'),
      );
      expect(snapshot.projectId, 'p1');
      expect(snapshot.projectRevision, 7);
      expect(snapshot.selectedTimelineClipIds, <String>['c1', 'c2']);
    });

    test('context hash is stable for identical inputs', () {
      final manager = ContextManager();
      final a = manager.snapshotFor(_input());
      final b = manager.snapshotFor(_input());
      expect(a.contextHash, b.contextHash);
    });

    test('context hash changes when project revision changes', () {
      final manager = ContextManager();
      final a = manager.snapshotFor(_input());
      final b = manager.snapshotFor(
        ContextBuildInput(
          projectId: 'p1',
          projectRevision: 8,
          workspaceRoot: '/work/p1',
        ),
      );
      expect(a.contextHash, isNot(b.contextHash));
    });
  });
}
