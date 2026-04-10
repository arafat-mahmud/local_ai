import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelUpdateConfig {
  const ModelUpdateConfig({
    required this.manifestUrl,
    this.storageFolderName = 'models',
  });

  final String manifestUrl;
  final String storageFolderName;
}

class InstalledModel {
  const InstalledModel({
    required this.version,
    required this.versionCode,
    required this.modelName,
    required this.fileName,
    required this.filePath,
    required this.installedAtIso,
    this.fileSizeBytes,
  });

  final String version;
  final int versionCode;
  final String modelName;
  final String fileName;
  final String filePath;
  final String installedAtIso;
  final int? fileSizeBytes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'version_code': versionCode,
      'model_name': modelName,
      'file_name': fileName,
      'file_path': filePath,
      'installed_at_iso': installedAtIso,
      'file_size_bytes': fileSizeBytes,
    };
  }

  factory InstalledModel.fromJson(Map<String, dynamic> json) {
    return InstalledModel(
      version: (json['version'] ?? '').toString(),
      versionCode: _parseInt(json['version_code']) ?? 0,
      modelName: (json['model_name'] ?? '').toString(),
      fileName: (json['file_name'] ?? '').toString(),
      filePath: (json['file_path'] ?? '').toString(),
      installedAtIso: (json['installed_at_iso'] ?? '').toString(),
      fileSizeBytes: _parseInt(json['file_size_bytes']),
    );
  }
}

class RemoteModelManifest {
  const RemoteModelManifest({
    required this.version,
    required this.versionCode,
    required this.modelName,
    required this.fileName,
    required this.fileUrl,
    this.fileSizeBytes,
    this.notes,
  });

  final String version;
  final int versionCode;
  final String modelName;
  final String fileName;
  final String fileUrl;
  final int? fileSizeBytes;
  final String? notes;

  bool isNewerThan(InstalledModel installed) {
    if (versionCode != installed.versionCode) {
      return versionCode > installed.versionCode;
    }
    return version != installed.version;
  }

  factory RemoteModelManifest.fromJson(Map<String, dynamic> json) {
    final String fileUrl = (json['file_url'] ?? json['url'] ?? '')
        .toString()
        .trim();
    final String fileName = (json['file_name'] ?? json['model_file_name'] ?? '')
        .toString()
        .trim();

    if (fileUrl.isEmpty) {
      throw const FormatException('Manifest file_url is required.');
    }

    return RemoteModelManifest(
      version: (json['version'] ?? '1.0.0').toString(),
      versionCode: _parseInt(json['version_code']) ?? 1,
      modelName: (json['model_name'] ?? 'AI Model').toString(),
      fileName: fileName.isEmpty ? _fallbackFileName(fileUrl) : fileName,
      fileUrl: fileUrl,
      fileSizeBytes: _parseInt(json['file_size_bytes']),
      notes: json['notes']?.toString(),
    );
  }
}

class ModelUpdateService extends ChangeNotifier {
  ModelUpdateService({required this.config}) : _dio = Dio(_dioOptions());

  final ModelUpdateConfig config;
  final Dio _dio;

  static const String _installedModelKey = 'installed_model_metadata';

  InstalledModel? installedModel;
  RemoteModelManifest? latestManifest;

  bool isCheckingForUpdates = false;
  bool isDownloading = false;
  double downloadProgress = 0.0;
  int downloadBytesReceived = 0;
  int? downloadTotalBytes;
  String statusMessage = 'Checking local model...';
  String? lastError;

  bool get hasInstalledModel => installedModel != null;
  bool get hasKnownDownloadTotal =>
      downloadTotalBytes != null && downloadTotalBytes! > 0;

  bool get hasUpdateAvailable {
    if (latestManifest == null) {
      return false;
    }
    if (installedModel == null) {
      return true;
    }
    return latestManifest!.isNewerThan(installedModel!);
  }

  Future<void> initialize({bool autoCheckRemote = true}) async {
    await _loadInstalledModel();
    if (autoCheckRemote) {
      await checkForUpdates();
    }
  }

