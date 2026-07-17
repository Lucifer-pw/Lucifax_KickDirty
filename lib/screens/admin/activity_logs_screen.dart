import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../widgets/watermark.dart';

class ActivityLogsScreen extends StatefulWidget {
  ActivityLogsScreen({Key? key}) : super(key: key);

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Get icon based on action text
  IconData _getActionIcon(String action) {
    final lowerAction = action.toLowerCase();
    if (lowerAction.contains('pesanan') || lowerAction.contains('order')) {
      return Icons.shopping_bag_outlined;
    } else if (lowerAction.contains('pengeluaran') || lowerAction.contains('expense')) {
      return Icons.payments_outlined;
    } else if (lowerAction.contains('kategori') || lowerAction.contains('category')) {
      return Icons.category_outlined;
    } else if (lowerAction.contains('voucher') || lowerAction.contains('diskon')) {
      return Icons.confirmation_number_outlined;
    } else if (lowerAction.contains('login') || lowerAction.contains('masuk')) {
      return Icons.login_outlined;
    }
    return Icons.settings_accessibility_outlined;
  }

  // Get color based on action type
  Color _getActionColor(String action) {
    final lowerAction = action.toLowerCase();
    if (lowerAction.contains('pesanan') || lowerAction.contains('order')) {
      return AppTheme.primaryBlue;
    } else if (lowerAction.contains('pengeluaran') || lowerAction.contains('expense')) {
      return Colors.redAccent;
    } else if (lowerAction.contains('kategori') || lowerAction.contains('category')) {
      return Colors.teal;
    } else if (lowerAction.contains('voucher') || lowerAction.contains('diskon')) {
      return Colors.amber[700]!;
    }
    return AppTheme.textGray;
  }

  // Get badge color based on role
  Color _getRoleBadgeColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return Colors.purple;
      case 'developer':
        return Colors.blueGrey;
      default:
        return AppTheme.primaryBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUserModel;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('app_config').doc('version_info').snapshots(),
      builder: (context, configSnapshot) {
        if (configSnapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final bool enableOwnerLogs = configSnapshot.hasData &&
            configSnapshot.data!.exists &&
            (configSnapshot.data!.data() as Map<String, dynamic>?)?['enableOwnerLogs'] == true;

        // Strict access control: developer always has access, owner only if enableOwnerLogs is true
        final bool hasAccess = user != null &&
            (user.role == 'developer' || (user.role == 'owner' && enableOwnerLogs));

        if (!hasAccess) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, color: Colors.redAccent, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Akses Ditolak',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Hanya Owner dan Developer yang dapat mengakses log aktivitas.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textGray),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppTheme.lightBlueBackground,
          appBar: AppBar(
            title: Text('Log Aktivitas Karyawan'),
            centerTitle: true,
          ),
          body: Stack(
            children: [
          Watermark(),
          Column(
            children: [
              // Search input box
              Padding(
                padding: EdgeInsets.all(16.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Cari berdasarkan nama staff atau aksi...',
                      prefixIcon: Icon(Icons.search, color: AppTheme.textGray),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AppTheme.textGray),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim().toLowerCase();
                      });
                    },
                  ),
                ),
              ),

              // Logs StreamBuilder
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('activity_logs')
                      .orderBy('timestamp', descending: true)
                      .limit(200) // Show up to 200 logs
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.list_alt_outlined, color: AppTheme.textGray, size: 64),
                            SizedBox(height: 16),
                            Text(
                              'Belum ada aktivitas yang dicatat.',
                              style: TextStyle(color: AppTheme.textGray),
                            ),
                          ],
                        ),
                      );
                    }

                    // Filter logs locally based on search query
                    final docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final userName = (data['userName'] ?? '').toString().toLowerCase();
                      final action = (data['action'] ?? '').toString().toLowerCase();
                      return userName.contains(_searchQuery) || action.contains(_searchQuery);
                    }).toList();

                    if (docs.isEmpty) {
                      return Center(
                        child: Text(
                          'Aktivitas tidak ditemukan.',
                          style: TextStyle(color: AppTheme.textGray),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;
                        final String action = data['action'] ?? '';
                        final String details = data['details'] ?? '';
                        final String userName = data['userName'] ?? 'Unknown';
                        final String role = data['userRole'] ?? 'staff';
                        final timestampVal = data['timestamp'];
                        
                        DateTime time = DateTime.now();
                        if (timestampVal is Timestamp) {
                          time = timestampVal.toDate();
                        }

                        final String formattedTime = DateFormat('dd MMM yyyy, HH:mm').format(time);

                        return Container(
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppTheme.cardShadow,
                            border: Border.all(color: AppTheme.lightGray, width: 0.5),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Action circular icon
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: _getActionColor(action).withOpacity(0.1),
                                child: Icon(
                                  _getActionIcon(action),
                                  color: _getActionColor(action),
                                  size: 22,
                                ),
                              ),
                              SizedBox(width: 14),
                              
                              // Log details text
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // User identity & Role badge
                                    Row(
                                      children: [
                                        Text(
                                          userName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppTheme.darkBlueText,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _getRoleBadgeColor(role).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            role.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: _getRoleBadgeColor(role),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 6),
                                    
                                    // Action Text
                                    Text(
                                      action,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.darkBlueText,
                                      ),
                                    ),
                                    
                                    // Details (if not empty)
                                    if (details.isNotEmpty) ...[
                                      SizedBox(height: 6),
                                      Container(
                                        width: double.infinity,
                                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: AppTheme.lightBlueBackground,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          details,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textGray,
                                          ),
                                        ),
                                      ),
                                    ],
                                    SizedBox(height: 8),
                                    
                                    // Time
                                    Text(
                                      formattedTime,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textGray,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  },
);
  }
}
