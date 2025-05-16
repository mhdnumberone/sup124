// lib/presentation/encryption_tab/encryption_screen.dart
import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/encryption/aes_gcm_service.dart';
import '../../core/history/history_item.dart';
import '../../core/history/history_service.dart'; // هنا يتم استيراد HistoryService
import '../../core/logging/logger_service.dart';
import '../../core/steganography/zero_width_service.dart';
import '../../core/logging/logger_provider.dart'; // افترض أن هذا يوفر appLoggerProvider

// Providers
final aesGcmServiceProvider = Provider<AesGcmService>((ref) => AesGcmService());
final zeroWidthServiceProvider =
    Provider<ZeroWidthService>((ref) => ZeroWidthService());

// *** الإصلاح الرئيسي هنا للخطأ not_enough_positional_arguments ***
// افترض أن HistoryService يتطلب LoggerService. تأكد من أن appLoggerProvider يوفر LoggerService.
final historyServiceProvider = Provider<HistoryService>((ref) {
  final logger = ref.watch(appLoggerProvider); // احصل على الـ logger
  return HistoryService(logger); // مرر الـ logger إلى HistoryService
});
// إذا كان HistoryService لا يتطلب أي arguments الآن، يمكنك العودة إلى:
// final historyServiceProvider = Provider<HistoryService>((ref) => HistoryService());
// ولكن رسالة الخطأ تشير إلى أنه يتطلب argument.

// enum OperationMode, class EncryptionState (كما هي من قبل)
enum OperationMode {
  encrypt,
  decrypt,
  hide,
  reveal,
  encryptAndHide,
  revealAndDecrypt
}

class EncryptionState {
  final String secretInput;
  final String coverInput;
  final String passwordInput;
  final String outputText;
  final bool isLoading;
  final bool isPasswordVisible;
  final OperationMode operationMode;

  EncryptionState({
    this.secretInput = '',
    this.coverInput = '',
    this.passwordInput = '',
    this.outputText = '',
    this.isLoading = false,
    this.isPasswordVisible = false,
    this.operationMode = OperationMode.encrypt,
  });

  bool get useSteganography => _deriveUseSteganography(operationMode);
  bool get usePassword => _deriveUsePassword(operationMode);

  EncryptionState copyWith({
    String? secretInput,
    String? coverInput,
    String? passwordInput,
    String? outputText,
    bool? isLoading,
    bool? isPasswordVisible,
    OperationMode? operationMode,
  }) {
    final newOperationMode = operationMode ?? this.operationMode;
    return EncryptionState(
      secretInput: secretInput ?? this.secretInput,
      coverInput: coverInput ?? this.coverInput,
      passwordInput: passwordInput ?? this.passwordInput,
      outputText: outputText ?? this.outputText,
      isLoading: isLoading ?? this.isLoading,
      isPasswordVisible: isPasswordVisible ?? this.isPasswordVisible,
      operationMode: newOperationMode,
    );
  }

  static bool _deriveUseSteganography(OperationMode mode) {
    return mode == OperationMode.hide ||
        mode == OperationMode.reveal ||
        mode == OperationMode.encryptAndHide ||
        mode == OperationMode.revealAndDecrypt;
  }

  static bool _deriveUsePassword(OperationMode mode) {
    return mode == OperationMode.encrypt ||
        mode == OperationMode.decrypt ||
        mode == OperationMode.encryptAndHide ||
        mode == OperationMode.revealAndDecrypt;
  }
}

// class EncryptionNotifier (تستخدم historyServiceProvider المُعدّل)
class EncryptionNotifier extends StateNotifier<EncryptionState> {
  final AesGcmService _aesService;
  final ZeroWidthService _zwService;
  final HistoryService
      _historyService; // ستحصل على النسخة الصحيحة من خلال الـ provider
  final LoggerService _logger;

  EncryptionNotifier(
      this._aesService, this._zwService, this._historyService, this._logger)
      : super(EncryptionState());

