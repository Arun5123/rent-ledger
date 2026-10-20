import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/cloudinary_config.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/repositories/repositories.dart';

/// Uploads to Cloudinary through an unsigned upload preset.
///
/// Deletions run either:
/// 1. Signed via Cloudinary's destroy API (permanent, anytime) if API credentials
///    are configured.
/// 2. Client-side via Cloudinary's delete-by-token API (valid ~10 minutes) when
///    "Return delete token" is enabled on the unsigned preset in the Cloudinary
///    console.
class CloudinaryStorageRepository implements StorageRepository {
  CloudinaryStorageRepository({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// One-time delete tokens returned by Cloudinary at upload time.
  final Map<String, String> _deleteTokens = {};

  static const String _tokenPrefPrefix = 'cld_del_tok_';

  @override
  Future<String> uploadBytes({
    required String path,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) async {
    if (!CloudinaryConfig.isConfigured) {
      throw const AppException(
        'File uploads are not configured. Rebuild with '
        '--dart-define=CLOUDINARY_CLOUD_NAME and '
        '--dart-define=CLOUDINARY_UPLOAD_PRESET.',
      );
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/'
      '${CloudinaryConfig.cloudName}/auto/upload',
    );

    try {
      final folder = _folderOf(path);
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
        ..fields['public_id'] = _publicIdOf(path)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: path.split('/').last,
          ),
        );
      if (folder.isNotEmpty) {
        request.fields['folder'] = folder;
      }

      final response = await _client.send(request);
      final body = await response.stream.bytesToString();
      if (response.statusCode >= 400) {
        String? cloudMessage;
        try {
          final errJson = jsonDecode(body);
          if (errJson is Map && errJson['error'] is Map) {
            cloudMessage = errJson['error']['message']?.toString();
          }
        } catch (_) {}

        throw AppException(
          cloudMessage != null && cloudMessage.isNotEmpty
              ? 'Upload failed (${response.statusCode}): $cloudMessage'
              : 'Upload failed (${response.statusCode}). Confirm the Cloudinary '
                  'preset is set to unsigned.',
        );
      }

      final payload = jsonDecode(body) as Map<String, dynamic>;
      final url = payload['secure_url'] as String?;
      final deleteToken = payload['delete_token'] as String?;

      if (url != null &&
          url.isNotEmpty &&
          deleteToken != null &&
          deleteToken.isNotEmpty) {
        _deleteTokens[url] = deleteToken;
        unawaited(_persistToken(url, deleteToken));
      }

      if (url is! String || url.isEmpty) {
        throw const AppException('Cloudinary did not return a file URL.');
      }
      return url;
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      throw AppException.from(error, stackTrace);
    }
  }

  /// Cloudinary takes the directory and the file name as separate fields.
  static String _folderOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? '' : path.substring(0, index);
  }

  /// Cloudinary appends the format itself, so the extension is dropped.
  static String _publicIdOf(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  /// Extracts the Cloudinary public_id from a delivery URL.
  static String? extractPublicId(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final uploadIndex = segments.indexOf('upload');
      if (uploadIndex == -1 || uploadIndex >= segments.length - 1) return null;

      var startIndex = uploadIndex + 1;
      if (startIndex < segments.length &&
          RegExp(r'^v\d+$').hasMatch(segments[startIndex])) {
        startIndex++;
      }

      if (startIndex >= segments.length) return null;

      final resourceType = extractResourceType(url);
      final remaining = segments.sublist(startIndex).join('/');

      if (resourceType == 'raw') {
        return remaining;
      }
      final dot = remaining.lastIndexOf('.');
      return dot <= 0 ? remaining : remaining.substring(0, dot);
    } catch (_) {
      return null;
    }
  }

  /// Extracts the resource_type ('image' or 'raw') from a delivery URL.
  static String extractResourceType(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final uploadIndex = segments.indexOf('upload');
      if (uploadIndex > 0) {
        final candidate = segments[uploadIndex - 1];
        if (candidate == 'raw' || candidate == 'video') return candidate;
      }
    } catch (_) {}
    return 'image';
  }

  /// Deletes the file stored at [url].
  ///
  /// If [CloudinaryConfig.hasApiCredentials] is configured, deletes directly
  /// using Cloudinary's Destroy API.
  /// Otherwise uses Cloudinary's delete-by-token API if a valid token was
  /// captured at upload time.
  @override
  Future<bool> deleteBytes({required String url}) async {
    if (!CloudinaryConfig.isConfigured) {
      return false;
    }

    // 1. Signed deletion if API credentials are configured
    if (CloudinaryConfig.hasApiCredentials) {
      final publicId = extractPublicId(url);
      if (publicId != null) {
        final success = await _deleteSigned(url: url, publicId: publicId);
        if (success) {
          _deleteTokens.remove(url);
          unawaited(_removePersistedToken(url));
          return true;
        }
      }
    }

    // 2. Unsigned deletion via delete_token (valid within 10 minutes of upload)
    final deleteToken = _deleteTokens[url] ?? await _loadPersistedToken(url);
    if (deleteToken != null && deleteToken.isNotEmpty) {
      final success = await _deleteByToken(deleteToken);
      _deleteTokens.remove(url);
      unawaited(_removePersistedToken(url));
      if (success) return true;
    }

    return true; // Local unlinking proceeds
  }

  Future<bool> _deleteByToken(String deleteToken) async {
    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/'
        '${CloudinaryConfig.cloudName}/delete_by_token',
      );

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'token': deleteToken},
      );

      if (response.statusCode >= 400) {
        return false;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return (payload['result'] as String?) == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteSigned({
    required String url,
    required String publicId,
  }) async {
    try {
      final resourceType = extractResourceType(url);
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/'
        '${CloudinaryConfig.cloudName}/$resourceType/destroy',
      );

      final timestamp =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final toSign =
          'public_id=$publicId&timestamp=$timestamp${CloudinaryConfig.apiSecret}';
      final signature = sha1.convert(utf8.encode(toSign)).toString();

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'public_id': publicId,
          'timestamp': timestamp,
          'api_key': CloudinaryConfig.apiKey,
          'signature': signature,
        },
      );

      if (response.statusCode >= 400) {
        return false;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final result = payload['result'] as String?;
      return result == 'ok' || result == 'not found';
    } catch (_) {
      return false;
    }
  }

  Future<void> _persistToken(String url, String deleteToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_tokenPrefPrefix$url', deleteToken);
    } catch (_) {}
  }

  Future<String?> _loadPersistedToken(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_tokenPrefPrefix$url');
    } catch (_) {
      return null;
    }
  }

  Future<void> _removePersistedToken(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_tokenPrefPrefix$url');
    } catch (_) {}
  }
}
