// lib/presentation/chat/providers/auth_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/logger_provider.dart';
import '../../../core/security/secure_storage_service.dart';

const String agentCodeStorageKey = 'conduit_current_agent_code_v2';

final currentAgentCodeProvider = FutureProvider<String?>((ref) async {
  final secureStorage = ref.watch(secureStorageServiceProvider);
  final logger = ref.watch(appLoggerProvider);
  logger.info("currentAgentCodeProvider", "Attempting to read agent code");
  
  try {
    final agentCode = await secureStorage.readAgentCode();
    if (agentCode != null && agentCode.isNotEmpty) {
      logger.info("currentAgentCodeProvider", "Successfully read agent code");
      return agentCode;
    } else {
      logger.info("currentAgentCodeProvider", "No agent code found (null or empty)");
      return null;
    }
  } catch (e, stackTrace) {
    logger.error("currentAgentCodeProvider", "Error reading agent code", e, stackTrace);
    return null;
  }
});

final isLoggedInProvider = Provider<bool>((ref) {
  final agentCodeAsyncValue = ref.watch(currentAgentCodeProvider);
  return agentCodeAsyncValue.maybeWhen(
    data: (agentCode) => agentCode != null && agentCode.isNotEmpty,
    orElse: () => false,
  );
});

final secureStorageProviderForDecoy = secureStorageServiceProvider;

// Define AuthService class
class AuthService {
  final Ref _ref;
  AuthService(this._ref);

  Future<void> signOut() async {
    final logger = _ref.read(appLoggerProvider);
    final storage = _ref.read(secureStorageServiceProvider);
    try {
      await storage.deleteAgentCode();
      _ref.invalidate(currentAgentCodeProvider);
      // In a real app, you might also call Firebase Auth signOut or similar here.
      logger.info("AuthService", "User signed out, agent code deleted");
    } catch (e, s) {
      logger.error("AuthService", "Error during sign out", e, s);
      // Rethrow to allow callers to handle
      rethrow;
    }
  }

  // Add other auth methods here if needed, e.g., signIn, signUp
  Future<void> signIn(String agentCode) async {
    final logger = _ref.read(appLoggerProvider);
    final storage = _ref.read(secureStorageServiceProvider);
    try {
      await storage.writeAgentCode(agentCode);
      _ref.invalidate(currentAgentCodeProvider); // Invalidate to refetch
      logger.info("AuthService", "Agent code signed in and stored");
    } catch (e, s) {
      logger.error("AuthService", "Error during sign in", e, s);
      rethrow;
    }
  }
}

// Define and export authServiceProvider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref);
});