  Future<void> checkForUpdates() async {
    isCheckingForUpdates = true;
    lastError = null;
    statusMessage = 'Checking for model updates...';
    notifyListeners();

    try {
      final RemoteModelManifest remote = await _resolveRemoteModel();
      latestManifest = remote;

      if (!hasInstalledModel) {
        statusMessage =
            'Download ${remote.modelName} (${_readableBytes(remote.fileSizeBytes)}) to enable AI.';
      } else if (hasUpdateAvailable) {
        statusMessage = 'A new AI model update is available.';
      } else {
        statusMessage = 'Your model is up to date.';
      }
    } catch (error) {
      lastError = error.toString();
      if (hasInstalledModel) {
        statusMessage = 'Offline mode active. Installed model is ready.';
      } else {
        statusMessage =
            'Could not load model manifest. Please connect to internet.';
      }
    } finally {
      isCheckingForUpdates = false;
      notifyListeners();
    }
  }

  Future<void> downloadAndInstallLatest() async {
    if (isDownloading) {
      return;
    }

    if (latestManifest == null) {
      await checkForUpdates();
    }

    if (latestManifest == null) {
      throw StateError('No model metadata found from server.');
    }

    final RemoteModelManifest model = latestManifest!;
    final Directory baseDir = await getApplicationSupportDirectory();
    final Directory modelsDir = Directory(
      '${baseDir.path}/${config.storageFolderName}',
    );
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final File destinationFile = File('${modelsDir.path}/${model.fileName}');
    final File tempFile = File('${destinationFile.path}.download');
    final InstalledModel? previous = installedModel;
    final String downloadUrl = _toDirectDownloadUrl(model.fileUrl);

    isDownloading = true;
    downloadProgress = 0;
    downloadBytesReceived = 0;
    downloadTotalBytes = null;
    lastError = null;
    statusMessage = 'Downloading ${model.modelName}...';
    notifyListeners();

    try {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }

      final Response<dynamic> response = await _dio.download(
        downloadUrl,
        tempFile.path,
        deleteOnError: true,
        onReceiveProgress: (int count, int total) {
          downloadBytesReceived = count;
          downloadTotalBytes = total > 0 ? total : null;
          if (total > 0) {
            downloadProgress = count / total;
          }
          statusMessage =
              'Downloading ${model.modelName} (${_readableBytes(count)} / ${_readableBytes(downloadTotalBytes)})';
          notifyListeners();
        },
      );

      final String contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      if (contentType.contains('text/html')) {
        throw const FormatException(
          'Download URL returned HTML instead of model binary. Check Google Drive sharing/direct link.',
        );
      }

      if (!tempFile.existsSync()) {
        throw const FileSystemException('Downloaded file not found.');
      }

      if (model.fileSizeBytes != null &&
          model.fileSizeBytes! > 0 &&
          tempFile.lengthSync() != model.fileSizeBytes) {
        throw StateError(
          'Downloaded file size mismatch. Expected ${model.fileSizeBytes}, got ${tempFile.lengthSync()}.',
        );
      }

      if (destinationFile.existsSync()) {
        destinationFile.deleteSync();
      }
      tempFile.renameSync(destinationFile.path);

      final InstalledModel installed = InstalledModel(
        version: model.version,
        versionCode: model.versionCode,
        modelName: model.modelName,
        fileName: model.fileName,
        filePath: destinationFile.path,
        installedAtIso: DateTime.now().toUtc().toIso8601String(),
        fileSizeBytes: destinationFile.lengthSync(),
      );

      installedModel = installed;
      await _saveInstalledModel(installed);

      if (previous != null &&
          previous.filePath != installed.filePath &&
          File(previous.filePath).existsSync()) {
        File(previous.filePath).deleteSync();
      }

      statusMessage = 'Model installed successfully. Offline AI is ready.';
      latestManifest = model;
      downloadProgress = 1.0;
      downloadBytesReceived = destinationFile.lengthSync();
      downloadTotalBytes = destinationFile.lengthSync();
    } catch (error) {
      lastError = error.toString();
      statusMessage = 'Model download failed. Please try again.';
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      rethrow;
    } finally {
      isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> _loadInstalledModel() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? stored = prefs.getString(_installedModelKey);
    if (stored == null || stored.isEmpty) {
      installedModel = null;
      statusMessage = 'No local model installed yet.';
      notifyListeners();
      return;
    }

    try {
      final Map<String, dynamic> parsed =
          jsonDecode(stored) as Map<String, dynamic>;
      final InstalledModel model = InstalledModel.fromJson(parsed);
      if (model.filePath.isNotEmpty && File(model.filePath).existsSync()) {
        installedModel = model;
        statusMessage = 'Installed model found. Ready for offline use.';
      } else {
        installedModel = null;
        await prefs.remove(_installedModelKey);
        statusMessage =
            'Model metadata found but file is missing. Please download again.';
      }
    } catch (error) {
      installedModel = null;
      await prefs.remove(_installedModelKey);
      statusMessage = 'Invalid model metadata. Please download again.';
      debugPrint('Failed to load local model metadata: $error');
    }

    notifyListeners();
  }

