import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// GitHub repository that hosts APK releases.
const githubOwner = 'farrukh47';
const githubRepo = 'pocket-ledger';

class UpdateInfo {
  final String tag;
  final String version;
  final int build;
  final String apkUrl;
  final String releaseUrl;
  final String notes;
  final int sizeBytes;

  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.releaseUrl,
    required this.notes,
    required this.sizeBytes,
  });

  String get label => '$version+$build';

  String get sizeLabel => formatBytes(sizeBytes);
}

String formatBytes(int bytes) {
  if (bytes <= 0) return 'unknown size';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class AppUpdate {
  static const _install = MethodChannel('pocket_ledger/install');

  static Future<({String version, int build})> current() async {
    final raw = await _install.invokeMethod<dynamic>('getVersion');
    final map = Map<String, dynamic>.from(raw as Map);
    final version = (map['version'] as String?)?.trim() ?? '0.0.0';
    final build = (map['build'] as num?)?.toInt() ?? 0;
    return (version: version, build: build);
  }

  static Future<String> currentVersionLabel() async {
    final info = await current();
    return '${info.version}+${info.build}';
  }

  /// Returns update details when a newer GitHub release exists; otherwise null.
  static Future<UpdateInfo?> check() async {
    final info = await current();
    final localVersion = info.version;
    final localBuild = info.build;

    final uri = Uri.parse(
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
    );
    final response = await http.get(uri, headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'PocketLedger/$githubRepo',
    }).timeout(const Duration(seconds: 20));

    if (response.statusCode == 404) {
      throw const FormatException(
        'No public releases found. If the GitHub repo is private, make it public so updates can be checked.',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FormatException(
        'GitHub blocked the update check. The release feed must be publicly readable.',
      );
    }
    if (response.statusCode != 200) {
      throw FormatException('Update check failed (${response.statusCode}).');
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Unexpected update response.');
    }

    final tag = (data['tag_name'] as String? ?? '').trim();
    final assets = data['assets'];
    if (assets is! List || assets.isEmpty) {
      throw const FormatException('Release has no downloadable APK.');
    }

    String? apkUrl;
    String? assetName;
    var sizeBytes = 0;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = asset['name'] as String? ?? '';
      final url = asset['browser_download_url'] as String?;
      if (url != null && name.toLowerCase().endsWith('.apk')) {
        apkUrl = url;
        assetName = name;
        sizeBytes = (asset['size'] as num?)?.toInt() ?? 0;
        if (name.toLowerCase().contains('pocket-ledger')) break;
      }
    }
    if (apkUrl == null || assetName == null) {
      throw const FormatException('Release has no APK asset.');
    }

    final remote = _parseRemote(tag, assetName);
    if (!_isNewer(remote.version, remote.build, localVersion, localBuild)) {
      return null;
    }

    return UpdateInfo(
      tag: tag,
      version: remote.version,
      build: remote.build,
      apkUrl: apkUrl,
      releaseUrl: data['html_url'] as String? ??
          'https://github.com/$githubOwner/$githubRepo/releases/tag/$tag',
      notes: (data['body'] as String? ?? '').trim(),
      sizeBytes: sizeBytes,
    );
  }

  /// Local APK path for [update], if a complete copy is already on disk.
  static Future<File?> cachedApk(UpdateInfo update) async {
    final file = await _apkFile(update);
    if (!await file.exists()) return null;
    final length = await file.length();
    if (!_isCompleteApk(length, update.sizeBytes)) {
      await file.delete();
      return null;
    }
    return file;
  }

  /// Downloads the APK, or reuses a complete cached copy for this version.
  static Future<File> download(
    UpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final cached = await cachedApk(update);
    if (cached != null) {
      final length = await cached.length();
      onProgress?.call(length, length);
      return cached;
    }

    final file = await _apkFile(update);
    await file.parent.create(recursive: true);
    if (await file.exists()) await file.delete();
    await _deleteOtherCachedApks(keepLabel: update.label);

    final partial = File('${file.path}.part');
    if (await partial.exists()) await partial.delete();

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(update.apkUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'PocketLedger/$githubRepo');
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw FormatException('Download failed (${response.statusCode}).');
      }
      final total = response.contentLength > 0
          ? response.contentLength
          : update.sizeBytes;
      var received = 0;
      final sink = partial.openWrite();
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total > 0 ? total : received);
      }
      await sink.close();
      final length = await partial.length();
      if (!_isCompleteApk(length, update.sizeBytes > 0 ? update.sizeBytes : total)) {
        await partial.delete();
        throw const FormatException('Downloaded update looks incomplete.');
      }
      await partial.rename(file.path);
      return file;
    } finally {
      client.close(force: true);
    }
  }

  static Future<File> _apkFile(UpdateInfo update) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'updates', 'pocket-ledger-${update.label}.apk'));
  }

  static bool _isCompleteApk(int length, int expectedBytes) {
    if (length < 1024 * 1024) return false;
    if (expectedBytes > 0) return length == expectedBytes;
    return true;
  }

  static Future<void> _deleteOtherCachedApks({required String keepLabel}) async {
    final dir = await getApplicationSupportDirectory();
    final updates = Directory(p.join(dir.path, 'updates'));
    if (!await updates.exists()) return;
    await for (final entity in updates.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('pocket-ledger-') || !name.endsWith('.apk')) continue;
      if (name == 'pocket-ledger-$keepLabel.apk') continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  /// Installs over the existing app (same package + signing key).
  static Future<void> installUpdate(File apk) async {
    await _install.invokeMethod<void>('installUpdate', {'path': apk.path});
  }

  static ({String version, int build}) _parseRemote(String tag, String assetName) {
    final fromAsset = RegExp(
      r'(\d+\.\d+\.\d+)\+(\d+)',
    ).firstMatch(assetName);
    if (fromAsset != null) {
      return (
        version: fromAsset.group(1)!,
        build: int.parse(fromAsset.group(2)!),
      );
    }
    final fromTag = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(tag);
    if (fromTag == null) {
      throw FormatException('Unsupported release tag: $tag');
    }
    final major = int.parse(fromTag.group(1)!);
    final minor = int.parse(fromTag.group(2)!);
    final patch = int.parse(fromTag.group(3)!);
    return (
      version: '$major.$minor.$patch',
      build: major * 10000 + minor * 100 + patch,
    );
  }

  static bool _isNewer(
    String remoteVersion,
    int remoteBuild,
    String localVersion,
    int localBuild,
  ) {
    final cmp = _compareSemver(remoteVersion, localVersion);
    if (cmp != 0) return cmp > 0;
    return remoteBuild > localBuild;
  }

  static int _compareSemver(String a, String b) {
    List<int> parts(String v) {
      final bits = v.split('.');
      int at(int i) => i < bits.length ? (int.tryParse(bits[i]) ?? 0) : 0;
      return [at(0), at(1), at(2)];
    }

    final left = parts(a);
    final right = parts(b);
    for (var i = 0; i < 3; i++) {
      if (left[i] != right[i]) return left[i].compareTo(right[i]);
    }
    return 0;
  }
}
