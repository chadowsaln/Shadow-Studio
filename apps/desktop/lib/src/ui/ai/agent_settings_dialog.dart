import 'package:flutter/material.dart';

import '../../agent/agent_session_controller.dart';
import '../../agent/agent_settings.dart';
import '../../theme/shadow_colors.dart';
import '../../theme/shadow_typography.dart';

/// Provider/model/API-key configuration for the desktop AI agent.
class AgentSettingsDialog extends StatefulWidget {
  const AgentSettingsDialog({super.key, required this.session});

  final AgentSessionController session;

  @override
  State<AgentSettingsDialog> createState() => _AgentSettingsDialogState();
}

class _AgentSettingsDialogState extends State<AgentSettingsDialog> {
  late String _providerId;
  late final TextEditingController _modelController;
  late final TextEditingController _baseUriController;
  final TextEditingController _apiKeyController = TextEditingController();
  bool _saving = false;
  bool _obscureKey = true;
  bool _savedKeyForSelected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.session.settings ?? AgentSettings.defaults();
    _providerId = settings.providerId;
    _modelController = TextEditingController(text: settings.model);
    _baseUriController = TextEditingController(
      text: settings.baseUri?.toString() ?? '',
    );
    _loadSavedKey();
  }

  Future<void> _loadSavedKey() async {
    final hasKey = await widget.session.settingsStore.hasApiKey(_providerId);
    if (!mounted) return;
    setState(() => _savedKeyForSelected = hasKey);
  }

  @override
  void dispose() {
    _modelController.dispose();
    _baseUriController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final model = _modelController.text.trim();
    if (model.isEmpty) {
      setState(() => _error = 'Model must not be empty');
      return;
    }
    final rawBase = _baseUriController.text.trim();
    final baseUri = rawBase.isEmpty ? null : Uri.tryParse(rawBase);
    if (rawBase.isNotEmpty && (baseUri == null || !baseUri.hasScheme)) {
      setState(() => _error = 'Base URL must be an absolute URI');
      return;
    }
    final key = _apiKeyController.text.trim();
    if (key.isEmpty && !_savedKeyForSelected) {
      setState(() => _error = 'An API key is required for this provider');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.session.saveSettings(
        AgentSettings(
          providerId: _providerId,
          model: model,
          baseUri: baseUri,
        ),
        apiKey: key.isEmpty ? null : key,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save settings: $error';
      });
    }
  }

  void _selectProvider(String id) {
    final previousDefault = agentProviderFor(_providerId).defaultModel;
    final next = agentProviderFor(id);
    setState(() {
      _providerId = id;
      if (_modelController.text.trim().isEmpty ||
          _modelController.text.trim() == previousDefault) {
        _modelController.text = next.defaultModel;
      }
      _savedKeyForSelected = false;
    });
    _loadSavedKey();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ShadowColors.of(context);
    final provider = agentProviderFor(_providerId);
    final savedKey = _savedKeyForSelected;

    return AlertDialog(
      backgroundColor: colors.surface1,
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: colors.accent, size: 20),
          const SizedBox(width: 8),
          Text(
            'AI Provider',
            style: ShadowTypography.title.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The API key is stored encrypted on this device. It is never written to the project file or activity log.',
              style: ShadowTypography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _providerId,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final option in agentProviders)
                  DropdownMenuItem(
                    value: option.id,
                    child: Text(option.label),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) _selectProvider(value);
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              enabled: !_saving,
              obscureText: _obscureKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: savedKey
                    ? 'A key is saved — leave blank to keep it'
                    : 'Paste the provider API key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscureKey ? 'Show key' : 'Hide key',
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  icon: Icon(
                    _obscureKey ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUriController,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: 'Base URL (optional)',
                hintText: provider.defaultBaseUri,
                border: const OutlineInputBorder(),
              ),
            ),
            if (savedKey) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: colors.success),
                  const SizedBox(width: 6),
                  Text(
                    'Encrypted key available for ${provider.label}',
                    style: ShadowTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: ShadowTypography.body.copyWith(color: colors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
          ),
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
