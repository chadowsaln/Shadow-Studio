/// Pure Dart Editing Core for Shadow Studio.
///
/// Contains:
/// - Immutable project document model ([ProjectDocument], [Track], [Clip], [Asset], [ProjectProfile], [Timebase]).
/// - Pure editing commands with full inverses ([AddTrackCommand], [RemoveTrackCommand], [AddClipCommand], [RemoveClipCommand], [MoveClipCommand], [TrimClipCommand], [SplitClipCommand], [JoinClipCommand], [AddAssetCommand], [RemoveAssetCommand]).
/// - Atomic transactions ([EditTransaction], [EditOutcome], [EditSuccess], [EditFailure]).
/// - Invariant validation ([DocumentInvariants], [ShadowError]).
/// - Editing service port ([EditingService], [DefaultEditingService]).
/// - Time & tick conversions ([TimeTicks]).
/// - UUIDv7 generation ([UuidV7]).
library editing_core;

export 'src/commands/add_clip_command.dart';
export 'src/commands/add_track_command.dart';
export 'src/commands/add_transition_command.dart';
export 'src/commands/asset_commands.dart';
export 'src/commands/audio_mix_commands.dart';
export 'src/commands/clip_effect_commands.dart';
export 'src/commands/edit_command.dart';
export 'src/commands/join_clip_command.dart';
export 'src/commands/move_clip_command.dart';
export 'src/commands/remove_clip_command.dart';
export 'src/commands/remove_track_command.dart';
export 'src/commands/remove_transition_command.dart';
export 'src/commands/text_layer_commands.dart';
export 'src/commands/split_clip_command.dart';
export 'src/commands/trim_clip_command.dart';
export 'src/error/shadow_error.dart';
export 'src/invariants/document_invariants.dart';
export 'src/model/asset.dart';
export 'src/model/clip.dart';
export 'src/model/effect.dart';
export 'src/model/keyframe.dart';
export 'src/model/param.dart';
export 'src/model/project_document.dart';
export 'src/model/project_profile.dart';
export 'src/model/range_ticks.dart';
export 'src/model/render_graph.dart';
export 'src/model/render_graph_clip.dart';
export 'src/model/render_graph_track.dart';
export 'src/model/text_layer.dart';
export 'src/model/timebase.dart';
export 'src/model/track.dart';
export 'src/model/transform_box.dart';
export 'src/model/transition.dart';
export 'src/model/transition_kind.dart';
export 'src/service/default_editing_service.dart';
export 'src/service/editing_service.dart';
export 'src/time/time_ticks.dart';
export 'src/transaction/edit_outcome.dart';
export 'src/transaction/edit_transaction.dart';
export 'src/uuid/uuid_v7.dart';
