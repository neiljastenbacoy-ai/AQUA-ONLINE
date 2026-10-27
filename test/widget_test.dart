import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'copyToClipboard writes the requested text to the platform clipboard',
    () async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText =
                  (call.arguments as Map<Object?, Object?>)['text'] as String;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await copyToClipboard('AQUA order');

      expect(copiedText, 'AQUA order');
    },
  );

  test('peso and oid helpers behave like the web app', () {
    expect(peso(25), '₱25.00');
    expect(peso(1234.5), '₱1,234.50');
    expect(pl(1, 'Gallon'), '1 Gallon');
    expect(pl(3, 'Gallon'), '3 Gallons');
    expect(initialsOf('Maria Santos'), 'MS');
  });
}
