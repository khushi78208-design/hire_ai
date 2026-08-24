import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  /// Which side of the product the person is here for. The server still
  /// decides what the account actually is — this only sets expectations
  /// and colours the screen.
  String _role = 'candidate';
  bool _isRegisterMode = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = _isRegisterMode
        ? await AuthService.register(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            fullName: _nameCtrl.text.trim(),
            role: _role,
          )
        : await AuthService.login(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!result.success) {
      setState(() => _errorMessage = result.error);
      return;
    }

    // Signing in as the wrong kind of account is a common mistake and a
    // confusing one — the app would simply open the other product.
    if (!_isRegisterMode && result.role != null && result.role != _role) {
      final actual = result.role == 'candidate' ? 'candidate' : 'recruiter';
      setState(() {
        _errorMessage =
            'This is a $actual account. '
            'Switch to the $actual tab to sign in.';
      });
      await AuthService.logout();
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  void _switchRole(String role) {
    if (_role == role) return;
    setState(() {
      _role = role;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isHr = _role == 'hr';
    final accent = isHr ? const Color(0xFF4F46E5) : const Color(0xFF0D9488);
    final shell = isHr ? Shell.hr : Shell.candidate;

    return Scaffold(
      backgroundColor: shell,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Space.xl),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                        ),
                        child: const Icon(
                          Icons.work_outline,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      const Text(
                        'HireAI',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.5,
                          color: Shell.onDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    isHr
                        ? 'Screen candidates with AI. Decide for yourself.'
                        : 'Find roles that actually fit you.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Shell.onDarkMuted,
                    ),
                  ),
                  const SizedBox(height: Space.xxl),

                  Container(
                    padding: const EdgeInsets.all(Space.xl),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RoleTabs(
                            role: _role,
                            accent: accent,
                            onChanged: _switchRole,
                          ),
                          const SizedBox(height: Space.xl),

                          if (_isRegisterMode) ...[
                            TextFormField(
                              controller: _nameCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (v) =>
                                  (v == null || v.trim().length < 2)
                                  ? 'Enter your name'
                                  : null,
                            ),
                            const SizedBox(height: Space.md),
                          ],

                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter your email';
                              }
                              if (!v.contains('@') || !v.contains('.')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: Space.md),

                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _isLoading ? null : _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Enter your password';
                              }
                              if (_isRegisterMode && v.length < 8) {
                                return 'At least 8 characters';
                              }
                              return null;
                            },
                          ),

                          if (_errorMessage != null) ...[
                            const SizedBox(height: Space.lg),
                            Container(
                              padding: const EdgeInsets.all(Space.md),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.control,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    size: 19,
                                    color: Color(0xFFB91C1C),
                                  ),
                                  const SizedBox(width: Space.sm),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: Space.xl),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                              ),
                              onPressed: _isLoading ? null : _submit,
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isRegisterMode
                                          ? 'Create account'
                                          : 'Sign in',
                                    ),
                            ),
                          ),

                          // A cold free-tier instance takes about a minute
                          // to wake; silence would read as a broken app.
                          if (_isLoading) ...[
                            const SizedBox(height: Space.md),
                            const Text(
                              'Waking up the server — this can take a minute '
                              'the first time.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF71717A),
                              ),
                            ),
                          ],

                          const SizedBox(height: Space.sm),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () => setState(() {
                                    _isRegisterMode = !_isRegisterMode;
                                    _errorMessage = null;
                                  }),
                            child: Text(
                              _isRegisterMode
                                  ? 'Already have an account? Sign in'
                                  : "Don't have an account? Register",
                              style: TextStyle(color: accent),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: Space.xl),
                  const Text(
                    'AI screens and explains. The recruiter decides.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Shell.onDarkMuted),
                  ),
                  const SizedBox(height: Space.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTabs extends StatelessWidget {
  final String role;
  final Color accent;
  final void Function(String) onChanged;

  const _RoleTabs({
    required this.role,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'Job seeker',
            icon: Icons.search,
            selected: role == 'candidate',
            accent: accent,
            onTap: () => onChanged('candidate'),
          ),
          _Tab(
            label: 'Recruiter',
            icon: Icons.business_center_outlined,
            selected: role == 'hr',
            accent: accent,
            onTap: () => onChanged('hr'),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Tab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: Space.md),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? accent : const Color(0xFF71717A),
              ),
              const SizedBox(width: Space.sm),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? accent : const Color(0xFF71717A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
