import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_core_flow.dart';

void main() {
  testWidgets('core navigation and chat interaction tour remains device-runnable', (
    tester,
  ) async {
    await runDeviceCoreFlow(tester);
    debugPrint('[device-core] body-returned');
  });
}
