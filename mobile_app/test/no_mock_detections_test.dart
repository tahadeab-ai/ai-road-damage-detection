import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Strict Rule: No mock, random, or synthetic detection code in lib/', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'lib directory must exist');

    final bannedKeywords = [
      '_generateMockDetections',
      'generateMockDetections',
      'mockDetections',
      'rand.nextDouble()',
      'Random().nextDouble()',
      '_generateFallbackBoxes',
    ];

    final violations = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final content = entity.readAsStringSync();
        for (final keyword in bannedKeywords) {
          if (content.contains(keyword)) {
            violations.add('${entity.path} contains banned mock keyword: "$keyword"');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Mock or fabricated detection code was detected! Violations:\n${violations.join('\n')}',
    );
  });
}
