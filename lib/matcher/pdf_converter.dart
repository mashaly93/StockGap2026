import 'dart:io';

class PdfConverter {
  static Future<void> testTabula() async {
    final result = await Process.run(
      'java',
      [
        '-jar',
        'tools/tabula.jar',
        '--help',
      ],
    );

    print(result.stdout);
    print(result.stderr);
  }
}