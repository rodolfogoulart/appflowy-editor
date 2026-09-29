import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class FilePickerResult {
  const FilePickerResult(this.files);

  /// Picked files.
  final List<PlatformFile> files;
}

/// Abstract file picker as a service to implement dependency injection.
abstract class FilePickerService {
  Future<String?> getDirectoryPath({
    String? title,
  }) async =>
      throw UnimplementedError('getDirectoryPath() has not been implemented.');

  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) async =>
      throw UnimplementedError('pickFiles() has not been implemented.');

  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    Uint8List? bytes,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async =>
      throw UnimplementedError('saveFile() has not been implemented.');
}
