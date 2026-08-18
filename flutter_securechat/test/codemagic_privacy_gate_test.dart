import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/audit_codemagic_privacy.dart';

void main() {
  test(
    'Codemagic workflows are pinned, fail-closed and never auto-publish',
    () {
      expect(auditCodemagicPrivacy(projectRoot: Directory.current), isEmpty);
    },
  );
}
