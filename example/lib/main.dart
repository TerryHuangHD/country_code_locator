import 'package:country_code_locator/country_code_locator.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const CountryCodeLocatorExample());
}

class CountryCodeLocatorExample extends StatelessWidget {
  const CountryCodeLocatorExample({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const LookupPage(),
    );
  }
}

class LookupPage extends StatefulWidget {
  const LookupPage({super.key});

  @override
  State<LookupPage> createState() => _LookupPageState();
}

class _LookupPageState extends State<LookupPage> {
  final _latitudeController = TextEditingController(text: '35.6812');
  final _longitudeController = TextEditingController(text: '139.7671');

  OfflineCountryCode? _locator;
  String _message = 'Loading bundled boundaries…';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final locator = await OfflineCountryCode.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _locator = locator;
        _message = 'Ready';
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _message = 'Load failed: $error');
    }
  }

  void _lookup() {
    final locator = _locator;
    final latitude = double.tryParse(_latitudeController.text);
    final longitude = double.tryParse(_longitudeController.text);
    if (locator == null) {
      setState(() => _message = 'Boundary data is not ready yet.');
      return;
    }
    if (latitude == null || longitude == null) {
      setState(() => _message = 'Enter numeric latitude and longitude.');
      return;
    }
    try {
      final code = locator.lookup(latitude: latitude, longitude: longitude);
      setState(() => _message = code ?? 'No unambiguous land code');
    } on ArgumentError catch (error) {
      setState(() => _message = error.message.toString());
    }
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Country code locator')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _latitudeController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Latitude',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _longitudeController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Longitude',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onSubmitted: (_) => _lookup(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _locator == null ? null : _lookup,
                  child: const Text('Look up'),
                ),
                const SizedBox(height: 24),
                SelectableText(
                  _message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
