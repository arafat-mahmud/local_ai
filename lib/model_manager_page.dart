import 'dart:async';

import 'package:flutter/material.dart';

import 'chat_page.dart';
import 'model_update_service.dart';

const String kModelManifestUrl = String.fromEnvironment(
  'MODEL_MANIFEST_URL',
  defaultValue:
      'https://huggingface.co/arafat-mahmud/smollm2-1.7b-q8-local-ai/resolve/main/model_manifest.json',
);

class ModelManagerPage extends StatefulWidget {
  const ModelManagerPage({super.key, required this.title});

  final String title;

  @override
  State<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends State<ModelManagerPage> {
  late final ModelUpdateService _service;
  bool _didAutoOpenChat = false;

  @override
  void initState() {
    super.initState();
    _service = ModelUpdateService(
      config: const ModelUpdateConfig(manifestUrl: kModelManifestUrl),
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
    _maybeAutoOpenChat();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _maybeAutoOpenChat() async {
    if (_didAutoOpenChat || !mounted) {
      return;
    }
    final InstalledModel? installed = _service.installedModel;
    final bool isBusy = _service.isCheckingForUpdates || _service.isDownloading;
    if (installed == null || isBusy) {
      return;
    }
    _didAutoOpenChat = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ChatPage(
              modelReady: true,
              modelLabel: installed.modelName,
              hasModelUpdate: _service.hasUpdateAvailable,
              modelFilePath: installed.filePath,
              startNewSessionOnLaunch: true,
            ),
          ),
        ),
      );
    });
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

  Future<void> _openChat() async {
    final InstalledModel? installed = _service.installedModel;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          modelReady: installed != null,
          modelLabel: installed?.modelName ?? 'Local AI',
          hasModelUpdate: _service.hasUpdateAvailable,
          modelFilePath: installed?.filePath,
          startNewSessionOnLaunch: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final InstalledModel? installed = _service.installedModel;
    final RemoteModelManifest? latest = _service.latestManifest;
    final bool hasUpdate = _service.hasUpdateAvailable;
    final bool canDownloadOrUpdate =
        installed == null || hasUpdate;
    final bool downloading = _service.isDownloading;
    final bool checking = _service.isCheckingForUpdates;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
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
                    Text(
                      'Version: ${installed.version} (${installed.versionCode})',
                    ),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Downloading Model...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _service.hasKnownDownloadTotal
                            ? _service.downloadProgress
                            : null,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            _service.hasKnownDownloadTotal
                                ? 'Progress: ${(_service.downloadProgress * 100).toStringAsFixed(1)}%'
                                : 'Progress: Downloading...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _service.statusMessage,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _service.hasKnownDownloadTotal
                          ? '${_formatBytes(_service.downloadBytesReceived)} / ${_formatBytes(_service.downloadTotalBytes)}'
                          : '${_formatBytes(_service.downloadBytesReceived)} downloaded',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                onPressed: (downloading || !canDownloadOrUpdate)
                    ? null
                    : _downloadOrUpdate,
                icon: const Icon(Icons.download),
                label: Text(
                  installed == null
                      ? 'Download Model'
                      : hasUpdate
                      ? 'Update Model'
                      : 'Model Up to Date',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Open Chat'),
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
                  'Model host setup:\n'
                  '1) Upload your model file (for example: .gguf).\n'
                  '2) Upload your manifest JSON file (for example: model_manifest.json).\n'
                  '3) Put the direct model link in manifest file_url.\n'
                  '4) In this app, use only the manifest file direct-download URL as MODEL_MANIFEST_URL.',
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
