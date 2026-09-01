import 'dart:io';
import 'package:path/path.dart' as p;

class PdfConverter {
  static Future<void> testTabula() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);

    final javaPath = p.join(
      exeDir,
      'jre',
      'bin',
      'java.exe',
    );

    final tabulaPath = p.join(
      exeDir,
      'tools',
      'tabula.jar',
    );

    final result = await Process.run(
      javaPath,
      [
        '-jar',
        tabulaPath,
        '--help',
      ],
      workingDirectory: exeDir,
    );

    print(result.stdout);
    print(result.stderr);
  }
}