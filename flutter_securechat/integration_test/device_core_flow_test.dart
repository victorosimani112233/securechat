import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/device_core_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('physical device core navigation and chat interaction tour', (
    tester,
  ) async {
    await runDeviceCoreFlow(tester);
    debugPrint('[device-core] body-returned');
  });
}