  // ... (باقي دوال EncryptionNotifier كما هي: updateSecretInput, performOperation, etc.)
  // لا حاجة لتغييرها هنا لأنها تتلقى HistoryService كـ dependency
  void updateSecretInput(String value) =>
      state = state.copyWith(secretInput: value, outputText: '');
  void updateCoverInput(String value) =>
      state = state.copyWith(coverInput: value, outputText: '');
  void updatePasswordInput(String value) =>
      state = state.copyWith(passwordInput: value, outputText: '');
  void togglePasswordVisibility() =>
      state = state.copyWith(isPasswordVisible: !state.isPasswordVisible);

  void setOperationMode(OperationMode mode) {
    state = state.copyWith(operationMode: mode, outputText: '');
  }

  void resetFields() {
    state = state.copyWith(
      secretInput: '',
      coverInput: '',
      outputText: '',
      isLoading: false,
    );
  }

  Future<void> performOperation() async {
    state = state.copyWith(isLoading: true, outputText: '');
    String result = '';
    OperationType historyOpType = OperationType.encryptAes;
    String inputForHistory = state.secretInput;
    String? historyCover =
        state.coverInput.isNotEmpty ? state.coverInput : null;
    bool historyUsedPassword = state.usePassword;
    bool historyUsedStego = state.useSteganography;

    _logger.info("performOperation",
        "Mode: ${state.operationMode}, UsePwd: $historyUsedPassword, UseStego: $historyUsedStego");

    try {
      final secret = state.secretInput.trim();
      final cover = state.coverInput.trim();
      final password = state.passwordInput;

      if (secret.isEmpty) {
        throw Exception('يرجى إدخال النص المطلوب.');
      }
      if (historyUsedPassword && password.isEmpty) {
        throw Exception('كلمة المرور مطلوبة لهذه العملية.');
      }
      if ((state.operationMode == OperationMode.hide ||
              state.operationMode == OperationMode.encryptAndHide) &&
          cover.isEmpty) {
        throw Exception('نص الغطاء مطلوب عند استخدام الإخفاء.');
      }

      switch (state.operationMode) {
        case OperationMode.encrypt:
          historyOpType = OperationType.encryptAes;
          result = await _aesService.encryptWithPassword(secret, password);
          break;
        case OperationMode.decrypt:
          historyOpType = OperationType.decryptAes;
          result = await _aesService.decryptWithPassword(secret, password);
          break;
        case OperationMode.hide:
          historyOpType = OperationType.encodeZeroWidth;
          final zeroWidth = _zwService.encode(secret);
          result = _zwService.hideInCoverText(cover, zeroWidth);
          break;
        case OperationMode.reveal:
          historyOpType = OperationType.decodeZeroWidth;
          result = _zwService.extractFromText(secret);
          break;
        case OperationMode.encryptAndHide:
          historyOpType = OperationType.encryptThenHide;
          final encrypted =
              await _aesService.encryptWithPassword(secret, password);
          final zeroWidth = _zwService.encode(encrypted);
          result = _zwService.hideInCoverText(cover, zeroWidth);
          break;
        case OperationMode.revealAndDecrypt:
          historyOpType = OperationType.revealThenDecrypt;
          final extracted = _zwService.extractFromText(secret);
          result = await _aesService.decryptWithPassword(extracted, password);
          break;
      }
      state = state.copyWith(outputText: result, isLoading: false);
      _logger.info("performOperation",
          "Success. Output: ${result.substring(0, (result.length > 30 ? 30 : result.length))}...");

      await _historyService.addHistoryItem(HistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        operationType: historyOpType,
        originalInput: (historyOpType == OperationType.encryptAes ||
                historyOpType == OperationType.encodeZeroWidth ||
                historyOpType == OperationType.encryptThenHide ||
                historyOpType == OperationType.encryptFile ||
                historyOpType == OperationType.embedImageStego)
            ? inputForHistory
            : null,
        processedInput: (historyOpType == OperationType.decryptAes ||
                historyOpType == OperationType.decodeZeroWidth ||
                historyOpType == OperationType.revealThenDecrypt ||
                historyOpType == OperationType.decryptFile ||
                historyOpType == OperationType.extractImageStego)
            ? inputForHistory
            : null,
        coverText: historyCover,
        output: result,
        usedPassword: historyUsedPassword,
        usedSteganography: historyUsedStego,
      ));
    } on SecretBoxAuthenticationError {
      _logger.warn("performOperation",
          "Authentication failed (wrong password/tampered)");
      state = state.copyWith(
        outputText:
            "❌ خطأ: فشل فك التشفير. كلمة المرور خاطئة أو البيانات تالفة.",
        isLoading: false,
      );
    } catch (e, stackTrace) {
      _logger.error("performOperation", "Operation Error", e, stackTrace);
      state = state.copyWith(
        outputText: "❌ خطأ: ${e.toString().replaceFirst("Exception: ", "")}",
        isLoading: false,
      );
    }
  }
}

