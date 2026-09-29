import 'package:appflowy_editor/src/editor/util/file_picker/file_picker_service.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/services.dart';

class FilePicker implements FilePickerService {
  @override
  Future<String?> getDirectoryPath({String? title}) {
    return fp.FilePicker.getDirectoryPath(dialogTitle: title);
  }

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    Function(fp.FilePickerStatus p1)? onFileLoading,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) async {
    final windowsOptions = fp.WindowsOptions(
      lockParentWindow: lockParentWindow,
    );

    if (allowMultiple) {
      final files = await fp.FilePicker.pickFiles(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        onFileLoading: onFileLoading,
        windowsOptions: windowsOptions,
      );

      if (files.isEmpty) {
        return null;
      }
      return FilePickerResult(files);
    } else {
      final file = await fp.FilePicker.pickFile(
        dialogTitle: dialogTitle,
        initialDirectory: initialDirectory,
        type: type,
        allowedExtensions: allowedExtensions,
        onFileLoading: onFileLoading,
        windowsOptions: windowsOptions,
      );

      if (file == null) {
        return null;
      }
      return FilePickerResult([file]);
    }
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    Uint8List? bytes,
    String? initialDirectory,
    fp.FileType type = fp.FileType.any,
    List<String>? allowedExtensions,
    bool lockParentWindow = false,
  }) async {
    // Na v13.x, saveFile requer `fileName` e `bytes: Uint8List` e retorna `Uri?`.
    // Se o seu fluxo apenas precisar do diálogo para salvar um arquivo vazio/novo:
    final uri = await fp.FilePicker.saveFile(
      fileName: fileName ?? '',
      bytes: bytes ?? Uint8List(0),
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      windowsOptions: fp.WindowsOptions(lockParentWindow: lockParentWindow),
    );

    return uri?.scheme == 'file' ? uri!.toFilePath() : uri?.toString();
  }
}
