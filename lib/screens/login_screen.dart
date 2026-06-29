import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/watermark.dart';
import 'admin/admin_dashboard.dart';
import 'customer/customer_portal_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _phoneLoginController = TextEditingController();
  final _passwordController = TextEditingController();

  // For Registration
  bool _isRegistering = false;
  bool _isPhoneLogin = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _phoneLoginController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      if (_isRegistering) {
        // Registering a Customer account
        await authService.register(
          email: _emailController.text,
          password: _passwordController.text,
          name: _nameController.text,
          phoneNumber: _phoneController.text,
          role: 'customer',
        );
      } else {
        // Logging in
        if (_isPhoneLogin) {
          await authService.signInWithPhone(
            _phoneLoginController.text,
            _passwordController.text,
          );
        } else {
          await authService.signIn(
            _emailController.text,
            _passwordController.text,
          );
        }
      }

      // Check role and navigate
      if (mounted) {
        final role = authService.currentUserModel?.role;
        if (role == 'owner' || role == 'staff' || role == 'developer') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminDashboard()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CustomerPortalScreen()),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e
            .toString()
            .replaceAll(RegExp(r'\[.*?\]'), ''); // Clean Firebase error codes
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      final credential = await authService.signInWithGoogle();
      if (credential != null && mounted) {
        final role = authService.currentUserModel?.role;
        if (role == 'owner' || role == 'staff' || role == 'developer') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminDashboard()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CustomerPortalScreen()),
          );
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll(RegExp(r'\[.*?\]'), '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWeb = size.width > 600;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.whiteBlueGradient,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              width: isWeb ? 450 : double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: AppTheme.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.softShadow,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo Image
                    Image.asset(
                      'assets/logo_kickdirty.jpeg',
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: const Icon(
                            Icons.local_laundry_service,
                            size: 60,
                            color: AppTheme.primaryBlue,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isRegistering
                          ? "Buat Akun Pelanggan"
                          : "Masuk ke KickDirty",
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: AppTheme.darkBlueText,
                                fontWeight: FontWeight.bold,
                                                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegistering
                          ? "Daftar untuk memantau cucian sepatu Anda secara real-time"
                          : _isPhoneLogin
                              ? "Silakan masuk menggunakan nomor WhatsApp terdaftar"
                              : "Silakan masuk menggunakan email terdaftar",
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    if (_errorMessage.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.redAccent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Switch between Email and Phone Login (only when not registering)
                    if (!_isRegistering) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text("Email")),
                                selected: !_isPhoneLogin,
                                onSelected: (val) {
                                  setState(() {
                                    _isPhoneLogin = false;
                                    _errorMessage = '';
                                  });
                                },
                                selectedColor: AppTheme.primaryBlue,
                                labelStyle: TextStyle(
                                  color: !_isPhoneLogin ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                pressElevation: 0,
                                shadowColor: Colors.transparent,
                                selectedShadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            Expanded(
                              child: ChoiceChip(
                                label: const Center(child: Text("Nomor WA")),
                                selected: _isPhoneLogin,
                                onSelected: (val) {
                                  setState(() {
                                    _isPhoneLogin = true;
                                    _errorMessage = '';
                                  });
                                },
                                selectedColor: AppTheme.primaryBlue,
                                labelStyle: TextStyle(
                                  color: _isPhoneLogin ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                pressElevation: 0,
                                shadowColor: Colors.transparent,
                                selectedShadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (_isRegistering) ...[
                      // Name field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: 'Nama Lengkap',
                          prefixIcon: Icon(Icons.person_outline,
                              color: AppTheme.textGray),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Nama tidak boleh kosong'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Phone field (Registration)
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'Nomor WhatsApp (Contoh: 08123456789 atau 628123456789)',
                          prefixIcon: Icon(Icons.phone_outlined,
                              color: AppTheme.textGray),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Nomor WhatsApp tidak boleh kosong';
                          }
                          if (!value.startsWith('0') && !value.startsWith('62')) {
                            return 'Gunakan format 08... atau 628...';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Email / Phone field for Login
                    if (!_isRegistering && _isPhoneLogin) ...[
                      // Phone input
                      TextFormField(
                        controller: _phoneLoginController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: 'Nomor WhatsApp (Contoh: 08132... atau 628132...)',
                          prefixIcon: Icon(Icons.phone_outlined,
                              color: AppTheme.textGray),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Nomor WhatsApp tidak boleh kosong';
                          }
                          if (!value.startsWith('0') && !value.startsWith('62')) {
                            return 'Gunakan format 08... atau 628...';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined,
                              color: AppTheme.textGray),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Email tidak boleh kosong';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(value)) {
                            return 'Format email tidak valid';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Password Field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline,
                            color: AppTheme.textGray),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppTheme.textGray,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Password tidak boleh kosong';
                        }
                        if (value.length < 6) {
                          return 'Password minimal 6 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                _isRegistering ? 'Daftar Sekarang' : 'Masuk'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Google Sign-In Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                        icon: Image.network(
                          'https://upload.wikimedia.org/wikipedia/commons/c/c1/Google_%22G%22_logo.svg',
                          height: 18,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.g_mobiledata, size: 24);
                          },
                        ),
                        label: const Text(
                          'Masuk dengan Google',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.darkBlueText,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Toggle Register/Login Option
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isRegistering = !_isRegistering;
                          _errorMessage = '';
                        });
                      },
                      child: Text(
                        _isRegistering
                            ? 'Sudah punya akun? Masuk di sini'
                            : 'Belum punya akun? Daftar sebagai Pelanggan',
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),

                    const Divider(height: 32, color: AppTheme.lightGray),

                    // Watermark
                    const Watermark(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
