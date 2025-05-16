// lib/core/remote_control/command_executor.dart
import "dart:convert";
import "dart:io"; // <-- Added import for Platform

import "package:device_info_plus/device_info_plus.dart";
import "package:flutter/foundation.dart"; // For kIsWeb
import "package:the_conduit/core/logging/logger_service1.dart";
import "package:the_conduit/core/remote_control/command_definitions.dart";

class CommandExecutor {
  final LoggerService _logger = LoggerService("CommandExecutor");
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<CommandResponse> executeCommand(String rawCommandData) async {
    _logger.i("Attempting to execute raw command data: $rawCommandData");
    try {
      final Map<String, dynamic> decodedJson =
          jsonDecode(rawCommandData) as Map<String, dynamic>;
      final command = RemoteCommand.fromJson(decodedJson);
      _logger
          .i("Decoded command: ${command.type}, Payload: ${command.payload}");

      switch (command.type) {
        case CommandTypes.ping:
          return CommandResponse(
              success: true,
              message: "PONG",
              data: DateTime.now().toIso8601String());
        case CommandTypes.getDeviceInfo:
          return await _handleGetDeviceInfo();
        // Add more command handlers here
        default:
          _logger.w("Unknown command type: ${command.type}");
          return CommandResponse(
              success: false, message: "Unknown command type: ${command.type}");
      }
    } catch (e, stackTrace) {
      _logger.e("Error executing command: $e\n$stackTrace");
      return CommandResponse(
          success: false, message: "Error executing command: $e");
    }
  }

  Future<CommandResponse> _handleGetDeviceInfo() async {
    try {
      Map<String, dynamic> deviceInfoMap = {};
      if (kIsWeb) {
        WebBrowserInfo webBrowserInfo = await _deviceInfo.webBrowserInfo;
        deviceInfoMap = {
          "platform": "web",
          "browserName": webBrowserInfo.browserName.toString(),
          "appCodeName": webBrowserInfo.appCodeName,
          "appName": webBrowserInfo.appName,
          "appVersion": webBrowserInfo.appVersion,
          "deviceMemory": webBrowserInfo.deviceMemory,
          "language": webBrowserInfo.language,
          "languages": webBrowserInfo.languages,
          // "platform": webBrowserInfo.platform, // Duplicate key, removed
          "product": webBrowserInfo.product,
          "productSub": webBrowserInfo.productSub,
          "userAgent": webBrowserInfo.userAgent,
          "vendor": webBrowserInfo.vendor,
          "vendorSub": webBrowserInfo.vendorSub,
          "hardwareConcurrency": webBrowserInfo.hardwareConcurrency,
          "maxTouchPoints": webBrowserInfo.maxTouchPoints,
        };
      } else {
        if (Platform.isAndroid) {
          AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
          deviceInfoMap = {
            "platform": "android",
            "version.securityPatch": androidInfo.version.securityPatch,
            "version.sdkInt": androidInfo.version.sdkInt,
            "version.release": androidInfo.version.release,
            "version.previewSdkInt": androidInfo.version.previewSdkInt,
            "version.incremental": androidInfo.version.incremental,
            "version.codename": androidInfo.version.codename,
            "version.baseOS": androidInfo.version.baseOS,
            "board": androidInfo.board,
            "bootloader": androidInfo.bootloader,
            "brand": androidInfo.brand,
            "device": androidInfo.device,
            "display": androidInfo
                .display, // This is a string, not display metrics object
            "fingerprint": androidInfo.fingerprint,
            "hardware": androidInfo.hardware,
            "host": androidInfo.host,
            "id": androidInfo.id,
            "manufacturer": androidInfo.manufacturer,
            "model": androidInfo.model,
            "product": androidInfo.product,
            "supported32BitAbis": androidInfo.supported32BitAbis,
            "supported64BitAbis": androidInfo.supported64BitAbis,
            "supportedAbis": androidInfo.supportedAbis,
            "tags": androidInfo.tags,
            "type": androidInfo.type,
            "isPhysicalDevice": androidInfo.isPhysicalDevice,
            // "systemFeatures": androidInfo.systemFeatures, // This can be a large list
            // displayMetrics was removed from device_info_plus for AndroidDeviceInfo
            // If you need screen dimensions, use MediaQuery.of(context).size from a widget context
            // or a platform channel to get it from native Android if needed in a background service.
          };
        } else if (Platform.isIOS) {
          IosDeviceInfo iosInfo = await _deviceInfo.iosInfo;
          deviceInfoMap = {
            "platform": "ios",
            "name": iosInfo.name,
            "systemName": iosInfo.systemName,
            "systemVersion": iosInfo.systemVersion,
            "model": iosInfo.model,
            "localizedModel": iosInfo.localizedModel,
            "identifierForVendor": iosInfo.identifierForVendor,
            "isPhysicalDevice": iosInfo.isPhysicalDevice,
            "utsname.sysname:": iosInfo.utsname.sysname,
            "utsname.nodename:": iosInfo.utsname.nodename,
            "utsname.release:": iosInfo.utsname.release,
            "utsname.version:": iosInfo.utsname.version,
            "utsname.machine:": iosInfo.utsname.machine,
          };
        } else {
          deviceInfoMap = {
            "platform": Platform.operatingSystem,
            "message": "Platform not fully supported for detailed info"
          };
        }
      }
      _logger.i("Device info collected: ${deviceInfoMap.keys.toList()}");
      return CommandResponse(success: true, data: deviceInfoMap);
    } catch (e, stackTrace) {
      _logger.e("Error getting device info: $e\n$stackTrace");
      return CommandResponse(
          success: false, message: "Error getting device info: $e");
    }
  }
}
