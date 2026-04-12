import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'chat_storage_service.dart';
import 'chat_types.dart';
import 'developer_info_screen.dart';
import 'local_inference_service.dart';
import 'model_update_service.dart';

const String kChatModelManifestUrl = String.fromEnvironment(
  'MODEL_MANIFEST_URL',
  defaultValue:
      'https://huggingface.co/arafat-mahmud/smollm2-1.7b-q8-local-ai/resolve/main/model_manifest.json',
);

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.modelReady,
    required this.modelLabel,
    required this.hasModelUpdate,
    this.modelFilePath,
    this.startNewSessionOnLaunch = false,
  });

  final bool modelReady;
  final String modelLabel;
  final bool hasModelUpdate;
  final String? modelFilePath;
  final bool startNewSessionOnLaunch;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const String _initialAssistantGreeting =
      'Hi. I am ready. Downloaded model can answer here in offline mode.';

  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _messageKeys = <GlobalKey>[];
  final ChatStorageService _storage = ChatStorageService.instance;
  final LocalInferenceService _inference = LocalInferenceService();
  late final ModelUpdateService _modelService;

  List<_ChatMessage> _messages = <_ChatMessage>[];
  List<ChatSessionRecord> _sessions = <ChatSessionRecord>[];
  String? _activeSessionId;
  bool _activeSessionPersisted = false;

  bool _isTyping = false;
  bool _isPreparingModel = false;
  String _appVersion = 'Loading...';
  bool _hasModelUpdateLive = false;
  RemoteModelManifest? _latestManifest;
  bool _blinkOn = true;
  Timer? _blinkTimer;
  Timer? _updatePollTimer;

  @override
  void initState() {
    super.initState();
    _modelService = ModelUpdateService(
      config: const ModelUpdateConfig(manifestUrl: kChatModelManifestUrl),
    );
    _hasModelUpdateLive = widget.hasModelUpdate;
    _setupBlinking();
    _loadAppVersion();
    _initializeChatData();
    unawaited(_refreshModelUpdateStatus(fullInit: true));
    _startUpdatePolling();
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _updatePollTimer?.cancel();
    _modelService.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _inference.dispose();
    super.dispose();
  }

  void _setupBlinking() {
    if (!_hasModelUpdateLive) {
      _blinkTimer?.cancel();
      _blinkOn = true;
      return;
    }
    _blinkTimer?.cancel();
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _blinkOn = !_blinkOn;
      });
    });
  }

  void _startUpdatePolling() {
    _updatePollTimer?.cancel();
    _updatePollTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(_refreshModelUpdateStatus());
    });
  }

  Future<void> _refreshModelUpdateStatus({bool fullInit = false}) async {
    try {
      if (fullInit) {
        await _modelService.initialize(autoCheckRemote: true);
      } else {
        await _modelService.checkForUpdates();
      }
    } catch (_) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hasModelUpdateLive = _modelService.hasUpdateAvailable;
      _latestManifest = _modelService.latestManifest;
    });
    _setupBlinking();
  }

  Future<void> _loadAppVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersion = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersion = 'Unavailable';
      });
    }
  }

  Future<void> _initializeChatData() async {
    await _refreshSessions();
    if (widget.startNewSessionOnLaunch || _sessions.isEmpty) {
      await _createAndSwitchToNewSession();
      return;
    }
    await _switchSession(_sessions.first.id, closeDrawer: false);
  }

  Future<void> _refreshSessions() async {
    final List<ChatSessionRecord> sessions = await _storage.listSessions();
    if (!mounted) {
      return;
    }
    setState(() {
      _sessions = sessions;
    });
  }

  Future<void> _createAndSwitchToNewSession() async {
    final DateTime now = DateTime.now();
    final String sessionId = 'session_${now.microsecondsSinceEpoch}';
    if (!mounted) {
      return;
    }
    setState(() {
      _activeSessionId = sessionId;
      _activeSessionPersisted = false;
      _messages = <_ChatMessage>[
        const _ChatMessage(
          role: ChatRole.assistant,
          text: _initialAssistantGreeting,
        ),
      ];
      _messageKeys
        ..clear()
        ..add(GlobalKey());
    });
    _scrollToBottom();
  }

  Future<void> _switchSession(
    String sessionId, {
    bool closeDrawer = true,
  }) async {
    final List<ChatMessageRecord> rows = await _storage.listMessagesForSession(
      sessionId,
    );
    final List<_ChatMessage> loaded = rows
        .map((_fromRecord))
        .toList(growable: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _activeSessionId = sessionId;
      _activeSessionPersisted = true;
      _messages = loaded;
      _messageKeys
        ..clear()
        ..addAll(
          List<GlobalKey>.generate(_messages.length, (_) => GlobalKey()),
        );
    });
    if (closeDrawer && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    _scrollToBottom();
  }

  _ChatMessage _fromRecord(ChatMessageRecord record) {
    return _ChatMessage(
      role: record.role == 'user' ? ChatRole.user : ChatRole.assistant,
      text: record.text,
    );
  }

  Future<void> _ensureModelInitialized() async {
    if (_inference.isReady || !widget.modelReady) {
      return;
    }
    final String? modelPath = widget.modelFilePath;
    if (modelPath == null || modelPath.isEmpty) {
      throw StateError(
        'Model file path missing. Reinstall model from download page.',
      );
    }
    setState(() {
      _isPreparingModel = true;
    });
    try {
      await _inference.ensureInitialized(modelPath: modelPath);
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingModel = false;
        });
      }
    }
  }

  Future<void> _sendMessage() async {
    final String input = _controller.text.trim();
    final String? sessionId = _activeSessionId;
    if (input.isEmpty || sessionId == null || _isTyping || _isPreparingModel) {
      return;
    }

    final DateTime now = DateTime.now();
    setState(() {
      _messages = <_ChatMessage>[
        ..._messages,
        _ChatMessage(role: ChatRole.user, text: input),
      ];
      _messageKeys.add(GlobalKey());
      _isTyping = true;
      _controller.clear();
    });
    _scrollToBottom();

    if (!_activeSessionPersisted) {
      final String title = _headlineFrom(input);
      await _storage.createSession(
        id: sessionId,
        title: title,
        createdAtIso: now.toIso8601String(),
      );
      if (_messages.isNotEmpty &&
          _messages.first.role == ChatRole.assistant &&
          _messages.first.text == _initialAssistantGreeting) {
        await _storage.addMessage(
          sessionId: sessionId,
          role: 'assistant',
          text: _initialAssistantGreeting,
          createdAtIso: now.toIso8601String(),
        );
      }
      _activeSessionPersisted = true;
      await _refreshSessions();
    }

    await _storage.addMessage(
      sessionId: sessionId,
      role: 'user',
      text: input,
      createdAtIso: now.toIso8601String(),
    );

    ChatSessionRecord? session;
    for (final ChatSessionRecord s in _sessions) {
      if (s.id == sessionId) {
        session = s;
        break;
      }
    }
    if (session != null && session.title == 'New Chat') {
      await _storage.renameSession(
        id: sessionId,
        title: _headlineFrom(input),
        updatedAtIso: now.toIso8601String(),
      );
      await _refreshSessions();
    }

    try {
      if (!widget.modelReady) {
        throw StateError(
          'Model is not installed yet. Please install model first from previous screen.',
        );
      }
      await _ensureModelInitialized();
      final String response = await _inference.complete(
        history: _messages
            .map((m) => ChatTurn(role: m.role, text: m.text))
            .toList(growable: false),
      );
      final DateTime replyAt = DateTime.now();
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = <_ChatMessage>[
          ..._messages,
          _ChatMessage(role: ChatRole.assistant, text: response),
        ];
        _messageKeys.add(GlobalKey());
        _isTyping = false;
      });
      _scrollToBottom();
      await _storage.addMessage(
        sessionId: sessionId,
        role: 'assistant',
        text: response,
        createdAtIso: replyAt.toIso8601String(),
      );
      await _refreshSessions();
    } catch (error) {
      final String message = _friendlyInferenceError(error);
      final DateTime replyAt = DateTime.now();
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = <_ChatMessage>[
          ..._messages,
          _ChatMessage(
            role: ChatRole.assistant,
            text: message,
          ),
        ];
        _messageKeys.add(GlobalKey());
        _isTyping = false;
      });
      _scrollToBottom();
      await _storage.addMessage(
        sessionId: sessionId,
        role: 'assistant',
        text: message,
        createdAtIso: replyAt.toIso8601String(),
      );
      await _refreshSessions();
    }
  }

  String _headlineFrom(String text) {
    final String compact = text.replaceAll('\n', ' ').trim();
    if (compact.isEmpty) {
      return 'New Chat';
    }
    if (compact.length <= 40) {
      return compact;
    }
    return '${compact.substring(0, 40)}...';
  }

  String _friendlyInferenceError(Object error) {
    final String raw = error.toString().replaceFirst('StateError: ', '');
    if (raw.contains('Model context is not initialized')) {
      return 'Model is not ready yet. Please reopen chat and try again.';
    }
    if (raw.contains('Model is busy')) {
      return 'Model is generating another reply. Please wait and send again.';
    }
    return 'Sorry, I could not generate a clean offline reply. Please try again.';
  }

  Future<void> _showModelBadgeInfo() async {
    await _refreshModelUpdateStatus();
    if (!mounted) {
      return;
    }
    final String title = _hasModelUpdateLive ? 'Update Available' : 'Model Active';
    final String details;
    if (_hasModelUpdateLive && _latestManifest != null) {
      details =
          'Installed: ${widget.modelLabel}\n'
          'Latest: ${_latestManifest!.modelName}\n'
          'Version: ${_latestManifest!.version} (${_latestManifest!.versionCode})\n\n'
          'Open Download/Update Page to install this update.';
    } else if (_hasModelUpdateLive) {
      details =
          'A new model update is available.\n'
          'Open Download/Update Page to see and install it.';
    } else {
      details = 'Current model is active and up to date.';
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(details),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openSettings() async {
    Navigator.of(context).pop();
    final _SettingsAction? action = await Navigator.of(context)
        .push<_SettingsAction>(
          MaterialPageRoute<_SettingsAction>(
            builder: (_) => _ChatSettingsPage(
              modelReady: widget.modelReady,
              modelLabel: widget.modelLabel,
              hasModelUpdate: _hasModelUpdateLive,
              appVersion: _appVersion,
            ),
          ),
        );
    if (!mounted) {
      return;
    }
    if (action == _SettingsAction.openModelHub) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PocketBrain'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _hasModelUpdateLive
                      ? Colors.red.withValues(alpha: _blinkOn ? 0.20 : 0.08)
                      : widget.modelReady
                      ? Colors.green.withValues(alpha: 0.14)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _showModelBadgeInfo,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      _hasModelUpdateLive
                          ? 'update'
                          : widget.modelReady
                          ? 'active'
                          : 'Model Not Installed',
                      style: TextStyle(
                        color: _hasModelUpdateLive
                            ? const Color(0xFFB00020)
                            : widget.modelReady
                            ? const Color(0xFF146C2E)
                            : const Color(0xFF9A5800),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                color: const Color(0xFFF2F6FD),
                child: const Text(
                  'Menu',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                subtitle: const Text('Model update and app version'),
                onTap: _openSettings,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: const Text('New Chat Session'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _createAndSwitchToNewSession();
                },
              ),
              const Divider(height: 1),
              const ListTile(
                dense: true,
                title: Text(
                  'Session History',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: _sessions.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.history_toggle_off_rounded),
                        title: Text('No sessions yet'),
                        dense: true,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: _sessions.length,
                        itemBuilder: (BuildContext context, int index) {
                          final ChatSessionRecord session = _sessions[index];
                          final bool selected = session.id == _activeSessionId;
                          return ListTile(
                            selected: selected,
                            leading: const Icon(
                              Icons.chat_bubble_outline_rounded,
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _formatSessionTime(session.updatedAtIso),
                            ),
                            onTap: () => _switchSession(session.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFFF6F8FC), Color(0xFFEDF2FA)],
          ),
        ),
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (_isTyping && index == _messages.length) {
                    return const _TypingBubble();
                  }
                  final _ChatMessage message = _messages[index];
                  return _ChatBubble(
                    key: _messageKeys[index],
                    message: message,
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5EAF2))),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: widget.modelReady
                              ? _isPreparingModel
                                    ? 'Preparing model...'
                                    : 'Message PocketBrain...'
                              : 'Install model first to start local chat...',
                          filled: true,
                          fillColor: const Color(0xFFF5F7FB),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _sendMessage,
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        minimumSize: const Size(46, 46),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSessionTime(String iso) {
    final DateTime? dt = DateTime.tryParse(iso);
    if (dt == null) {
      return '';
    }
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

enum _SettingsAction { openModelHub }

class _ChatSettingsPage extends StatelessWidget {
  const _ChatSettingsPage({
    required this.modelReady,
    required this.modelLabel,
    required this.hasModelUpdate,
    required this.appVersion,
  });

  final bool modelReady;
  final String modelLabel;
  final bool hasModelUpdate;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Model Settings',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(modelReady ? 'Installed: $modelLabel' : 'Not installed'),
                  const SizedBox(height: 8),
                  Text(
                    hasModelUpdate
                        ? 'Update available for model.'
                        : 'No model update info right now.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(_SettingsAction.openModelHub);
                    },
                    icon: const Icon(Icons.system_update_alt_rounded),
                    label: const Text('Open Download/Update Page'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'App Version',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('Current: $appVersion'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Current app version is $appVersion'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Check App Version'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Developer',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('About the developer and contact details.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DeveloperInfoScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_outline_rounded),
                    label: const Text('About Developer'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessage {
  const _ChatMessage({required this.role, required this.text});

  final ChatRole role;
  final String text;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({super.key, required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF2C5D99) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: const Color(0xFFE7EDF6)),
          boxShadow: isUser
              ? null
              : const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x16000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : const Color(0xFF22252B),
            height: 1.35,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7EDF6)),
        ),
        child: const SizedBox(
          width: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[_Dot(), _Dot(), _Dot()],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Color(0xFF9CA8BB),
        shape: BoxShape.circle,
      ),
    );
  }
}
