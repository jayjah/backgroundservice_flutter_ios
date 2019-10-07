import 'package:client_flutter_background_service/client_flutter_background_service.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';


abstract class BackgroundSericePlugin {
  static const MethodChannel _channel =
  const MethodChannel('de.movementfam.webapp/background_service');

  /// Initialize the plugin
  static Future<bool> initialize(int config) async {
    //Start Service in native part
    final callbacker = PluginUtilities.getCallbackHandle(callbackDispatcher);
    await _channel.invokeMethod('BackgroundService.initializeService',
        <dynamic>[config,callbacker.toRawHandle()]);
  }

  static Future<bool> setMainCallback(void Function(List<String> id)
  callback) async {
    //Get data from native part
    final args = <dynamic>[
      PluginUtilities.getCallbackHandle(callback).toRawHandle()
    ];
    //args.addAll(id);
    await _channel.invokeMethod('BackgroundService.registerMainCallback', args);
    debugPrint("BackgroundServicePlugin :: initialize: parameter that was called to native part: $args");
    return true;
  }

  static Future<bool> enableBackgroundFetchIOS([void Function() callback]) async {
    if (callback == null) {
      return await _channel.invokeMethod('BackgroundService.enableBackgroundFetch', []);
    } else {
      final args = <dynamic>[
        PluginUtilities.getCallbackHandle(callback).toRawHandle()
      ];
      return await _channel.invokeMethod('BackgroundService.enableBackgroundFetch', args);
    }
  }

  static Future<bool> sendPushNotification(String title, String shortText, String longText) async {
    await _channel.invokeMethod('BackgroundService.sendPushNotification', [title, shortText, longText]);
    return true;
  }

  static Future<bool> checkConnectivity() {
    return _channel.invokeMethod('BackgroundService.checkConnectivity',[]);
  }

}