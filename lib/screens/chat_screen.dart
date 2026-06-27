import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String senderId;
  final String senderName;
  final bool isAdmin;

  const ChatScreen({
    Key? key,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.senderId,
    required this.senderName,
    required this.isAdmin,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _clearUnread();
  }

  void _clearUnread() {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    if (widget.isAdmin) {
      dbService.clearUnreadCountAdmin(widget.customerId);
    } else {
      dbService.clearUnreadCountCustomer(widget.customerId);
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    await dbService.sendChatMessage(
      customerId: widget.customerId,
      customerName: widget.customerName,
      customerPhone: widget.customerPhone,
      senderId: widget.senderId,
      senderName: widget.senderName,
      message: text,
      isAdmin: widget.isAdmin,
    );

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isAdmin ? widget.customerName : 'Hubungi Owner (KickDirty)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.isAdmin ? 'WhatsApp: ${widget.customerPhone}' : 'Tanya seputar cucian sepatu Anda',
              style: const TextStyle(fontSize: 11, color: AppTheme.textGray),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: dbService.getChatMessages(widget.customerId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: AppTheme.textGray.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum ada pesan. Mulai obrolan sekarang!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textGray, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Scroll to bottom after frame rendered
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final bool isMe = msg['senderId'] == widget.senderId;
                    
                    DateTime? date;
                    if (msg['timestamp'] is Timestamp) {
                      date = (msg['timestamp'] as Timestamp).toDate();
                    } else if (msg['timestamp'] is String) {
                      date = DateTime.tryParse(msg['timestamp'] ?? '');
                    }

                    String timeText = date != null ? DateFormat('HH:mm').format(date) : '';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe ? AppTheme.primaryBlue : Colors.grey[200],
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!isMe && widget.isAdmin) ...[
                              Text(
                                msg['senderName'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: AppTheme.darkBlueText),
                              ),
                              const SizedBox(height: 2),
                            ],
                            Text(
                              msg['message'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                color: isMe ? Colors.white : AppTheme.darkBlueText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              timeText,
                              style: TextStyle(
                                fontSize: 9,
                                color: isMe ? Colors.white70 : Colors.black45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Input row
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, -2),
                  )
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Tulis pesan...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: null,
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: AppTheme.primaryBlue,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
