import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';
import '../theme.dart';
import '../utils/error_helper.dart';

class ChatScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String senderId;
  final String senderName;
  final bool isAdmin;

  ChatScreen({
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
  List<String> _quickReplies = [];
  bool _loadingQuickReplies = true;

  @override
  void initState() {
    super.initState();
    _clearUnread();
    _loadQuickReplies();
  }

  void _loadQuickReplies() {
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.senderId)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _loadingQuickReplies = false;
          if (snapshot.exists && snapshot.data()!.containsKey('quickReplies')) {
            _quickReplies = List<String>.from(snapshot.data()!['quickReplies']);
          } else {
            _quickReplies = widget.isAdmin
                ? [
                    'Halo, sepatu Anda sedang kami proses.',
                    'Layanan Anda sudah selesai dan siap diambil.',
                    'Silakan melakukan pembayaran.',
                    'Terima kasih telah mencuci di KickDirty!',
                  ]
                : [
                    'Halo, apakah sepatu saya sudah selesai?',
                    'Berapa biaya pengiriman?',
                    'Bisa request pick-up?',
                    'Terima kasih!',
                  ];
          }
        });
      }
    });
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
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
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
              widget.customerId == 'dev_support'
                  ? (widget.isAdmin ? 'Hubungi Developer (Dukungan)' : 'Dukungan Developer (Owner & Staff)')
                  : (widget.isAdmin ? widget.customerName : 'Hubungi Owner (KickDirty)'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.customerId == 'dev_support'
                  ? (widget.isAdmin ? 'Tanya seputar kendala aplikasi' : 'Chat bantuan kendala aplikasi')
                  : (widget.isAdmin ? 'WhatsApp: ${widget.customerPhone}' : 'Tanya seputar cucian sepatu Anda'),
              style: TextStyle(fontSize: 11, color: AppTheme.textGray),
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
                  return Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text(getCleanErrorMessage(snapshot.error)));
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: AppTheme.textGray.withOpacity(0.5)),
                          SizedBox(height: 16),
                          Text(
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
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final bool isMe;
                    if (widget.customerId == 'dev_support') {
                      isMe = widget.isAdmin
                          ? (msg['isAdmin'] == true || msg['senderId'] == widget.senderId)
                          : (msg['isAdmin'] == false || msg['senderId'] == widget.senderId);
                    } else {
                      isMe = widget.isAdmin
                          ? (msg['senderId'] != widget.customerId)
                          : (msg['senderId'] == widget.senderId);
                    }
                    
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
                        margin: EdgeInsets.symmetric(vertical: 4),
                        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMe ? AppTheme.primaryBlue : Colors.grey[200],
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                            bottomLeft: isMe ? Radius.circular(16) : Radius.zero,
                            bottomRight: isMe ? Radius.zero : Radius.circular(16),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!isMe && widget.isAdmin) ...[
                              Text(
                                msg['senderName'] ?? '',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: AppTheme.darkBlueText),
                              ),
                              SizedBox(height: 2),
                            ],
                            Text(
                              msg['message'] ?? '',
                              style: TextStyle(
                                fontSize: 13,
                                color: isMe ? Colors.white : AppTheme.darkBlueText,
                              ),
                            ),
                            SizedBox(height: 4),
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
          
          // Quick replies list
          if (!_loadingQuickReplies && _quickReplies.isNotEmpty)
            Container(
              height: 48,
              color: Colors.grey[50],
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  ..._quickReplies.map((reply) => Padding(
                    padding: EdgeInsets.only(right: 8.0),
                    child: ActionChip(
                      label: Text(reply, style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey[300]!),
                      onPressed: () {
                        _messageController.text = reply;
                        _sendMessage();
                      },
                    ),
                  )),
                  IconButton(
                    icon: Icon(Icons.edit_note, size: 20, color: AppTheme.primaryBlue),
                    onPressed: _manageQuickReplies,
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    tooltip: 'Kelola Pesan Cepat',
                  ),
                ],
              ),
            ),

          // Input row
          SafeArea(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: Offset(0, -2),
                  )
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
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
                      icon: Icon(Icons.send, color: Colors.white, size: 18),
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

  void _manageQuickReplies() {
    final TextEditingController newReplyController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kelola Pesan Cepat',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                      ),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newReplyController,
                          decoration: InputDecoration(
                            hintText: 'Tambah template pesan...',
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final text = newReplyController.text.trim();
                          if (text.isNotEmpty) {
                            setState(() {
                              _quickReplies.add(text);
                            });
                            setStateSheet(() {});
                            newReplyController.clear();
                            FirebaseFirestore.instance
                                .collection('users')
                                .doc(widget.senderId)
                                .update({'quickReplies': _quickReplies});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        child: Text('Tambah', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 250),
                    child: _quickReplies.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'Belum ada pesan cepat.',
                                style: TextStyle(color: AppTheme.textGray),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _quickReplies.length,
                            itemBuilder: (context, idx) {
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  _quickReplies[idx],
                                  style: TextStyle(fontSize: 13),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () {
                                    setState(() {
                                      _quickReplies.removeAt(idx);
                                    });
                                    setStateSheet(() {});
                                    FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(widget.senderId)
                                        .update({'quickReplies': _quickReplies});
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
