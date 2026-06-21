import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../models/models.dart';
import '../config/server_config.dart';

/// Generates a simple unique ID (avoids adding uuid package dependency)
String _generateMsgId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  final hash = now.hashCode.toRadixString(36);
  return 'msg_${hash}_${now % 100000}';
}

class ChatProvider extends ChangeNotifier {
  socket_io.Socket? _socket;
  List<ChatMessage> _messages = [];
  bool _isConnected = false;
  String? _currentUserEmail;
  String? _currentRoomId;

  List<ChatMessage> get messages => _messages;
  bool get isConnected => _isConnected;

  void init(String userEmail) {
    if (_socket != null && _currentUserEmail == userEmail) return;
    
    _currentUserEmail = userEmail;
    
    _socket?.dispose();
    _socket = socket_io.io(serverUrl, 
      socket_io.OptionBuilder()
        .setTransports(['websocket'])
        .enableAutoConnect()
        .build()
    );

    _socket!.onConnect((_) {
      _isConnected = true;
      if (_currentRoomId != null) {
        _socket!.emit('join', {'room': _currentRoomId});
      }
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      notifyListeners();
    });

    _socket!.on('message', (data) {
      final newMessage = ChatMessage.fromJson(data, _currentUserEmail ?? '');
      
      // Deduplicate by msg_id (handles optimistic updates + server echoes)
      if (newMessage.msgId != null) {
        final existingIdx = _messages.indexWhere((m) => m.msgId == newMessage.msgId);
        if (existingIdx != -1) {
          // Already have this message (from optimistic update), skip
          return;
        }
      } else {
        // Fallback: avoid exact duplicates from same sender with same text (within 5 seconds)
        bool isDuplicate = _messages.any((m) =>
          m.sender == newMessage.sender &&
          m.text == newMessage.text &&
          _isRecentTimestamp(m.createdAt, newMessage.createdAt)
        );
        if (isDuplicate) return;
      }
      
      _messages.add(newMessage);
      notifyListeners();
    });

    _socket!.on('history', (data) {
      _messages = (data as List).map((m) => ChatMessage.fromJson(m, _currentUserEmail ?? '')).toList();
      notifyListeners();
    });
  }

  /// Check if two timestamps are within 5 seconds of each other
  bool _isRecentTimestamp(String ts1, String ts2) {
    try {
      final d1 = DateTime.parse(ts1);
      final d2 = DateTime.parse(ts2);
      return d1.difference(d2).abs() < const Duration(seconds: 5);
    } catch (_) {
      return true; // If we can't parse, assume duplicate to be safe
    }
  }

  void joinRoom(String roomId) {
    if (_currentRoomId == roomId) return;
    _currentRoomId = roomId;
    _messages.clear();
    _socket?.emit('join', {'room': roomId});
    notifyListeners();
  }

  void sendMessage(String roomId, String sender, String text) {
    final msgId = _generateMsgId();

    // Optimistic Update with msg_id for deduplication
    final tempMsg = ChatMessage(
      sender: sender,
      text: text,
      createdAt: DateTime.now().toIso8601String(),
      isMe: true,
      msgId: msgId,
    );
    _messages.add(tempMsg);
    notifyListeners();

    _socket?.emit('message', {
      'room': roomId,
      'sender': sender,
      'text': text,
      'msg_id': msgId,
    });
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}
