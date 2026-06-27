import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../chat_screen.dart';

class AdminChatListScreen extends StatelessWidget {
  final bool isTab;
  const AdminChatListScreen({Key? key, this.isTab = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<DatabaseService>(context);
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUserModel;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesan Masuk Pelanggan'),
        automaticallyImplyLeading: !isTab,
      ),
      body: currentUser == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<Map<String, dynamic>>>(
              stream: dbService.getChatRooms(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
                }

                final rooms = snapshot.data ?? [];

                if (rooms.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: AppTheme.textGray.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          const Text(
                            'Belum ada pesan masuk dari pelanggan.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppTheme.textGray, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    final String customerId = room['customerId'] ?? '';
                    final String customerName = room['customerName'] ?? '';
                    final String customerPhone = room['customerPhone'] ?? '';
                    final String lastMessage = room['lastMessage'] ?? '';
                    final int unreadCount = room['unreadCountAdmin'] ?? 0;

                    DateTime? lastTime;
                    if (room['lastMessageTime'] is Timestamp) {
                      lastTime = (room['lastMessageTime'] as Timestamp).toDate();
                    }

                    String timeText = '';
                    if (lastTime != null) {
                      final now = DateTime.now();
                      if (now.day == lastTime.day && now.month == lastTime.month && now.year == lastTime.year) {
                        timeText = DateFormat('HH:mm').format(lastTime);
                      } else {
                        timeText = DateFormat('dd/MM/yyyy').format(lastTime);
                      }
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                customerId: customerId,
                                customerName: customerName,
                                customerPhone: customerPhone,
                                senderId: currentUser.uid,
                                senderName: currentUser.name,
                                isAdmin: true,
                              ),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                          child: const Icon(Icons.person, color: AppTheme.primaryBlue),
                        ),
                        title: Text(
                          customerName,
                          style: TextStyle(
                            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          lastMessage.isNotEmpty ? lastMessage : 'No messages',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: unreadCount > 0 ? AppTheme.darkBlueText : AppTheme.textGray,
                            fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (timeText.isNotEmpty)
                              Text(
                                timeText,
                                style: const TextStyle(fontSize: 10, color: AppTheme.textGray),
                              ),
                            if (unreadCount > 0) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '$unreadCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
