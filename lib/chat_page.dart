import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.modelReady,
    required this.modelLabel,
    required this.hasModelUpdate,
  });

  final bool modelReady;
  final String modelLabel;
  final bool hasModelUpdate;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _messageKeys = <GlobalKey>[GlobalKey()];

  final List<_ChatMessage> _messages = <_ChatMessage>[
    const _ChatMessage(
      role: _ChatRole.assistant,
      text: 'Hi. I am ready. Downloaded model can answer here in offline mode.',
    ),
  ];
  final List<_HistoryEntry> _history = <_HistoryEntry>[];

  bool _isTyping = false;
  String _appVersion = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersion = '${info.version} (${info.buildNumber})';
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

  void _sendMessage() {
    final String input = _controller.text.trim();
    if (input.isEmpty) {
      return;
    }

    setState(() {
      final int userMessageIndex = _messages.length;
      _messages.add(_ChatMessage(role: _ChatRole.user, text: input));
      _messageKeys.add(GlobalKey());
      _history.insert(
        0,
        _HistoryEntry(
          label: input,
          messageIndex: userMessageIndex,
          createdAt: DateTime.now(),
        ),
      );
      _isTyping = true;
      _controller.clear();
    });
    _scrollToBottom();

    Future<void>.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          _ChatMessage(
            role: _ChatRole.assistant,
            text: widget.modelReady
                ? 'Received: "$input"\n\nThis is chat UI mode. Connect your local inference call here.'
                : 'Model is not installed yet. Please install model first from previous screen.',
          ),
        );
        _messageKeys.add(GlobalKey());
        _isTyping = false;
      });
      _scrollToBottom();
    });
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

  void _jumpToHistory(_HistoryEntry entry) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? targetContext =
          _messageKeys[entry.messageIndex].currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
      }
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
              hasModelUpdate: widget.hasModelUpdate,
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
        title: const Text('Local AI Chat'),
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
                  color: widget.modelReady
                      ? Colors.green.withValues(alpha: 0.14)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.modelReady ? widget.modelLabel : 'Model Not Installed',
                  style: TextStyle(
                    color: widget.modelReady
                        ? const Color(0xFF146C2E)
                        : const Color(0xFF9A5800),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  children: <Widget>[
                    const ListTile(
                      title: Text(
                        'History',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      dense: true,
                    ),
                    if (_history.isEmpty)
                      const ListTile(
                        leading: Icon(Icons.history_toggle_off_rounded),
                        title: Text('No chat history yet'),
                        dense: true,
                      )
                    else
                      ..._history.map((entry) {
                        return ListTile(
                          leading: const Icon(
                            Icons.chat_bubble_outline_rounded,
                          ),
                          title: Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${entry.createdAt.hour.toString().padLeft(2, '0')}:${entry.createdAt.minute.toString().padLeft(2, '0')}',
                          ),
                          onTap: () => _jumpToHistory(entry),
                        );
                      }),
                  ],
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
                              ? 'Message Local AI...'
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
        ],
      ),
    );
  }
}

enum _ChatRole { user, assistant }

class _HistoryEntry {
  const _HistoryEntry({
    required this.label,
    required this.messageIndex,
    required this.createdAt,
  });

  final String label;
  final int messageIndex;
  final DateTime createdAt;
}

class _ChatMessage {
  const _ChatMessage({required this.role, required this.text});

  final _ChatRole role;
  final String text;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({super.key, required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == _ChatRole.user;
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
