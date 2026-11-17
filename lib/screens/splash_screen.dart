import 'package:flutter/material.dart';

import '../api/client.dart';
import 'login_screen.dart';
import 'quote_list_screen.dart';

/// Écran de démarrage : logo qui monte en fondu + zoom léger,
/// puis navigation vers la liste (connecté) ou la connexion.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<double> _scale = Tween(begin: 0.82, end: 1.0).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    Future.delayed(const Duration(milliseconds: 1600), _next);
  }

  void _next() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => ApiClient.instance.isConfigured
            ? const QuoteListScreen()
            : const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C2B33),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      alignment: Alignment.center,
                      child: Text('PP',
                          style: const TextStyle(
                      fontFamily: 'Poppins',
                              fontSize: 44,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1C2B33))),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text('Devis PPSOLAR',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text('ppsolar.fr',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                        fontSize: 12.5, color: const Color(0xFFDFE4E8))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
