// lib/core/remote_control/remote_control_service.dart
import "dart:async";
import "dart:convert"; // For utf8 encoding/decoding and json
import "dart:io";
import "dart:typed_data"; // For Uint8List
import "dart:ui";

import "package:flutter_background_service/flutter_background_service.dart";
import "package:flutter_background_service_android/flutter_background_service_android.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:the_conduit/core/encryption/aes_gcm_service.dart"; // Import AES GCM Service
import "package:the_conduit/core/remote_control/command_definitions.dart";
import "package:the_conduit/core/remote_control/command_executor.dart";

import "../logging/logger_service.dart";

const String notificationChannelId = "conduit_remote_control_channel";
const int notificationId = 888;
const String initialNotificationTitle = "The Conduit Remote Service";
const String initialNotificationContent = "Initializing...";
const String listeningNotificationContent = "Listening for remote commands";

// Encryption key storage
const String _remoteControlEncryptionKeyName = "remote_control_encryption_key";
const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

// Generate and store encryption key if not already present
Future<String> _getOrCreateEncryptionKey() async {
  String? existingKey = await _secureStorage.read(key: _remoteControlEncryptionKeyName);
  if (existingKey != null && existingKey.isNotEmpty) {
    return existingKey;
  }
  
  // Generate a secure random key (32 bytes = 256 bits, converted to base64)
  final random = Random.secure();
  final values = List<int>.generate(32, (i) => random.nextInt(256));
  final secureKey = base64Encode(values);
  
  // Store the key
  await _secureStorage.write(key: _remoteControlEncryptionKeyName, value: secureKey);
  return secureKey;
}

@pragma("vm:entry-point")
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final LoggerService logger = LoggerService("RemoteControlService_Background");
  final AesGcmService aesService = AesGcmService(); // Instantiate AES Service
  final CommandExecutor commandExecutor =
  CommandExecutor(); // Instantiate Command Executor

  logger.i("Background Service Started.");

  // Get encryption key
  String encryptionKey;
  try {
    encryptionKey = await _getOrCreateEncryptionKey();
    logger.i("Retrieved encryption key for secure communications.");
  } catch (e, s) {
    logger.e("Failed to retrieve encryption key. Using fallback method.", e, s);
    // Fallback key - not ideal but better than hardcoding in the source
    encryptionKey = "RemoteControlTemporaryKey_${DateTime.now().millisecondsSinceEpoch}";
  }

  if (service is AndroidServiceInstance) {
    service.on("setAsForeground").listen((event) {
      service.setAsForegroundService();
      logger.i("Service set to run in foreground.");
    });

    service.on("setAsBackground").listen((event) {
      service.setAsBackgroundService();
      logger.i("Service set to run in background.");
    });
  }

  service.on("stopService").listen((event) {
    service.stopSelf();
    logger.i("Service stopping itself.");
  });

  // Timer for updating notification, can be removed if not needed or adjusted
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        // Update notification content if needed, e.g., with status or last activity
        // Corrected method name: setForegroundNotificationInfo
        service.setForegroundNotificationInfo(
          title: "Conduit Remote Active",
          content:
          "Listening... Last check: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
        );
      }
    }
    logger.d("Background service heartbeat: ${DateTime.now()}");
  });

  try {
    const int port = 12345; // Make this configurable later
    final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    logger.i(
        "Successfully bound to ${serverSocket.address.address}:${serverSocket.port}");

    // Corrected method name: setForegroundNotificationInfo
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: initialNotificationTitle,
        content: "$listeningNotificationContent on port $port (Encrypted)",
      );
    } else {
      // For iOS or other platforms, you might need different handling or this might not be applicable
      // For now, we assume Android foreground service context for this specific notification update.
    }

    await for (Socket clientSocket in serverSocket) {
      logger.i(
          "Client connected: ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}");
      List<int> accumulatedData = [];

      clientSocket.listen(
            (Uint8List data) async {
          logger.d("Received ${data.length} encrypted bytes from client.");
          accumulatedData.addAll(data);

          if (accumulatedData.isNotEmpty) {
            try {
              logger
                  .d("Attempting to decrypt ${accumulatedData.length} bytes.");
              final Uint8List decryptedBytes =
              await aesService.decryptBytesWithPassword(
                Uint8List.fromList(accumulatedData),
                encryptionKey,
              );
              accumulatedData.clear();

              final String decryptedCommandJson = utf8.decode(decryptedBytes);
              logger.i("Decrypted command JSON: $decryptedCommandJson");

              final CommandResponse response =
              await commandExecutor.executeCommand(decryptedCommandJson);
              logger.i(
                  "Command execution response: Success=${response.success}, Message=${response.message}");

              final String responseJson = jsonEncode(response.toJson());
              final Uint8List responseBytes = utf8.encode(responseJson);

              logger.d("Encrypting response: $responseJson");
              final Uint8List encryptedResponseBytes =
              await aesService.encryptBytesWithPassword(
                responseBytes,
                encryptionKey,
              );

              logger.d(
                  "Sending ${encryptedResponseBytes.length} encrypted bytes to client.");
              clientSocket.add(encryptedResponseBytes);
              await clientSocket.flush();
            } catch (e, stackTrace) {
              logger.e("Error processing client data: $e\n$stackTrace");
              try {
                final errorResponse = CommandResponse(
                    success: false,
                    message: "Error processing command: ${e.toString()}");
                final errorJson = jsonEncode(errorResponse.toJson());
                final errorBytes = utf8.encode(errorJson);
                final encryptedError =
                await aesService.encryptBytesWithPassword(
                    errorBytes, encryptionKey);
                clientSocket.add(encryptedError);
                await clientSocket.flush();
              } catch (encErr) {
                logger.e("Failed to send encrypted error: $encErr");
              }
              accumulatedData.clear();
            }
          }
        },
        onError: (error, stackTrace) {
          logger.e("Client socket error: $error\n$stackTrace");
          clientSocket.close();
        },
        onDone: () {
          logger.i(
              "Client disconnected: ${clientSocket.remoteAddress.address}:${clientSocket.remotePort}");
          clientSocket.close();
        },
        cancelOnError: true,
      );
    }
  } catch (e, stackTrace) {
    logger.e("Fatal error starting ServerSocket: $e\n$stackTrace");
    if (service is AndroidServiceInstance) {
      // Corrected method name: setForegroundNotificationInfo
      service.setForegroundNotificationInfo(
        title: "Conduit Remote Error",
        content: "Failed to start listener: $e",
      );
    }
  }
}

class RemoteControlManager {
  final LoggerService _logger = LoggerService("RemoteControlManager");
  final FlutterBackgroundService _service = FlutterBackgroundService();

  Future<void> initializeService() async {
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: initialNotificationTitle,
        initialNotificationContent: initialNotificationContent,
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
      ),
    );
    _logger.i("Remote Control Service configured.");
  }

  Future<void> startService() async {
    bool isRunning = await _service.isRunning();
    if (!isRunning) {
      _service.startService();
      _logger.i("Remote Control Service started.");
    } else {
      _logger.i("Remote Control Service is already running.");
    }
  }

  Future<void> stopService() async {
    bool isRunning = await _service.isRunning();
    if (isRunning) {
      _service.invoke("stopService");
      _logger.i("Stop command sent to Remote Control Service.");
    } else {
      _logger.i("Remote Control Service is not running.");
    }
  }
}