  Future<void> _saveInstalledModel(InstalledModel model) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_installedModelKey, jsonEncode(model.toJson()));
  }

  Future<RemoteModelManifest> _downloadManifest() async {
    final String manifestUrl = _toDirectDownloadUrl(config.manifestUrl);
    final Response<dynamic> response = await _dio.get<dynamic>(
      manifestUrl,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 15),
        headers: const <String, String>{'Range': 'bytes=0-262143'},
      ),
    );
    final dynamic data = response.data;

    if (data is Map<String, dynamic>) {
      return RemoteModelManifest.fromJson(data);
    }
    if (data is String) {
      final Map<String, dynamic> parsed =
          jsonDecode(data) as Map<String, dynamic>;
      return RemoteModelManifest.fromJson(parsed);
    }
    if (data is List<int>) {
      final String text = utf8.decode(data, allowMalformed: true);
      final Map<String, dynamic> parsed =
          jsonDecode(text) as Map<String, dynamic>;
      return RemoteModelManifest.fromJson(parsed);
    }
    throw const FormatException('Unsupported manifest format.');
  }

  Future<RemoteModelManifest> _resolveRemoteModel() async {
    final String directUrl = _toDirectDownloadUrl(config.manifestUrl);
    final _RemoteProbe probe = await _probeRemoteResource(directUrl);

    if (probe.isLikelyModelBinary) {
      return _buildManifestFromDirectModelUrl(
        config.manifestUrl,
        inferredFileName: probe.fileName,
        inferredFileSizeBytes: probe.contentLength,
      );
    }

    try {
      return await _downloadManifest();
    } catch (error) {
      if (!_shouldFallbackToDirectModel(error)) {
        rethrow;
      }
      return _buildManifestFromDirectModelUrl(
        config.manifestUrl,
        inferredFileName: probe.fileName,
        inferredFileSizeBytes: probe.contentLength,
      );
    }
  }

  Future<_RemoteProbe> _probeRemoteResource(String directUrl) async {
    try {
      final Response<dynamic> head = await _dio.head<dynamic>(
        directUrl,
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          responseType: ResponseType.plain,
        ),
      );
      return _RemoteProbe.fromHeaders(
        url: directUrl,
        contentType: head.headers.value(Headers.contentTypeHeader),
        contentDisposition: head.headers.value('content-disposition'),
        contentLength: _parseInt(
          head.headers.value(Headers.contentLengthHeader),
        ),
      );
    } catch (_) {
      return _RemoteProbe(url: directUrl);
    }
  }

  RemoteModelManifest _buildManifestFromDirectModelUrl(
    String url, {
    String? inferredFileName,
    int? inferredFileSizeBytes,
  }) {
    final String directUrl = _toDirectDownloadUrl(url);
    final String fileName =
        (inferredFileName != null && inferredFileName.trim().isNotEmpty)
        ? inferredFileName.trim()
        : _fallbackFileName(directUrl);
    final String modelName = _modelNameFromFile(fileName);

    return RemoteModelManifest(
      version: 'direct-link',
      versionCode: 1,
      modelName: modelName,
      fileName: fileName,
      fileUrl: directUrl,
      fileSizeBytes: inferredFileSizeBytes,
      notes:
          'Direct model URL mode: provide a manifest URL later for proper versioned updates.',
    );
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  static BaseOptions _dioOptions() {
    return BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      followRedirects: true,
      validateStatus: (int? status) =>
          status != null && status >= 200 && status < 400,
    );
  }
}