// encryptionScreenProvider (يستخدم Providers المُعدّلة)
final encryptionScreenProvider =
    StateNotifierProvider<EncryptionNotifier, EncryptionState>((ref) {
  return EncryptionNotifier(
    ref.watch(aesGcmServiceProvider),
    ref.watch(zeroWidthServiceProvider),
    ref.watch(historyServiceProvider), // سيحصل على النسخة الصحيحة
    ref.watch(appLoggerProvider),
  );
});

// class EncryptionScreen (Widget - كما هي من قبل)
class EncryptionScreen extends ConsumerWidget {
  const EncryptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ... (الكود الخاص بالـ UI لا يتغير هنا)
    // يمكنك استخدام نفس الكود الذي قدمته في الأسئلة السابقة لجزء الواجهة (build method)
    // سأقوم بإعادة لصق الكود الخاص بالواجهة من رد سابق للكمال:
    final state = ref.watch(encryptionScreenProvider);
    final notifier = ref.read(encryptionScreenProvider.notifier);
    final theme = Theme.of(context);

    bool showCoverInput = state.operationMode == OperationMode.hide ||
        state.operationMode == OperationMode.encryptAndHide;
    bool showPasswordInputAndSwitch = state.usePassword;

    String secretInputLabel = 'النص الأصلي لإدخاله';
    String secretInputHint = 'أدخل النص هنا...';
    if (state.operationMode == OperationMode.decrypt ||
        state.operationMode == OperationMode.reveal ||
        state.operationMode == OperationMode.revealAndDecrypt) {
      secretInputLabel = 'النص المُدخل (المشفر أو المخفي)';
      secretInputHint = 'الصق النص هنا...';
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildOperationModeSelector(context, state, notifier),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        secretInputLabel,
                        style: GoogleFonts.cairo(
                            textStyle: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: TextEditingController(
                            text: state.secretInput)
                          ..selection = TextSelection.fromPosition(
                              TextPosition(offset: state.secretInput.length)),
                        onChanged: notifier.updateSecretInput,
                        style: GoogleFonts.cairo(fontSize: 15),
                        maxLines: 4,
                        minLines: 2,
                        decoration: InputDecoration(
                          hintText: secretInputHint,
                          hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                          prefixIcon: Icon(
                              state.operationMode == OperationMode.decrypt ||
                                      state.operationMode ==
                                          OperationMode.reveal ||
                                      state.operationMode ==
                                          OperationMode.revealAndDecrypt
                                  ? Icons.lock_open_rounded
                                  : Icons.edit_document,
                              color: theme.iconTheme.color?.withOpacity(0.7)),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      if (showCoverInput) ...[
                        const SizedBox(height: 16),
                        Text(
                          'نص الغطاء (للإخفاء ضمنه)',
                          style: GoogleFonts.cairo(
                              textStyle: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: TextEditingController(
                              text: state.coverInput)
                            ..selection = TextSelection.fromPosition(
                                TextPosition(offset: state.coverInput.length)),
                          onChanged: notifier.updateCoverInput,
                          style: GoogleFonts.cairo(fontSize: 15),
                          maxLines: 3,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText:
                                'أدخل نص الغطاء الظاهر الذي سيتم إخفاء البيانات بداخله...',
                            hintStyle:
                                GoogleFonts.cairo(color: Colors.grey[500]),
                            prefixIcon: Icon(Icons.text_snippet_outlined,
                                color: theme.iconTheme.color?.withOpacity(0.7)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (showPasswordInputAndSwitch)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const ValueKey('encryption_settings_tile'),
                      initiallyExpanded: true,
                      leading:
                          Icon(Icons.key_outlined, color: theme.primaryColor),
                      title: Text('إعدادات كلمة المرور (AES-GCM)',
                          style: GoogleFonts.cairo(
                              textStyle: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600))),
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                          child: TextField(
                            controller:
                                TextEditingController(text: state.passwordInput)
                                  ..selection = TextSelection.fromPosition(
                                      TextPosition(
                                          offset: state.passwordInput.length)),
                            onChanged: notifier.updatePasswordInput,
                            obscureText: !state.isPasswordVisible,
                            style: GoogleFonts.cairo(
                                fontSize: 16, letterSpacing: 1),
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              labelStyle: GoogleFonts.cairo(),
                              hintText: 'أدخل كلمة مرور قوية هنا',
                              hintStyle:
                                  GoogleFonts.cairo(color: Colors.grey[500]),
                              suffixIcon: IconButton(
                                icon: Icon(
                                    state.isPasswordVisible
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: theme.iconTheme.color
                                        ?.withOpacity(0.7)),
                                onPressed: notifier.togglePasswordVisibility,
                              ),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : _getOperationIconWidget(state.operationMode),
                label: Text(
                  state.isLoading
                      ? 'جاري المعالجة...'
                      : _getOperationButtonText(state.operationMode),
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                onPressed: state.isLoading
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        await notifier.performOperation();
                        if (!context.mounted) return;

                        final currentState = ref.read(encryptionScreenProvider);
                        if (!currentState.isLoading &&
                            (currentState.outputText.isNotEmpty &&
                                !currentState.outputText.startsWith('❌'))) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('✅ تمت العملية بنجاح!',
                                    style: GoogleFonts.cairo()),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: Colors.green[700],
                                duration: const Duration(seconds: 2)),
                          );
                        } else if (currentState.outputText.startsWith('❌')) {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('حدث خطأ في العملية',
                                  style: GoogleFonts.cairo()),
                              content: Text(
                                  currentState.outputText.substring(2),
                                  style: GoogleFonts.cairo()),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text('حسنًا',
                                      style: GoogleFonts.cairo(
                                          color: theme.primaryColor)),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 3,
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              if (state.outputText.isNotEmpty)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: state.outputText.startsWith('❌')
                      ? Colors.red.withOpacity(0.05)
                      : theme.colorScheme.surfaceContainerHighest
                          .withOpacity(0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              state.outputText.startsWith('❌')
                                  ? 'رسالة خطأ'
                                  : 'النتيجة',
                              style: GoogleFonts.cairo(
                                textStyle:
                                    theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: state.outputText.startsWith('❌')
                                      ? Colors.red.shade700
                                      : theme.textTheme.titleMedium?.color,
                                ),
                              ),
                            ),
                            if (!state.outputText.startsWith('❌'))
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.copy_all_outlined,
                                        size: 22),
                                    tooltip: 'نسخ النتيجة',
                                    color:
                                        theme.iconTheme.color?.withOpacity(0.8),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(
                                          text: state.outputText));
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '✅ تم نسخ النتيجة إلى الحافظة.',
                                                style: GoogleFonts.cairo()),
                                            behavior: SnackBarBehavior.floating,
                                            backgroundColor: Colors.green[700],
                                            duration:
                                                const Duration(seconds: 2)),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.share_outlined,
                                        size: 22),
                                    tooltip: 'مشاركة النتيجة',
                                    color:
                                        theme.iconTheme.color?.withOpacity(0.8),
                                    onPressed: () {
                                      Share.share(state.outputText);
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          state.outputText.startsWith('❌')
                              ? state.outputText.substring(2)
                              : state.outputText,
                          style: GoogleFonts.cairo(
                            textStyle: TextStyle(
                              fontSize: 14.5,
                              color: state.outputText.startsWith('❌')
                                  ? Colors.red.shade800
                                  : theme.textTheme.bodyMedium?.color,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: Text("إعادة تعيين الحقول", style: GoogleFonts.cairo()),
                onPressed: notifier.resetFields,
                style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ... (دوال الواجهة المساعدة: _getOperationButtonText, _getOperationIconWidget, etc. كما هي)
  String _getOperationButtonText(OperationMode mode) {
    switch (mode) {
      case OperationMode.encrypt:
        return 'تشفير النص';
      case OperationMode.decrypt:
        return 'فك تشفير النص';
      case OperationMode.hide:
        return 'إخفاء النص';
      case OperationMode.reveal:
        return 'كشف النص';
      case OperationMode.encryptAndHide:
        return 'تشفير ثم إخفاء';
      case OperationMode.revealAndDecrypt:
        return 'كشف ثم فك تشفير';
    }
  }

  Widget _getOperationIconWidget(OperationMode mode) {
    switch (mode) {
      case OperationMode.encrypt:
        return const Icon(Icons.enhanced_encryption_rounded);
      case OperationMode.decrypt:
        return const Icon(Icons.lock_open_rounded);
      case OperationMode.hide:
        return const Icon(Icons.visibility_off_rounded);
      case OperationMode.reveal:
        return const Icon(Icons.visibility_rounded);
      case OperationMode.encryptAndHide:
        return const Icon(Icons.shield_moon_rounded);
      case OperationMode.revealAndDecrypt:
        return const Icon(Icons.key_rounded);
    }
  }

  Widget _buildOperationModeSelector(BuildContext context,
      EncryptionState state, EncryptionNotifier notifier) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اختر العملية المطلوبة:',
          style: GoogleFonts.cairo(
              textStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<OperationMode>(
          value: state.operationMode,
          style: GoogleFonts.cairo(
              color: theme.textTheme.bodyLarge?.color, fontSize: 15),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.tune_outlined,
                color: theme.iconTheme.color?.withOpacity(0.7)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            fillColor:
                theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            filled: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down_circle_outlined,
              color: theme.iconTheme.color?.withOpacity(0.7)),
          dropdownColor: theme.cardColor,
          items: OperationMode.values.map((OperationMode mode) {
            return DropdownMenuItem<OperationMode>(
              value: mode,
              child:
                  Text(_getOperationMenuText(mode), style: GoogleFonts.cairo()),
            );
          }).toList(),
          onChanged: (OperationMode? newValue) {
            if (newValue != null) {
              notifier.setOperationMode(newValue);
            }
          },
        ),
      ],
    );
  }

  String _getOperationMenuText(OperationMode mode) {
    switch (mode) {
      case OperationMode.encrypt:
        return 'تشفير (AES-GCM)';
      case OperationMode.decrypt:
        return 'فك تشفير (AES-GCM)';
      case OperationMode.hide:
        return 'إخفاء (Zero-Width)';
      case OperationMode.reveal:
        return 'كشف (Zero-Width)';
      case OperationMode.encryptAndHide:
        return 'تشفير ثم إخفاء';
      case OperationMode.revealAndDecrypt:
        return 'كشف ثم فك تشفير';
    }
  }
}
