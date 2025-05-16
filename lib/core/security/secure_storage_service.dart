// lib/core/security/secure_storage_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/logger_service.dart';

const String agentCodeKey = 'current_agent_code_conduit';

class SecureStorageService {
  final FlutterSecureStorage _storage;
  final LoggerService _logger;
  
  // Define android options with encryption
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  // Define iOS options with accessibility settings
  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  SecureStorageService(this._storage, this._logger) {
    _logger.info("SecureStorage", "Secure storage service initialized");
  }

  Future<void> writeAgentCode(String agentCode) async {
    try {
      await _storage.write(
        key: agentCodeKey, 
        value: agentCode,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      _logger.info("SecureStorage", "Agent code saved successfully");
    } catch (e, s) {
      _logger.error("SecureStorage", "Failed to write agent code", e, s);
      rethrow;
    }
  }

  Future<String?> readAgentCode() async {
    try {
      final code = await _storage.read(
        key: agentCodeKey,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      return code;
    } catch (e, s) {
      _logger.error("SecureStorage", "Failed to read agent code", e, s);
      return null;
    }
  }

  Future<void> deleteAgentCode() async {
    try {
      await _storage.delete(
        key: agentCodeKey,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      _logger.info("SecureStorage", "Agent code deleted");
    } catch (e, s) {
      _logger.error("SecureStorage", "Failed to delete agent code", e, s);
      rethrow;
    }
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll(
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
      _logger.info("SecureStorage", "All secure storage cleared");
    } catch (e, s) {
      _logger.error("SecureStorage", "Failed to clear secure storage", e, s);
      rethrow;
    }
  }

  // Write generic data
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(
        key: key, 
        value: value,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
    } catch (e, s) {
      _logger.error("SecureStorage", "Failed to write key: $key", e, s);
      rethrow;
    }
  }

  // Read generic data
  Future<String?> read(String key) async {
    try {
      return await _storage.read(
        key: key,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
    } catch (e, s) {
      _logger.error("SecureStorage", "Failed to read key: $key", e, s);
      return null;
    }
  }

  // Delete generic data
  Future<void> delete(String key) async {
    try {
      await _storage.delete(
        key: key,
        aOptions: _androidOptions,
        iOptions: _iosOptions,
      );
    } catch (e, s) {
      _logger.error("SecureStorage", "Failed to delete key: $key", e, s);
      rethrow;
    }
  }
}

final flutterSecureStorageProvider = Provider((ref) => const FlutterSecureStorage());

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  final storage = ref.watch(flutterSecureStorageProvider);
  final logger = ref.watch(loggerServiceProvider('SecureStorage'));
  return SecureStorageService(storage, logger);
});