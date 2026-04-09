import 'dart:async';

import 'package:flutter/material.dart';

import 'model_update_service.dart';

const String kModelManifestUrl = String.fromEnvironment(
  'MODEL_MANIFEST_URL',
  defaultValue: 'https://drive.google.com/uc?export=download&id=YOUR_MANIFEST_FILE_ID',
);

class ModelManagerPage extends StatefulWidget {
  const ModelManagerPage({super.key, required this.title});

  final String title;

  @override
  State<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends State<ModelManagerPage> {
  late final ModelUpdateService _service;

  @override
  void initState() {
    super.initState();
    _service = ModelUpdateService(
      config: const ModelUpdateConfig(
        manifestUrl: kModelManifestUrl,
      ),
    );
    _service.addListener(_onServiceChanged);
    unawaited(_service.initialize(autoCheckRemote: true));
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    _service.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkUpdate() async {
    await _service.checkForUpdates();
  }

  Future<void> _downloadOrUpdate() async {
    try {
      await _service.downloadAndInstallLatest();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model installed successfully.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final InstalledModel? installed = _service.installedModel;
    final RemoteModelManifest? latest = _service.latestManifest;
    final bool hasUpdate = _service.hasUpdateAvailable;
    final bool downloading = _service.isDownloading;
    final bool checking = _service.isCheckingForUpdates;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Model Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(_service.statusMessage),
                  if (_service.lastError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _service.lastError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Installed Model',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (installed == null)
                    const Text('Not installed')
                  else ...<Widget>[
                    Text('Name: ${installed.modelName}'),
                    Text('Version: ${installed.version} (${installed.versionCode})'),
                    Text('File: ${installed.fileName}'),
                    Text('Size: ${_formatBytes(installed.fileSizeBytes)}'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Server Model',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (latest == null)
                    const Text('No server data loaded yet')
                  else ...<Widget>[
                    Text('Name: ${latest.modelName}'),
                    Text('Version: ${latest.version} (${latest.versionCode})'),
                    Text('Size: ${_formatBytes(latest.fileSizeBytes)}'),
                    if (latest.notes != null && latest.notes!.isNotEmpty)
                      Text('Notes: ${latest.notes}'),
                  ],
                ],
              ),
            ),
          ),
          if (downloading) ...<Widget>[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _service.downloadProgress),
            const SizedBox(height: 6),
            Text('${(_service.downloadProgress * 100).toStringAsFixed(1)}%'),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: (checking || downloading) ? null : _checkUpdate,
                icon: const Icon(Icons.sync),
                label: Text(checking ? 'Checking...' : 'Check Update'),
              ),
              FilledButton.icon(
                onPressed: downloading ? null : _downloadOrUpdate,
                icon: const Icon(Icons.download),
                label: Text(
                  installed == null
                      ? 'Download Model'
                      : hasUpdate
                          ? 'Update Model'
                          : 'Reinstall Model',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'After download, the model is stored in app data and can run offline. '
                'When a newer version is installed, the previous model file is deleted automatically.',
              ),
            ),
          ),
          if (kModelManifestUrl.contains('YOUR_MANIFEST_FILE_ID')) ...<Widget>[
            const SizedBox(height: 12),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Set your manifest link by replacing YOUR_MANIFEST_FILE_ID in '
                  'kModelManifestUrl or passing --dart-define=MODEL_MANIFEST_URL=...',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) {
    return 'unknown size';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(unitIndex == 0 ? 0 : 2)} ${units[unitIndex]}';
}
