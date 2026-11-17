import 'package:flutter/material.dart';

import '../api/client.dart';
import 'quote_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _url = TextEditingController(text: 'https://ppsolar.fr');
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.saveCredentials(
        baseUrl: _url.text.trim(),
        user: _user.text,
        appPassword: _password.text,
      );
      // Test réel : /settings répond 200 si l'auth est bonne
      await ApiClient.instance.get('/settings');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const QuoteListScreen()),
      );
    } catch (e) {
      await ApiClient.instance.clearCredentials();
      setState(() => _error = 'Connexion impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Devis PPSOLAR',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text(
                  'Connexion au site avec un mot de passe\nd\'application WordPress',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration:
                      const InputDecoration(labelText: 'Adresse du site'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  decoration:
                      const InputDecoration(labelText: 'Identifiant WordPress'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe d\'application',
                    helperText:
                        'Profil WordPress → Mots de passe d\'application',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: const TextStyle(color: Color(0xFFB32D2E))),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Se connecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
