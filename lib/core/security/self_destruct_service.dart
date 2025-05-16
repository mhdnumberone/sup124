// lib/core/security/self_destruct_service.dart
import "dart:io";

import "package:cloud_firestore/cloud_firestore.dart"
    as firestore; // Import with prefix for clarity
import "package:cloud_firestore/cloud_firestore.dart"
    hide FieldValue; // Hide Sembast's FieldValue
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../../presentation/chat/providers/auth_providers.dart";
import "../../presentation/decoy_screen/decoy_screen.dart";
import "../history/history_service.dart";
import "../logging/logger_provider.dart";
import "../logging/logger_service.dart"; // Added for LoggerService type
import "secure_storage_service.dart"; // For flutterSecureStorageProvider

final selfDestructServiceProvider = Provider<SelfDestructService>((ref) {
  return SelfDestructService(ref);
});

class SelfDestructService {
  final Ref _ref;
  final FirebaseFirestore _firestoreInstance = FirebaseFirestore.instance;

  SelfDestructService(this._ref);

  Future<void> _secureWipeSembastDatabase(LoggerService logger) async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final dbPath =
          "${appDocDir.path}/the_conduit_app.db"; // Fixed prefer_interpolation_to_compose_strings
      final dbFile = File(dbPath);

      if (await dbFile.exists()) {
        logger.info("SelfDestructService",
            "Sembast DB found at $dbPath. Attempting secure wipe.");
        final fileSize = await dbFile.length();
        final randomData = List<int>.generate(fileSize, (index) => 0);

        final sink = dbFile.openWrite(mode: FileMode.writeOnly);
        sink.add(randomData);
        await sink.flush();
        await sink.close();
        logger.info(
            "SelfDestructService", "Sembast DB overwritten with zeros.");

        await dbFile.delete();
        logger.info("SelfDestructService",
            "Sembast DB file deleted after overwrite: $dbPath");
      } else {
        logger.info("SelfDestructService",
            "Sembast DB file not found at $dbPath. No wipe needed for Sembast.");
      }
    } catch (e, s) {
      logger.error(
          "SelfDestructService", "Error during Sembast DB secure wipe", e, s);
    }
  }

  Future<void> _clearSharedPreferences(LoggerService logger) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      logger.info("SelfDestructService", "SharedPreferences cleared.");
    } catch (e, s) {
      logger.error(
          "SelfDestructService", "Error clearing SharedPreferences", e, s);
    }
  }

  Future<void> _clearAppCacheAndSupportDirs(LoggerService logger) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (await cacheDir.exists()) {
        logger.info("SelfDestructService",
            "Clearing cache directory: ${cacheDir.path}");
        await cacheDir.delete(recursive: true);
      }

      final appSupportDir = await getApplicationSupportDirectory();
      if (await appSupportDir.exists()) {
        logger.info("SelfDestructService",
            "Clearing application support directory: ${appSupportDir.path}");
        await appSupportDir.delete(recursive: true);
      }
    } catch (e, s) {
      logger.error("SelfDestructService",
          "Error clearing app cache/support directories", e, s);
    }
  }

  Future<void> initiateSelfDestruct(BuildContext context,
      {String? triggeredBy, bool performLogout = true, bool showMessages = true}) async {
    final logger = _ref.read(appLoggerProvider);
    final secureStorageService = _ref.read(secureStorageServiceProvider);
    final currentAgentCode = await secureStorageService.readAgentCode();

    logger.error(
        "FULL SELF-DESTRUCT SEQUENCE INITIATED by: ${triggeredBy ?? 'Unknown'}. Agent: $currentAgentCode. Perform Logout: $performLogout. Show Messages: $showMessages",
        "SELF_DESTRUCT_SERVICE");

    // Capture BuildContext and mounted state before async gaps
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    bool isContextMounted() => context.mounted;

    if (showMessages && isContextMounted()) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('بدء تسلسل التدمير الذاتي الكامل للبيانات المحلية...',
              style: GoogleFonts.cairo(color: Colors.white)),
          backgroundColor: Colors.red.shade900,
          duration: const Duration(seconds: 3),
        ),
      );
    }
    
    if (showMessages) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      if (currentAgentCode != null && currentAgentCode.isNotEmpty) {
        logger.info("SelfDestructService",
            "Marking server-side conversations as deleted for agent: $currentAgentCode");
        final conversationsSnapshot = await _firestoreInstance
            .collection('conversations')
            .where('participants', arrayContains: currentAgentCode)
            .get();

        logger.info("SelfDestructService",
            "Found ${conversationsSnapshot.docs.length} conversations to mark as deleted for agent $currentAgentCode.");
        WriteBatch batch = _firestoreInstance.batch();
        for (final convDoc in conversationsSnapshot.docs) {
          batch.update(convDoc.reference, {
            'deletedForUsers.$currentAgentCode': true,
            'updatedAt': firestore.FieldValue
                .serverTimestamp() // Use prefixed FieldValue
          });
        }
        await batch.commit();
        logger.info("SelfDestructService",
            "Finished batch marking conversations as deleted for agent $currentAgentCode.");
      } else {
        logger.warn("SelfDestructService",
            "No agent code found. Skipping server-side data marking.");
      }

      final historyService = _ref.read(historyServiceProvider);
      await historyService.clearHistory();
      logger.info("SelfDestructService", "Cleared local history.");

      await _secureWipeSembastDatabase(logger);
      await secureStorageService.deleteAll();
      logger.info("SelfDestructService", "Cleared FlutterSecureStorage.");
      await _clearSharedPreferences(logger);
      await _clearAppCacheAndSupportDirs(logger);
      logger.info(
          "SelfDestructService", "Cleared app cache and support directories.");

      if (performLogout) {
        final authService = _ref.read(authServiceProvider);
        await authService.signOut();
        logger.info("SelfDestructService", "User signed out from Firebase.");
        _ref.invalidate(currentAgentCodeProvider);
      } else {
        logger.info("SelfDestructService",
            "Skipped logout as per performLogout=false.");
      }

      logger.error(
          "FULL LOCAL DATA SELF-DESTRUCT SEQUENCE COMPLETED. Triggered by: ${triggeredBy ?? 'Unknown'}. Logout performed: $performLogout",
          "SELF_DESTRUCT_SERVICE");

      if (showMessages && isContextMounted()) {
        scaffoldMessenger.removeCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
                performLogout
                    ? 'تم تدمير جميع البيانات المحلية بنجاح وتم تسجيل الخروج.'
                    : 'تم تدمير جميع البيانات المحلية بنجاح.',
                style: GoogleFonts.cairo(color: Colors.white)),
            backgroundColor: Colors.black,
            duration: const Duration(seconds: 4),
          ),
        );
        await Future.delayed(const Duration(seconds: 1));
      }
      
      if (isContextMounted()) {
        if (performLogout) {
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => const DecoyScreen(isPostDestruct: true)),
            (route) => false,
          );
        } else {
          logger.info("SelfDestructService",
              "Full self-destruct complete, user remains logged in (if applicable, though unlikely for this scenario).");
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (_) => const DecoyScreen(isPostDestruct: true)),
            (route) => false,
          );
        }
      }
    } catch (e, s) {
      logger.error("SelfDestructService",
          "Error during full self-destruct sequence", e, s);
      if (showMessages && isContextMounted()) {
        scaffoldMessenger.removeCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
                'حدث خطأ أثناء تدمير البيانات المحلية. قد لا تكون جميع البيانات قد مُسحت.',
                style: GoogleFonts.cairo()),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      
      if (performLogout) {
        try {
          final authService = _ref.read(authServiceProvider);
          await authService.signOut();
          await _ref.read(secureStorageServiceProvider).deleteAll();
          await _clearSharedPreferences(logger);
          _ref.invalidate(currentAgentCodeProvider);
          if (isContextMounted()) {
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => const DecoyScreen(isPostDestruct: true)),
              (route) => false,
            );
          }
        } catch (finalError, finalStackTrace) {
          logger.error("SelfDestructService", "Error during fallback cleanup",
              finalError, finalStackTrace);
        }
      }
    }
  }
}