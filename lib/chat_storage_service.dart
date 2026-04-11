import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ChatSessionRecord {
  const ChatSessionRecord({
    required this.id,
    required this.title,
    required this.createdAtIso,
    required this.updatedAtIso,
  });

  final String id;
  final String title;
  final String createdAtIso;
  final String updatedAtIso;
}

class ChatMessageRecord {
  const ChatMessageRecord({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.text,
    required this.createdAtIso,
  });

  final int id;
  final String sessionId;
  final String role;
  final String text;
  final String createdAtIso;
}

class ChatStorageService {
  ChatStorageService._();

  static final ChatStorageService instance = ChatStorageService._();

  Database? _db;

  Future<Database> _database() async {
    if (_db != null) {
      return _db!;
    }
    final supportDir = await getApplicationSupportDirectory();
    final dbPath = p.join(supportDir.path, 'chat_history.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE chat_sessions (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_chat_messages_session_created ON chat_messages(session_id, created_at)',
        );
      },
    );
    return _db!;
  }

  Future<void> createSession({
    required String id,
    required String title,
    required String createdAtIso,
  }) async {
    final db = await _database();
    await db.insert('chat_sessions', <String, Object?>{
      'id': id,
      'title': title,
      'created_at': createdAtIso,
      'updated_at': createdAtIso,
    });
  }

  Future<void> renameSession({
    required String id,
    required String title,
    required String updatedAtIso,
  }) async {
    final db = await _database();
    await db.update(
      'chat_sessions',
      <String, Object?>{'title': title, 'updated_at': updatedAtIso},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> touchSession({
    required String id,
    required String updatedAtIso,
  }) async {
    final db = await _database();
    await db.update(
      'chat_sessions',
      <String, Object?>{'updated_at': updatedAtIso},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> addMessage({
    required String sessionId,
    required String role,
    required String text,
    required String createdAtIso,
  }) async {
    final db = await _database();
    await db.insert('chat_messages', <String, Object?>{
      'session_id': sessionId,
      'role': role,
      'text': text,
      'created_at': createdAtIso,
    });
    await touchSession(id: sessionId, updatedAtIso: createdAtIso);
  }

  Future<List<ChatSessionRecord>> listSessions() async {
    final db = await _database();
    final rows = await db.query('chat_sessions', orderBy: 'updated_at DESC');
    return rows
        .map(
          (Map<String, Object?> row) => ChatSessionRecord(
            id: (row['id'] ?? '').toString(),
            title: (row['title'] ?? '').toString(),
            createdAtIso: (row['created_at'] ?? '').toString(),
            updatedAtIso: (row['updated_at'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<ChatMessageRecord>> listMessagesForSession(
    String sessionId,
  ) async {
    final db = await _database();
    final rows = await db.query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (Map<String, Object?> row) => ChatMessageRecord(
            id: (row['id'] as int?) ?? 0,
            sessionId: (row['session_id'] ?? '').toString(),
            role: (row['role'] ?? '').toString(),
            text: (row['text'] ?? '').toString(),
            createdAtIso: (row['created_at'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }
}
