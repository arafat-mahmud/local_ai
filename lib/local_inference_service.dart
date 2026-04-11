import 'dart:async';

import 'package:fllama/fllama.dart';
import 'package:fllama/fllama_type.dart';

import 'chat_types.dart';

class LocalInferenceService {
  double? _contextId;
  bool _isBusy = false;

  bool get isReady => _contextId != null;
  bool get isBusy => _isBusy;

  Future<void> ensureInitialized({required String modelPath}) async {
    if (_contextId != null) {
      return;
    }
    final Map<Object?, dynamic>? context = await Fllama.instance()?.initContext(
      modelPath,
      nCtx: 2048,
      nBatch: 256,
      nThreads: 4,
      nGpuLayers: 0,
      useMmap: true,
      useMlock: false,
      emitLoadProgress: false,
    );
    final Object? rawId = context?['contextId'];
    final double? parsed = rawId is num
        ? rawId.toDouble()
        : double.tryParse(rawId?.toString() ?? '');
    if (parsed == null || parsed <= 0) {
      throw StateError('Could not initialize local model context.');
    }
    _contextId = parsed;
  }

  Future<String> complete({
    required List<ChatTurn> history,
    int maxTokens = 220,
  }) async {
    final double? contextId = _contextId;
    if (contextId == null) {
      throw StateError('Model context is not initialized.');
    }
    if (_isBusy) {
      throw StateError('Model is busy. Please wait for current response.');
    }
    _isBusy = true;
    try {
      final List<RoleContent> messages = <RoleContent>[
        RoleContent(
          role: 'system',
          content:
              'You are a helpful offline AI assistant inside a mobile app. Keep answers concise and clear.',
        ),
        ...history.map((ChatTurn turn) {
          return RoleContent(
            role: turn.role == ChatRole.user ? 'user' : 'assistant',
            content: turn.text,
          );
        }),
      ];
      final String formattedPrompt =
          await Fllama.instance()?.getFormattedChat(
            contextId,
            messages: messages,
          ) ??
          '';
      final Map<Object?, dynamic>? result = await Fllama.instance()?.completion(
        contextId,
        prompt: formattedPrompt,
        nPredict: maxTokens,
        temperature: 0.4,
        topP: 0.9,
        topK: 40,
        penaltyRepeat: 1.08,
        penaltyLastN: 128,
        emitRealtimeCompletion: false,
        stop: <String>['<|im_end|>', 'USER:', '\nUser:'],
      );
      final String text = (result?['text'] ?? result?['content'] ?? '')
          .toString()
          .trim();
      if (text.isEmpty) {
        throw StateError('Model returned an empty response.');
      }
      return text;
    } finally {
      _isBusy = false;
    }
  }

  Future<void> dispose() async {
    final double? contextId = _contextId;
    _contextId = null;
    if (contextId != null) {
      await Fllama.instance()?.releaseContext(contextId);
    }
  }
}
