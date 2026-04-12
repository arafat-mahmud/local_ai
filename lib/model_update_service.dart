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
    final Directory modelsDir = await _resolveModelsDirectory();
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final File destinationFile = File('${modelsDir.path}/${model.fileName}');
    final File tempFile = File('${destinationFile.path}.download');
    final InstalledModel? previous = installedModel;
    final String downloadUrl = _normalizeModelDownloadUrl(
      rawUrl: model.fileUrl,
      fileName: model.fileName,
    );

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

      await _downloadModelFile(
        initialUrl: downloadUrl,
        tempFile: tempFile,
        modelName: model.modelName,
        fileName: model.fileName,
      );

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

      if (_looksLikeInvalidModelFile(destinationFile.path)) {
        if (destinationFile.existsSync()) {
          destinationFile.deleteSync();
        }
        throw const FormatException(
          'Downloaded file is not a model binary (.gguf/.bin/.onnx). Check manifest file_url.',
        );
      }

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
      if (_isNoSpaceLeftError(error)) {
        await _deletePartialDownloads(modelsDir);
        statusMessage =
            'Not enough storage to install model. Please free device storage and retry.';
        lastError =
            'Insufficient storage (No space left on device). Required: ${_readableBytes(model.fileSizeBytes)}.';
      } else {
        statusMessage = 'Model download failed. Please try again.';
      }
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      rethrow;
    } finally {
      isDownloading = false;
      notifyListeners();
    }
  }

  Future<void> _downloadModelFile({
    required String initialUrl,
    required File tempFile,
    required String modelName,
    required String fileName,
  }) async {
    String url = initialUrl;
    String? cookieHeader;

    for (int attempt = 0; attempt < 4; attempt++) {
      final Map<String, String> requestHeaders = <String, String>{};
      if (cookieHeader != null && cookieHeader.isNotEmpty) {
        requestHeaders[HttpHeaders.cookieHeader] = cookieHeader;
      }

      final Response<dynamic> response = await _dio.download(
        url,
        tempFile.path,
        deleteOnError: true,
        options: requestHeaders.isEmpty
            ? null
            : Options(headers: requestHeaders),
        onReceiveProgress: (int count, int total) {
          downloadBytesReceived = count;
          downloadTotalBytes = total > 0 ? total : null;
          if (total > 0) {
            downloadProgress = count / total;
          }
          statusMessage =
              'Downloading $modelName (${_readableBytes(count)} / ${_readableBytes(downloadTotalBytes)})';
          notifyListeners();
        },
      );

      final String contentType =
          response.headers.value(Headers.contentTypeHeader) ?? '';
      if (_isKnownModelBinaryFile(tempFile)) {
        return;
      }
      final bool isModelByHeaders = _looksLikeModelBinaryByHeaders(
        url: url,
        contentType: contentType,
        contentDisposition: response.headers.value('content-disposition'),
        contentLength: _parseInt(response.headers.value(Headers.contentLengthHeader)),
      );
      final bool looksHtmlByFile = _looksLikeHtmlFile(tempFile);
      if (isModelByHeaders && !looksHtmlByFile) {
        return;
      }
      final bool looksHtmlByType = _looksLikeHtmlResponse(contentType);
      final bool looksHtml = looksHtmlByType || looksHtmlByFile;
      if (!looksHtml) {
        return;
      }

      // Avoid showing a misleading 100% progress when only a tiny HTML
      // interstitial/error page was downloaded from the model host.
      downloadProgress = 0;
      downloadBytesReceived = 0;
      downloadTotalBytes = null;

      final String html = _readTextHead(tempFile);
      final String? hostError = _extractHostDownloadErrorMessage(html);
      if (hostError != null) {
        throw StateError(hostError);
      }

      final String? mergedCookie = _mergeSetCookies(
        existingCookieHeader: cookieHeader,
        setCookieHeaders: response.headers.map[HttpHeaders.setCookieHeader],
      );
      if (mergedCookie != null && mergedCookie.isNotEmpty) {
        cookieHeader = mergedCookie;
      }

      final String? retryUrl = _extractRetryDownloadUrlFromHtml(
        html: html,
        originalUrl: url,
      );
      if (retryUrl != null && retryUrl != url) {
        statusMessage = 'Download page detected. Retrying with direct file link...';
        notifyListeners();
        url = retryUrl;
        continue;
      }

      final String fallbackDirectUrl = _normalizeModelDownloadUrl(
        rawUrl: initialUrl,
        fileName: fileName,
      );
      if (fallbackDirectUrl != url) {
        statusMessage = 'Retrying with model file direct URL...';
        notifyListeners();
        url = fallbackDirectUrl;
        continue;
      }
      break;
    }

    throw const FormatException(
      'Download URL returned HTML instead of model binary. Check your manifest file_url and use a direct model binary link.',
    );
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
      if (model.filePath.isNotEmpty &&
          File(model.filePath).existsSync() &&
          !_looksLikeInvalidModelFile(model.filePath)) {
        installedModel = model;
        statusMessage = 'Installed model found. Ready for offline use.';
      } else {
        if (model.filePath.isNotEmpty && File(model.filePath).existsSync()) {
          File(model.filePath).deleteSync();
        }
        installedModel = null;
        await prefs.remove(_installedModelKey);
        statusMessage =
            'Model metadata invalid or file missing. Please download model again.';
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
      final String trimmed = data.trimLeft();
      if (_looksLikeHtmlText(trimmed)) {
        throw const FormatException(
          'MODEL_MANIFEST_URL is not a manifest JSON file. Use your manifest JSON direct-download URL (not the model file link).',
        );
      }
      final Map<String, dynamic> parsed =
          jsonDecode(data) as Map<String, dynamic>;
      return RemoteModelManifest.fromJson(parsed);
    }
    if (data is List<int>) {
      final String text = utf8.decode(data, allowMalformed: true);
      final String trimmed = text.trimLeft();
      if (_looksLikeHtmlText(trimmed)) {
        throw const FormatException(
          'MODEL_MANIFEST_URL is not a manifest JSON file. Use your manifest JSON direct-download URL (not the model file link).',
        );
      }
      final Map<String, dynamic> parsed =
          jsonDecode(text) as Map<String, dynamic>;
      return RemoteModelManifest.fromJson(parsed);
    }
    throw const FormatException('Unsupported manifest format.');
  }

  Future<RemoteModelManifest> _resolveRemoteModel() async {
    final String directUrl = _toDirectDownloadUrl(config.manifestUrl);
    final _RemoteProbe probe = await _probeRemoteResource(directUrl);
    final bool explicitDirectModelLink = _isLikelyDirectModelLink(
      config.manifestUrl,
      directUrl,
    );

    try {
      return await _downloadManifest();
    } catch (error) {
      final bool allowDirectFallback =
          explicitDirectModelLink ||
          (probe.isLikelyModelBinary &&
              !_looksLikeManifestFileName(probe.fileName));
      if (!allowDirectFallback || !_shouldFallbackToDirectModel(error)) {
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

Future<Directory> _resolveModelsDirectory() async {
  final Directory supportDir = await getApplicationSupportDirectory();
  final List<Directory> candidateRoots = <Directory>[
    if (Platform.isAndroid) ...<Directory>[
      if (await getExternalStorageDirectory() case final Directory ext) ext,
    ],
    supportDir,
  ];

  for (final Directory root in candidateRoots) {
    final Directory dir = Directory('${root.path}/models');
    if (_canWriteToDirectory(dir)) {
      return dir;
    }
  }

  return Directory('${supportDir.path}/models');
}

bool _canWriteToDirectory(Directory directory) {
  try {
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final File probe = File('${directory.path}/.write_test');
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _deletePartialDownloads(Directory modelsDir) async {
  if (!modelsDir.existsSync()) {
    return;
  }
  for (final FileSystemEntity entity in modelsDir.listSync()) {
    if (entity is File && entity.path.endsWith('.download')) {
      try {
        entity.deleteSync();
      } catch (_) {
        // Keep going for other stale partial downloads.
      }
    }
  }
}

bool _isNoSpaceLeftError(Object error) {
  if (error is FileSystemException) {
    final String lower = error.toString().toLowerCase();
    return lower.contains('no space left on device') ||
        lower.contains('errno = 28') ||
        lower.contains('errno 28');
  }
  if (error is DioException) {
    final String lower = error.toString().toLowerCase();
    return lower.contains('no space left on device') ||
        lower.contains('errno = 28') ||
        lower.contains('errno 28');
  }
  return false;
}

String _fallbackFileName(String url) {
  try {
    final Uri uri = Uri.parse(url);
    final String? idValue = uri.queryParameters['id'];
    if (idValue != null && idValue.isNotEmpty) {
      return 'model_$idValue.gguf';
    }

    if (uri.pathSegments.isNotEmpty) {
      final String lastSegment = uri.pathSegments.last.trim();
      if (lastSegment.isNotEmpty &&
          lastSegment != 'download' &&
          lastSegment != 'uc') {
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

  final String host = uri.host.toLowerCase();
  if (host.contains('huggingface.co')) {
    final List<String> segments = List<String>.from(uri.pathSegments);
    final int blobIndex = segments.indexOf('blob');
    if (blobIndex != -1) {
      segments[blobIndex] = 'resolve';
      return _ensureHuggingFaceDownloadQuery(
        uri.replace(pathSegments: segments).toString(),
      );
    }
    final int treeIndex = segments.indexOf('tree');
    if (treeIndex != -1) {
      segments[treeIndex] = 'resolve';
      return _ensureHuggingFaceDownloadQuery(
        uri.replace(pathSegments: segments).toString(),
      );
    }
    if (segments.contains('resolve')) {
      return _ensureHuggingFaceDownloadQuery(rawUrl);
    }
    if (segments.length >= 3 &&
        _looksLikeModelFileName(segments.last) &&
        segments[2] != 'resolve') {
      final List<String> rewritten = <String>[
        segments[0],
        segments[1],
        'resolve',
        'main',
        ...segments.sublist(2),
      ];
      return _ensureHuggingFaceDownloadQuery(
        uri.replace(pathSegments: rewritten).toString(),
      );
    }
  }

  if (host == 'github.com') {
    final List<String> segments = List<String>.from(uri.pathSegments);
    final int blobIndex = segments.indexOf('blob');
    if (blobIndex != -1 && segments.length > blobIndex + 1) {
      final String owner = segments.isNotEmpty ? segments[0] : '';
      final String repo = segments.length > 1 ? segments[1] : '';
      final String branch = segments[blobIndex + 1];
      final List<String> filePathSegments = segments.sublist(blobIndex + 2);
      if (owner.isNotEmpty &&
          repo.isNotEmpty &&
          branch.isNotEmpty &&
          filePathSegments.isNotEmpty) {
        return Uri.https(
          'raw.githubusercontent.com',
          '/$owner/$repo/$branch/${filePathSegments.join('/')}',
        ).toString();
      }
    }
  }

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

  return Uri.https('drive.google.com', '/uc', <String, String>{
    'id': fileId,
    'export': 'download',
  }).toString();
}

String _normalizeModelDownloadUrl({
  required String rawUrl,
  required String fileName,
}) {
  final String direct = _toDirectDownloadUrl(rawUrl);
  final Uri uri = Uri.parse(direct);
  final String host = uri.host.toLowerCase();

  if (!host.contains('huggingface.co')) {
    return direct;
  }

  final List<String> segments = List<String>.from(uri.pathSegments);
  if (segments.length >= 4 && segments[2] == 'resolve') {
    final String last = segments.last.toLowerCase();
    if (last == fileName.toLowerCase()) {
      return _ensureHuggingFaceDownloadQuery(direct);
    }
    if (_looksLikeModelFileName(last)) {
      segments[segments.length - 1] = fileName;
      return _ensureHuggingFaceDownloadQuery(
        uri.replace(pathSegments: segments).toString(),
      );
    }
    if (!_looksLikeModelFileName(last)) {
      return _ensureHuggingFaceDownloadQuery(
        uri.replace(pathSegments: <String>[
          ...segments,
          fileName,
        ]).toString(),
      );
    }
  }

  if (segments.length >= 2 && !segments.contains('resolve')) {
    return _ensureHuggingFaceDownloadQuery(
      uri.replace(pathSegments: <String>[
        segments[0],
        segments[1],
        'resolve',
        'main',
        fileName,
      ]).toString(),
    );
  }

  return _ensureHuggingFaceDownloadQuery(direct);
}

String _ensureHuggingFaceDownloadQuery(String url) {
  final Uri parsed = Uri.parse(url);
  if (!parsed.host.toLowerCase().contains('huggingface.co')) {
    return url;
  }
  final Map<String, String> query = <String, String>{
    ...parsed.queryParameters,
    'download': 'true',
  };
  return parsed.replace(queryParameters: query).toString();
}

bool _looksLikeModelFileName(String value) {
  final String lower = value.toLowerCase();
  return lower.endsWith('.gguf') ||
      lower.endsWith('.bin') ||
      lower.endsWith('.onnx');
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
    final String fileNameLower = (fileName ?? '').toLowerCase();
    if (_looksLikeManifestFileName(fileNameLower)) {
      return false;
    }
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

bool _looksLikeManifestFileName(String? fileName) {
  if (fileName == null) {
    return false;
  }
  final String lower = fileName.trim().toLowerCase();
  if (lower.isEmpty) {
    return false;
  }
  return lower.endsWith('.json') || lower.contains('manifest');
}

bool _looksLikeInvalidModelFile(String filePath) {
  final String lower = filePath.toLowerCase();
  if (_looksLikeManifestFileName(lower)) {
    return true;
  }
  if (lower.endsWith('.gguf') ||
      lower.endsWith('.bin') ||
      lower.endsWith('.onnx')) {
    return false;
  }
  return true;
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

bool _looksLikeHtmlResponse(String? contentType) {
  final String normalized = (contentType ?? '').toLowerCase();
  return normalized.contains('text/html') ||
      normalized.contains('application/xhtml+xml');
}

bool _looksLikeModelBinaryByHeaders({
  required String url,
  required String? contentType,
  required String? contentDisposition,
  required int? contentLength,
}) {
  final _RemoteProbe probe = _RemoteProbe.fromHeaders(
    url: url,
    contentType: contentType,
    contentDisposition: contentDisposition,
    contentLength: contentLength,
  );
  return probe.isLikelyModelBinary;
}

bool _looksLikeHtmlText(String text) {
  final String lower = text.toLowerCase();
  return lower.startsWith('<!doctype html') ||
      lower.startsWith('<html') ||
      lower.contains('<head') ||
      lower.contains('<body');
}

bool _looksLikeHtmlFile(File file) {
  if (!file.existsSync()) {
    return false;
  }
  if (_isKnownModelBinaryFile(file)) {
    return false;
  }
  final String head = _readTextHead(file).toLowerCase();
  final String trimmed = head.trimLeft();
  return trimmed.startsWith('<!doctype html') ||
      trimmed.startsWith('<html') ||
      trimmed.startsWith('<head');
}

bool _isKnownModelBinaryFile(File file) {
  if (!file.existsSync()) {
    return false;
  }
  final RandomAccessFile raf = file.openSync(mode: FileMode.read);
  try {
    if (raf.lengthSync() < 4) {
      return false;
    }
    final List<int> bytes = raf.readSync(4);
    return bytes.length == 4 &&
        bytes[0] == 0x47 && // G
        bytes[1] == 0x47 && // G
        bytes[2] == 0x55 && // U
        bytes[3] == 0x46; // F
  } finally {
    raf.closeSync();
  }
}

String _readTextHead(File file, {int maxBytes = 262144}) {
  final RandomAccessFile raf = file.openSync(mode: FileMode.read);
  try {
    final int length = raf.lengthSync();
    final int toRead = length < maxBytes ? length : maxBytes;
    final List<int> bytes = raf.readSync(toRead);
    return utf8.decode(bytes, allowMalformed: true);
  } finally {
    raf.closeSync();
  }
}

String? _extractGoogleDriveConfirmedDownloadUrl({
  required String html,
  required String originalUrl,
}) {
  if (html.isEmpty) {
    return null;
  }

  final Uri original = Uri.parse(originalUrl);
  final Uri base = Uri(
    scheme: original.scheme.isEmpty ? 'https' : original.scheme,
    host: original.host,
  );

  final RegExp formActionPattern = RegExp(
    r'<form[^>]*action="([^"]+)"[^>]*>',
    caseSensitive: false,
  );
  final Match? formMatch = formActionPattern.firstMatch(html);
  if (formMatch != null && formMatch.groupCount >= 1) {
    String action = _decodeHtmlEntities(formMatch.group(1)!);
    final Uri actionUri = base.resolve(action);

    final Map<String, String> params = <String, String>{};
    final RegExp inputPattern = RegExp(
      r'<input[^>]*name="([^"]+)"[^>]*value="([^"]*)"[^>]*>',
      caseSensitive: false,
    );
    for (final Match match in inputPattern.allMatches(html)) {
      final String key = _decodeHtmlEntities(match.group(1)!);
      final String value = _decodeHtmlEntities(match.group(2)!);
      params[key] = value;
    }
    if (params.containsKey('id') && params['id']!.isNotEmpty) {
      params.putIfAbsent('export', () => 'download');
      if (!params.containsKey('confirm') || params['confirm']!.isEmpty) {
        params['confirm'] = 't';
      }
      action = actionUri.replace(queryParameters: params).toString();
      return action;
    }
  }

  final RegExp hrefPattern = RegExp(r'href="([^"]+)"', caseSensitive: false);
  for (final Match match in hrefPattern.allMatches(html)) {
    String candidate = _decodeHtmlEntities(match.group(1)!);
    if (!candidate.contains('confirm=')) {
      continue;
    }
    final Uri resolved = base.resolve(candidate);
    final String host = resolved.host.toLowerCase();
    if (host.contains('google.com') || host.contains('googleusercontent.com')) {
      return resolved.toString();
    }
  }

  final RegExp escapedUrlPattern = RegExp(
    r'https:\\/\\/[^"\\]+confirm=[^"\\]+',
    caseSensitive: false,
  );
  final Match? escapedUrl = escapedUrlPattern.firstMatch(html);
  if (escapedUrl != null) {
    final String decoded = escapedUrl
        .group(0)!
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u003d', '=')
        .replaceAll(r'\u0026', '&');
    return _decodeHtmlEntities(decoded);
  }

  return null;
}

String? _extractRetryDownloadUrlFromHtml({
  required String html,
  required String originalUrl,
}) {
  final Uri uri = Uri.parse(originalUrl);
  final String host = uri.host.toLowerCase();
  if (host.contains('drive.google.com')) {
    return _extractGoogleDriveConfirmedDownloadUrl(
      html: html,
      originalUrl: originalUrl,
    );
  }
  if (host.contains('huggingface.co')) {
    final String? fromHtml = _extractHuggingFaceResolvedDownloadUrl(html, uri);
    if (fromHtml != null) {
      return _ensureHuggingFaceDownloadQuery(fromHtml);
    }
    final String normalized = _toDirectDownloadUrl(originalUrl);
    if (normalized != originalUrl) {
      return normalized;
    }
  }
  return null;
}

String? _extractHuggingFaceResolvedDownloadUrl(String html, Uri original) {
  final RegExp hrefPattern = RegExp(r'href="([^"]+)"', caseSensitive: false);
  final RegExp modelPathPattern = RegExp(
    r'/[^/]+/[^/]+/resolve/[^"\s]+\.(gguf|bin|onnx)(\?[^"\s]*)?$',
    caseSensitive: false,
  );
  for (final Match match in hrefPattern.allMatches(html)) {
    String candidate = _decodeHtmlEntities(match.group(1)!);
    if (candidate.isEmpty) {
      continue;
    }
    final Uri resolved = original.resolve(candidate);
    if (!resolved.host.toLowerCase().contains('huggingface.co')) {
      continue;
    }
    if (modelPathPattern.hasMatch(resolved.path)) {
      return resolved.toString();
    }
  }
  return null;
}

String _decodeHtmlEntities(String input) {
  return input
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

bool _isLikelyDirectModelLink(String rawUrl, String convertedUrl) {
  final String rawLower = rawUrl.toLowerCase();
  final String convertedLower = convertedUrl.toLowerCase();

  try {
    final Uri rawUri = Uri.parse(rawUrl);
    if (rawUri.host.contains('drive.google.com') &&
        rawUri.path == '/file/d' &&
        !rawUri.pathSegments.contains('view')) {
      return false;
    }
    if (rawUri.host.contains('drive.google.com') &&
        rawUri.queryParameters.containsKey('id') &&
        (rawUri.path == '/uc' || rawUri.path == '/download')) {
      return true;
    }
  } catch (_) {
    // Ignore parse errors and continue with string heuristics.
  }

  if (rawLower.endsWith('.gguf') ||
      rawLower.endsWith('.bin') ||
      rawLower.endsWith('.onnx')) {
    return true;
  }
  if (convertedLower.endsWith('.gguf') ||
      convertedLower.endsWith('.bin') ||
      convertedLower.endsWith('.onnx')) {
    return true;
  }
  return false;
}

String? _extractHostDownloadErrorMessage(String html) {
  final String lower = html.toLowerCase();
  if (lower.contains('quota exceeded') ||
      lower.contains('too many users have viewed or downloaded this file')) {
    return 'Download quota exceeded for this file. Re-upload to your model host or use another host, then update the model URL.';
  }
  if (lower.contains('you need access') ||
      lower.contains('request access') ||
      lower.contains('access denied')) {
    return 'Model file is not publicly accessible. Update host permissions and try again.';
  }
  if (lower.contains('file you have requested does not exist') ||
      lower.contains('sorry, the file you have requested does not exist')) {
    return 'Model file was not found. Check the file URL in the manifest.';
  }
  return null;
}

String? _mergeSetCookies({
  required String? existingCookieHeader,
  required List<String>? setCookieHeaders,
}) {
  if ((existingCookieHeader == null || existingCookieHeader.isEmpty) &&
      (setCookieHeaders == null || setCookieHeaders.isEmpty)) {
    return null;
  }

  final Map<String, String> cookies = <String, String>{};

  if (existingCookieHeader != null && existingCookieHeader.isNotEmpty) {
    for (final String part in existingCookieHeader.split(';')) {
      final List<String> kv = part.split('=');
      if (kv.length < 2) {
        continue;
      }
      final String key = kv.first.trim();
      final String value = kv.sublist(1).join('=').trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        cookies[key] = value;
      }
    }
  }

  if (setCookieHeaders != null) {
    for (final String header in setCookieHeaders) {
      final List<String> segments = header.split(';');
      if (segments.isEmpty) {
        continue;
      }
      final String first = segments.first;
      final int eq = first.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      final String key = first.substring(0, eq).trim();
      final String value = first.substring(eq + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) {
        cookies[key] = value;
      }
    }
  }

  if (cookies.isEmpty) {
    return null;
  }
  return cookies.entries
      .map((MapEntry<String, String> e) => '${e.key}=${e.value}')
      .join('; ');
}
