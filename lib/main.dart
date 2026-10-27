import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';

const appwriteProjectId = '6ae112f6002b84c4affc';
const appwriteProjectName = 'alert_ledger';
const appwriteEndpoint = 'https://fra.cloud.appwrite.io/v1';

final appwriteClient =
    Client().setEndpoint(appwriteEndpoint).setProject(appwriteProjectId);

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appwriteProjectName,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const AppwritePingPage(),
    );
  }
}

class AppwritePingPage extends StatefulWidget {
  const AppwritePingPage({super.key});

  @override
  State<AppwritePingPage> createState() => _AppwritePingPageState();
}

class _AppwritePingPageState extends State<AppwritePingPage> {
  bool _isPinging = false;
  bool? _pingSucceeded;
  String? _status;

  Future<void> _pingAppwrite() async {
    setState(() {
      _isPinging = true;
      _status = null;
      _pingSucceeded = null;
    });

    try {
      final response = await appwriteClient.ping();
      if (!mounted) return;
      setState(() {
        _status = 'Connected: $response';
        _pingSucceeded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Ping failed: $error';
        _pingSucceeded = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isPinging = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (_pingSucceeded) {
      true => Colors.green.shade700,
      false => Theme.of(context).colorScheme.error,
      null => null,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Appwrite connection')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  appwriteProjectName,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text('Project ID'),
                SelectableText(appwriteProjectId),
                const SizedBox(height: 12),
                const Text('Endpoint'),
                SelectableText(appwriteEndpoint),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isPinging ? null : _pingAppwrite,
                  icon: _isPinging
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_isPinging ? 'Pinging...' : 'Ping Appwrite'),
                ),
                if (_status case final status?) ...[
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      status,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: statusColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
