import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'state/ledger_store.dart';
import 'theme.dart';
import 'widgets/illustrations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlertLedgerApp());
}

class AlertLedgerApp extends StatelessWidget {
  const AlertLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alert Ledger',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const _Boot(),
    );
  }
}

class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  late Future<void> _start = LedgerStore.instance.start();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _start,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const EmptyLedgerArt(),
                    const SizedBox(height: 16),
                    Text("Can't reach the server", style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text(
                      'Check your internet connection and try again. On the web, the site address must also be added as a platform in Appwrite.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _start = LedgerStore.instance.start()),
                      child: const Text('Try again'),
                    ),
                  ]),
                ),
              ),
            ),
          );
        }
        return const AppShell();
      },
    );
  }
}
