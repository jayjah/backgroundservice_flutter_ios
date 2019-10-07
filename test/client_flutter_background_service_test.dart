import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:client_flutter_background_service/client_flutter_background_service.dart';

void main() {
  const MethodChannel channel = MethodChannel('client_flutter_background_service');

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    //expect(await BackgroundSericePlugin.platformVersion, '42');
  });
}
