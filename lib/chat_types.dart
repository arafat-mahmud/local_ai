enum ChatRole { user, assistant }

class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  final ChatRole role;
  final String text;
}
