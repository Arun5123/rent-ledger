import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';

/// Writes generated exports to disk and hands them to the OS share sheet.
class ExportFileSaver {
  const ExportFileSaver();

  Future<Directory> exportDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory =
        Directory('${base.path}/${AppConstants.exportFolderName}');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  /// Persists [bytes] and returns the absolute file path.
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final directory = await exportDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Opens the platform share sheet (also used to trigger "Print" on iOS).
  Future<void> share({
    required String filePath,
    required String subject,
    String? text,
  }) async {
    await Share.shareXFiles(
      <XFile>[XFile(filePath, mimeType: _mimeFor(filePath))],
      subject: subject,
      text: text,
    );
  }

  static String _mimeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.csv')) return 'text/csv';
    return 'application/octet-stream';
  }
}