String _fallbackFileName(String url) {
  try {
    final Uri uri = Uri.parse(url);
    final String? idValue = uri.queryParameters['id'];
    if (idValue != null &&
        idValue.isNotEmpty &&
        uri.pathSegments.contains('download')) {
      return 'model_$idValue.gguf';
    }

    if (uri.pathSegments.isNotEmpty) {
      final String lastSegment = uri.pathSegments.last.trim();
      if (lastSegment.isNotEmpty && lastSegment != 'download') {
        return lastSegment;
      }
    }
  } catch (_) {
    // No-op: fallback below.
  }
  return 'model.gguf';
}

String _modelNameFromFile(String fileName) {
  final String name = fileName.trim();
  if (name.isEmpty) {
    return 'AI Model';
  }
  final int dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0) {
    return name;
  }
  return name.substring(0, dotIndex);
}

int? _parseInt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  return int.tryParse(value.toString());
}

String _readableBytes(int? bytes) {
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

String _toDirectDownloadUrl(String rawUrl) {
  final Uri uri = Uri.parse(rawUrl);

  if (!uri.host.contains('drive.google.com')) {
    return rawUrl;
  }

  String? fileId = uri.queryParameters['id'];
  if (fileId == null || fileId.isEmpty) {
    final List<String> segments = uri.pathSegments;
    final int fileMarkerIndex = segments.indexOf('d');
    if (fileMarkerIndex != -1 && fileMarkerIndex + 1 < segments.length) {
      fileId = segments[fileMarkerIndex + 1];
    }
  }

  if (fileId == null || fileId.isEmpty) {
    return rawUrl;
  }

  return Uri.https(
    'drive.usercontent.google.com',
    '/download',
    <String, String>{'id': fileId, 'export': 'download', 'confirm': 't'},
  ).toString();
}

bool _shouldFallbackToDirectModel(Object error) {
  if (error is FormatException) {
    return true;
  }
  if (error is TypeError) {
    return true;
  }
  if (error is DioException && error.type == DioExceptionType.badResponse) {
    return true;
  }
  return false;
}

class _RemoteProbe {
  const _RemoteProbe({
    required this.url,
    this.contentType,
    this.contentDisposition,
    this.contentLength,
  });

  final String url;
  final String? contentType;
  final String? contentDisposition;
  final int? contentLength;

  String? get fileName =>
      _extractFilenameFromContentDisposition(contentDisposition);

  bool get isLikelyModelBinary {
    final String type = (contentType ?? '').toLowerCase();
    if (type.contains('application/json') || type.contains('text/json')) {
      return false;
    }
    if (type.contains('application/octet-stream')) {
      return true;
    }
    final String lowerUrl = url.toLowerCase();
    if (lowerUrl.endsWith('.gguf') || lowerUrl.endsWith('.bin')) {
      return true;
    }
    final String name = (fileName ?? '').toLowerCase();
    if (name.endsWith('.gguf') || name.endsWith('.bin')) {
      return true;
    }
    return false;
  }

  static _RemoteProbe fromHeaders({
    required String url,
    required String? contentType,
    required String? contentDisposition,
    required int? contentLength,
  }) {
    return _RemoteProbe(
      url: url,
      contentType: contentType,
      contentDisposition: contentDisposition,
      contentLength: contentLength,
    );
  }
}

String? _extractFilenameFromContentDisposition(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final RegExp utfMatch = RegExp(
    r"filename\*=UTF-8''([^;]+)",
    caseSensitive: false,
  );
  final Match? utf = utfMatch.firstMatch(value);
  if (utf != null && utf.groupCount >= 1) {
    return Uri.decodeComponent(utf.group(1)!);
  }
  final RegExp simpleMatch = RegExp(
    r'filename="([^"]+)"',
    caseSensitive: false,
  );
  final Match? simple = simpleMatch.firstMatch(value);
  if (simple != null && simple.groupCount >= 1) {
    return simple.group(1);
  }
  return null;
}
