import 'dart:async';

import 'package:fllama/fllama.dart';
import 'package:fllama/fllama_type.dart';
import 'package:flutter/services.dart';

import 'chat_types.dart';

class LocalInferenceService {
  static const String _systemInstruction =
      'You are a helpful offline AI assistant inside the PocketBrain mobile app. '
      'Keep answers concise and clear.';

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
          content: _systemInstruction,
        ),
        ...history.map((ChatTurn turn) {
          return RoleContent(
            role: turn.role == ChatRole.user ? 'user' : 'assistant',
            content: turn.text,
          );
        }),
      ];
      String formattedPrompt;
      try {
        formattedPrompt =
            await Fllama.instance()?.getFormattedChat(
              contextId,
              messages: messages,
            ) ??
            '';
      } on PlatformException catch (error) {
        final bool isAndroidMessageCastBug =
            (error.message ?? '').contains(
              'ArrayList cannot be cast to java.util.HashMap[]',
            ) ||
            (error.details?.toString() ?? '').contains(
              'ArrayList cannot be cast to java.util.HashMap[]',
            );
        if (!isAndroidMessageCastBug) {
          rethrow;
        }
        formattedPrompt = _buildPromptFallback(history);
      }
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
        stop: <String>[
          '<|im_end|>',
          '<|endoftext|>',
          'USER:',
          '\nUser:',
          '\nHuman:',
          '\nAssistant:',
        ],
      );
      final String text = _sanitizeAssistantReply(
        (result?['text'] ?? result?['content'] ?? '').toString(),
      );
      if (text.isEmpty) {
        throw StateError('Model returned an empty response.');
      }
      return text;
    } finally {
      _isBusy = false;
    }
  }

  String _buildPromptFallback(List<ChatTurn> history) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('System: $_systemInstruction')
      ..writeln();
    for (final ChatTurn turn in history) {
      final String role = turn.role == ChatRole.user ? 'User' : 'Assistant';
      buffer
        ..writeln('$role: ${turn.text}')
        ..writeln();
    }
    buffer.write('Assistant:');
    return buffer.toString();
  }

  String _sanitizeAssistantReply(String raw) {
    String text = raw.trim();
    const List<String> cutMarkers = <String>[
      '<|endoftext|>',
      '<|im_end|>',
      '\nHuman:',
      '\nUser:',
      '\nAssistant:',
      'Human:',
      'User:',
      'Assistant:',
    ];
    int? cutAt;
    for (final String marker in cutMarkers) {
      final int index = text.indexOf(marker);
      if (index > 0 && (cutAt == null || index < cutAt)) {
        cutAt = index;
      }
    }
    if (cutAt != null) {
      text = text.substring(0, cutAt).trim();
    }
    return text;
  }

  Future<void> dispose() async {
    final double? contextId = _contextId;
    _contextId = null;
    if (contextId != null) {
      await Fllama.instance()?.releaseContext(contextId);
    }
  }
}
