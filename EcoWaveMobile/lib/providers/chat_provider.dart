import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../models/models.dart';
import '../config/server_config.dart';

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
      
      // Better duplicate check using both text and timestamp
      bool isDuplicate = _messages.any((m) => 
        m.sender == newMessage.sender && 
        m.text == newMessage.text && 
        m.isMe
      );
      
      if (!isDuplicate) {
        _messages.add(newMessage);
        notifyListeners();
      }
    });

    _socket!.on('history', (data) {
      _messages = (data as List).map((m) => ChatMessage.fromJson(m, _currentUserEmail ?? '')).toList();
      notifyListeners();
    });
  }

  void joinRoom(String roomId) {
    if (_currentRoomId == roomId) return;
    _currentRoomId = roomId;
    _messages.clear();
    _socket?.emit('join', {'room': roomId});
    notifyListeners();
  }

  void sendMessage(String roomId, String sender, String text) {
    // Optimistic Update
    final tempMsg = ChatMessage(
      sender: sender,
      text: text,
      createdAt: DateTime.now().toIso8601String(),
      isMe: true,
    );
    _messages.add(tempMsg);
    notifyListeners();

    _socket?.emit('message', {
      'room': roomId,
      'sender': sender,
      'text': text,
    });
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}
