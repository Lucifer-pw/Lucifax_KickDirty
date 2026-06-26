import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/expense_model.dart';
import '../../models/order_model.dart';
import '../../services/database_service.dart';
import '../../theme.dart';

class FinancialReportScreen extends StatefulWidget {
  const FinancialReportScreen({Key? key}) : super(key: key);

  @override
  State<FinancialReportScreen> createState() => _FinancialReportScreenState();
}

class _FinancialReportScreenState extends State<FinancialReportScreen> {
  String _selectedTimeframe = 'monthly'; // 'daily' | 'weekly' | 'monthly' | 'yearly'

  void _showAddExpenseDialog() {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCategory = 'Sabun & Bahan Kimia';
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Catat Pengeluaran Baru'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Nama Pengeluaran / Keterangan',
                          hintText: 'Contoh: Beli Parfum Sepatu 2L',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Keterangan wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        decoration: const InputDecoration(labelText: 'Kategori'),
                        items: const [
                          DropdownMenuItem(value: 'Sabun & Bahan Kimia', child: Text('Sabun & Bahan Kimia')),
                          DropdownMenuItem(value: 'Gaji Karyawan', child: Text('Gaji Karyawan')),
                          DropdownMenuItem(value: 'Transportasi & Kurir', child: Text('Transportasi & Kurir')),
                          DropdownMenuItem(value: 'Sewa & Utilitas', child: Text('Sewa & Utilitas (Listrik/Air)')),
                          DropdownMenuItem(value: 'Lain-lain', child: Text('Lain-lain')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() {
                              selectedCategory = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Jumlah Pengeluaran (Rp)',
                          hintText: 'Contoh: 150000',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Jumlah wajib diisi';
                          if (double.tryParse(v) == null) return 'Harus berupa angka';
                          if (double.parse(v) <= 0) return 'Harus lebih dari 0';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal', style: TextStyle(color: AppTheme.textGray)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setStateDialog(() {
                            isSubmitting = true;
                          });

                          try {
                            final expense = ExpenseModel(
                              id: '', // Will be set by Firestore
                              title: titleController.text.trim(),
                              amount: double.parse(amountController.text.trim()),
                              category: selectedCategory,
                              createdAt: DateTime.now(),
                            );
                            await dbService.addExpense(expense);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pengeluaran berhasil dicatat!')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gagal mencatat pengeluaran: $e')),
                              );
                            }
                          } finally {
                            setStateDialog(() {
                              isSubmitting = false;
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteExpense(String id) async {
    final dbService = Provider.of<DatabaseService>(context, listen: false);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Catatan'),
        content: const Text('Apakah Anda yakin ingin menghapus catatan pengeluaran ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal', style: TextStyle(color: AppTheme.textGray))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await dbService.deleteExpense(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengeluaran berhasil dihapus')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menghapus: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Keuangan'),
        elevation: 0,
      ),
      body: StreamBuilder<List<OrderModel>>(
        stream: dbService.getOrders(),
        builder: (context, ordersSnap) {
          if (ordersSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = ordersSnap.data ?? [];
          final salesRecap = dbService.calculateSalesRecap(orders);

          return StreamBuilder<List<ExpenseModel>>(
            stream: dbService.getExpenses(),
            builder: (context, expensesSnap) {
              if (expensesSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final expenses = expensesSnap.data ?? [];
              final expensesRecap = dbService.calculateExpensesRecap(expenses);

              // Extract values based on selected timeframe
              double revenue = salesRecap[_selectedTimeframe] ?? 0.0;
              double totalExpense = expensesRecap[_selectedTimeframe] ?? 0.0;
              double netProfit = revenue - totalExpense;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timeframe Filter Buttons
                    _buildTimeframeFilter(),
                    const SizedBox(height: 20),

                    // Financial Cards (Revenue, Expenses, Net Profit)
                    _buildFinancialSummaryCards(revenue, totalExpense, netProfit),
                    const SizedBox(height: 24),

                    // Visual Progress Chart
                    _buildVisualRatioBar(revenue, totalExpense),
                    const SizedBox(height: 24),

                    // Category Breakdown section
                    _buildCategoryBreakdown(expenses),
                    const SizedBox(height: 24),

                    // List of operating expenses
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Catatan Pengeluaran Operasional',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16),
                        ),
                        TextButton.icon(
                          onPressed: _showAddExpenseDialog,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Tambah', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildExpensesList(expenses),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExpenseDialog,
        backgroundColor: AppTheme.primaryBlue,
        child: const Icon(Icons.add_card, color: Colors.white),
      ),
    );
  }

  Widget _buildTimeframeFilter() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.lightGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildFilterButton('daily', 'Hari Ini'),
          _buildFilterButton('weekly', 'Minggu Ini'),
          _buildFilterButton('monthly', 'Bulan Ini'),
          _buildFilterButton('yearly', 'Tahun Ini'),
        ],
      ),
    );
  }

  Widget _buildFilterButton(String key, String label) {
    bool isSelected = _selectedTimeframe == key;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTimeframe = key;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? AppTheme.primaryBlue : AppTheme.textGray,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialSummaryCards(double revenue, double expense, double net) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Pendapatan Kotor',
                revenue,
                Icons.trending_up,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Total Pengeluaran',
                expense,
                Icons.trending_down,
                Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildNetProfitCard(net),
      ],
    );
  }

  Widget _buildSummaryCard(String title, double amount, IconData icon, Color color) {
    final String formattedAmount = amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 11, color: AppTheme.textGray)),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rp $formattedAmount',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppTheme.darkBlueText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetProfitCard(double net) {
    final bool isPositive = net >= 0;
    final String formattedAmount = net.abs().toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPositive ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPositive ? Colors.green.shade100 : Colors.red.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
            child: Icon(
              isPositive ? Icons.account_balance_wallet_outlined : Icons.report_problem_outlined,
              color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Keuntungan Bersih (Net Profit)',
                  style: TextStyle(fontSize: 11, color: AppTheme.textGray, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${isPositive ? "" : "- "}Rp $formattedAmount',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualRatioBar(double revenue, double expense) {
    double total = revenue > 0 ? revenue : (expense > 0 ? expense : 1.0);
    double expenseRatio = expense / total;
    if (expenseRatio > 1.0) expenseRatio = 1.0;
    double profitRatio = 1.0 - expenseRatio;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Visualisasi Rasio Laba vs Pengeluaran',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: [
                  if (profitRatio > 0 && revenue > 0)
                    Expanded(
                      flex: (profitRatio * 100).round(),
                      child: Tooltip(
                        message: 'Laba Bersih',
                        child: Container(color: Colors.green),
                      ),
                    ),
                  if (expenseRatio > 0)
                    Expanded(
                      flex: (expenseRatio * 100).round(),
                      child: Tooltip(
                        message: 'Pengeluaran',
                        child: Container(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 8, height: 8, color: Colors.green),
                  const SizedBox(width: 4),
                  Text('Laba Bersih (${(profitRatio * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 10, color: AppTheme.textGray)),
                ],
              ),
              Row(
                children: [
                  Container(width: 8, height: 8, color: Colors.red),
                  const SizedBox(width: 4),
                  Text('Pengeluaran (${(expenseRatio * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 10, color: AppTheme.textGray)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(List<ExpenseModel> expenses) {
    // Group expenses by category for current timeframe
    Map<String, double> categories = {
      'Sabun & Bahan Kimia': 0.0,
      'Gaji Karyawan': 0.0,
      'Transportasi & Kurir': 0.0,
      'Sewa & Utilitas': 0.0,
      'Lain-lain': 0.0,
    };

    double total = 0;
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    int weekdayDiff = now.weekday - 1;
    DateTime startOfWeek = today.subtract(Duration(days: weekdayDiff));
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    DateTime startOfYear = DateTime(now.year, 1, 1);

    for (var exp in expenses) {
      bool isMatch = false;
      if (_selectedTimeframe == 'daily' && (exp.createdAt.isAfter(today) || exp.createdAt.isAtSameMomentAs(today))) {
        isMatch = true;
      } else if (_selectedTimeframe == 'weekly' && (exp.createdAt.isAfter(startOfWeek) || exp.createdAt.isAtSameMomentAs(startOfWeek))) {
        isMatch = true;
      } else if (_selectedTimeframe == 'monthly' && (exp.createdAt.isAfter(startOfMonth) || exp.createdAt.isAtSameMomentAs(startOfMonth))) {
        isMatch = true;
      } else if (_selectedTimeframe == 'yearly' && (exp.createdAt.isAfter(startOfYear) || exp.createdAt.isAtSameMomentAs(startOfYear))) {
        isMatch = true;
      }

      if (isMatch) {
        categories[exp.category] = (categories[exp.category] ?? 0.0) + exp.amount;
        total += exp.amount;
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.lightGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rincian Pengeluaran per Kategori',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.darkBlueText),
          ),
          const SizedBox(height: 12),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Tidak ada pengeluaran di rentang waktu ini.', style: TextStyle(fontSize: 11, color: AppTheme.textGray, fontStyle: FontStyle.italic)),
            )
          else
            ...categories.entries.map((entry) {
              if (entry.value == 0) return const SizedBox();
              double percentage = entry.value / total;
              final String amountFormatted = entry.value.toStringAsFixed(0).replaceAllMapped(
                    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                    (Match m) => '${m[1]}.',
                  );

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                        Text('Rp $amountFormatted (${(percentage * 100).toStringAsFixed(0)}%)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: percentage,
                      backgroundColor: AppTheme.lightGray,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                    ),
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildExpensesList(List<ExpenseModel> expenses) {
    if (expenses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: AppTheme.lightGray.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Belum ada catatan pengeluaran.', style: TextStyle(fontSize: 12, color: AppTheme.textGray)),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: expenses.length > 10 ? 10 : expenses.length, // Show up to 10 latest
      itemBuilder: (context, index) {
        final exp = expenses[index];
        String day = exp.createdAt.day.toString().padLeft(2, '0');
        String month = exp.createdAt.month.toString().padLeft(2, '0');
        String year = exp.createdAt.year.toString();
        String formattedDate = "$day-$month-$year";

        final String amountFormatted = exp.amount.toStringAsFixed(0).replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]}.',
            );

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: AppTheme.primaryBlue.withOpacity(0.08),
              child: const Icon(Icons.monetization_on_outlined, color: AppTheme.primaryBlue, size: 20),
            ),
            title: Text(exp.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('${exp.category} • $formattedDate', style: const TextStyle(fontSize: 11, color: AppTheme.textGray)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rp $amountFormatted',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                  onPressed: () => _deleteExpense(exp.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
