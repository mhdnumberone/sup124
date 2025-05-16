// import 'dart:async'; // Added for Timer (clipboard clearing)

// import 'package:cryptography/cryptography.dart'; // Import for SecretBoxAuthenticationError
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:google_fonts/google_fonts.dart'; // Use Google Fonts
// import 'package:share_plus/share_plus.dart';

// // Import centralized providers
// import '../../core/encryption/aes_gcm_service.dart';
// import '../../core/history/history_item.dart';
// import '../../core/history/history_service.dart';
// import '../../core/steganography/zero_width_service.dart';

// // Provider for ZeroWidthService (keep here if only used in this tab, or centralize if used elsewhere)
// final zeroWidthServiceProvider = Provider((ref) => ZeroWidthService());

// // Enum for the selected operation mode
// enum OperationMode {
//   encrypt,
//   decrypt,
//   hide,
//   reveal,
//   encryptAndHide,
//   revealAndDecrypt
// }

// // StateNotifier for the Encryption Tab's state
// class EncryptionState {
//   final String secretInput;
//   final String coverInput;
//   final String passwordInput;
//   final String outputText;
//   final bool isLoading;
//   final bool usePassword;
//   final bool isPasswordVisible;
//   final OperationMode operationMode;
//   final bool useSteganography;

//   EncryptionState({
//     this.secretInput = '',
//     this.coverInput = '',
//     this.passwordInput = '',
//     this.outputText = '',
//     this.isLoading = false,
//     this.usePassword = true, // Default to using password for encryption
//     this.isPasswordVisible = false,
//     this.operationMode = OperationMode.encrypt, // Default mode
//     this.useSteganography = false, // Default to not using steganography
//   });

//   EncryptionState copyWith({
//     String? secretInput,
//     String? coverInput,
//     String? passwordInput,
//     String? outputText,
//     bool? isLoading,
//     bool? usePassword,
//     bool? isPasswordVisible,
//     OperationMode? operationMode,
//     bool? useSteganography,
//   }) {
//     return EncryptionState(
//       secretInput: secretInput ?? this.secretInput,
//       coverInput: coverInput ?? this.coverInput,
//       passwordInput: passwordInput ?? this.passwordInput,
//       outputText: outputText ?? this.outputText,
//       isLoading: isLoading ?? this.isLoading,
//       usePassword: usePassword ?? this.usePassword,
//       isPasswordVisible: isPasswordVisible ?? this.isPasswordVisible,
//       operationMode: operationMode ?? this.operationMode,
//       useSteganography: useSteganography ?? this.useSteganography,
//     );
//   }
// }

// class EncryptionNotifier extends StateNotifier<EncryptionState> {
//   final AesGcmService _aesService;
//   final ZeroWidthService _zwService;
//   final HistoryService _historyService;

//   EncryptionNotifier(this._aesService, this._zwService, this._historyService)
//       : super(EncryptionState());

//   // Update input fields
//   void updateSecretInput(String value) =>
//       state = state.copyWith(secretInput: value);
//   void updateCoverInput(String value) =>
//       state = state.copyWith(coverInput: value);
//   void updatePasswordInput(String value) =>
//       state = state.copyWith(passwordInput: value);

//   // Toggle password visibility
//   void togglePasswordVisibility() =>
//       state = state.copyWith(isPasswordVisible: !state.isPasswordVisible);

//   // Toggle password usage
//   void toggleUsePassword(bool value) =>
//       state = state.copyWith(usePassword: value);

//   // Toggle steganography usage
//   void toggleUseSteganography(bool value) =>
//       state = state.copyWith(useSteganography: value);

//   // Change operation mode
//   void setOperationMode(OperationMode mode) =>
//       state = state.copyWith(operationMode: mode);

//   // Reset fields
//   void resetFields() {
//     state = state.copyWith(
//       secretInput: '',
//       coverInput: '',
//       passwordInput: '',
//       outputText: '',
//       isLoading: false,
//     );
//   }

//   // Perform the selected operation
//   Future<void> performOperation() async {
//     state = state.copyWith(isLoading: true, outputText: '');
//     String result = '';
//     OperationType historyOpType = OperationType.encryptAes; // Default
//     String historyInput = state.secretInput;
//     String? historyCover = state.coverInput;
//     bool historyUsedPassword = state.usePassword;
//     bool historyUsedStego = state.useSteganography;

//     try {
//       final secret = state.secretInput.trim();
//       final cover = state.coverInput.trim();
//       final password =
//           state.passwordInput; // No trim, spaces might be intentional

//       // Input validation
//       if (secret.isEmpty) {
//         throw Exception('يرجى إدخال النص المطلوب.');
//       }
//       if (state.usePassword &&
//           password.isEmpty &&
//           (state.operationMode == OperationMode.encrypt ||
//               state.operationMode == OperationMode.decrypt ||
//               state.operationMode == OperationMode.encryptAndHide ||
//               state.operationMode == OperationMode.revealAndDecrypt)) {
//         throw Exception('كلمة المرور مطلوبة لهذه العملية.');
//       }
//       if (state.useSteganography &&
//           cover.isEmpty &&
//           (state.operationMode == OperationMode.hide ||
//               state.operationMode == OperationMode.encryptAndHide)) {
//         throw Exception('نص الغطاء مطلوب عند استخدام الإخفاء.');
//       }

//       switch (state.operationMode) {
//         case OperationMode.encrypt:
//           historyOpType = OperationType.encryptAes;
//           result = await _aesService.encryptWithPassword(secret, password);
//           break;
//         case OperationMode.decrypt:
//           historyOpType = OperationType.decryptAes;
//           result = await _aesService.decryptWithPassword(secret, password);
//           break;
//         case OperationMode.hide:
//           historyOpType = OperationType.encodeZeroWidth;
//           final zeroWidth = _zwService.encode(secret);
//           result = _zwService.hideInCoverText(cover, zeroWidth);
//           historyUsedPassword = false; // No password for pure stego
//           break;
//         case OperationMode.reveal:
//           historyOpType = OperationType.decodeZeroWidth;
//           result = _zwService.extractFromText(secret);
//           historyUsedPassword = false;
//           break;
//         case OperationMode.encryptAndHide:
//           historyOpType = OperationType.encryptThenHide;
//           final encrypted =
//               await _aesService.encryptWithPassword(secret, password);
//           final zeroWidth = _zwService.encode(encrypted);
//           result = _zwService.hideInCoverText(cover, zeroWidth);
//           break;
//         case OperationMode.revealAndDecrypt:
//           historyOpType = OperationType.revealThenDecrypt;
//           final extracted = _zwService.extractFromText(secret);
//           result = await _aesService.decryptWithPassword(extracted, password);
//           break;
//       }

//       state = state.copyWith(outputText: result, isLoading: false);

//       // Add to history
//       await _historyService.addHistoryItem(HistoryItem(
//         id: DateTime.now().millisecondsSinceEpoch.toString(),
//         timestamp: DateTime.now(),
//         operationType: historyOpType,
//         originalInput: historyInput,
//         coverText: historyCover,
//         output: result,
//         usedPassword: historyUsedPassword,
//         usedSteganography: historyUsedStego,
//       ));
//     } on SecretBoxAuthenticationError {
//       print(
//           "Operation Error: Authentication failed (wrong password or data tampered)");
//       state = state.copyWith(
//         outputText:
//             "❌ خطأ: فشل فك التشفير. كلمة المرور خاطئة أو البيانات تالفة.",
//         isLoading: false,
//       );
//       throw Exception("Decryption failed: Wrong password or data corrupted.");
//     } catch (e) {
//       print("Operation Error: $e");
//       state = state.copyWith(
//         outputText: "❌ خطأ: ${e.toString().replaceFirst("Exception: ", "")}",
//         isLoading: false,
//       );
//       throw Exception(e.toString().replaceFirst("Exception: ", ""));
//     }
//   }
// }

// // Provider for the EncryptionNotifier
// final encryptionProvider =
//     StateNotifierProvider<EncryptionNotifier, EncryptionState>((ref) {
//   return EncryptionNotifier(
//     ref.watch(aesGcmServiceProvider), // Use centralized provider
//     ref.watch(zeroWidthServiceProvider),
//     ref.watch(historyServiceProvider), // Use centralized provider
//   );
// });

// class EncryptionTab extends ConsumerWidget {
//   const EncryptionTab({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final state = ref.watch(encryptionProvider);
//     final notifier = ref.read(encryptionProvider.notifier);
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final theme = Theme.of(context);

//     // Determine which fields are visible based on the operation mode
//     bool showSecretInput = true; // Always shown, label changes
//     bool showCoverInput = state.operationMode == OperationMode.hide ||
//         state.operationMode == OperationMode.encryptAndHide;
//     bool showPasswordInput = state.usePassword &&
//         (state.operationMode == OperationMode.encrypt ||
//             state.operationMode == OperationMode.decrypt ||
//             state.operationMode == OperationMode.encryptAndHide ||
//             state.operationMode == OperationMode.revealAndDecrypt);
//     bool showUsePasswordSwitch = state.operationMode == OperationMode.encrypt ||
//         state.operationMode == OperationMode.decrypt ||
//         state.operationMode == OperationMode.encryptAndHide ||
//         state.operationMode == OperationMode.revealAndDecrypt;
//     bool showUseStegoSwitch = state.operationMode == OperationMode.encrypt ||
//         state.operationMode == OperationMode.hide ||
//         state.operationMode == OperationMode.encryptAndHide;

//     String secretInputLabel = 'النص الأصلي';
//     String secretInputHint = 'أدخل النص هنا...';
//     if (state.operationMode == OperationMode.decrypt ||
//         state.operationMode == OperationMode.reveal ||
//         state.operationMode == OperationMode.revealAndDecrypt) {
//       secretInputLabel = 'النص المُدخل (المشفر أو المخفي)';
//       secretInputHint = 'الصق النص هنا...';
//     }

//     return Directionality(
//       textDirection: TextDirection.rtl,
//       child: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.stretch,
//           children: [
//             // Operation Mode Selection
//             _buildOperationModeSelector(context, state, notifier),
//             const SizedBox(height: 16),

//             // Input Card
//             Card(
//               child: Padding(
//                 padding: const EdgeInsets.all(16.0),
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       secretInputLabel,
//                       style: GoogleFonts.cairo(
//                         // Apply Cairo font
//                         textStyle: theme.textTheme.titleMedium
//                             ?.copyWith(fontWeight: FontWeight.bold),
//                       ),
//                     ),
//                     const SizedBox(height: 8),
//                     TextField(
//                       controller: TextEditingController(text: state.secretInput)
//                         ..selection = TextSelection.fromPosition(
//                             TextPosition(offset: state.secretInput.length)),
//                       onChanged: notifier.updateSecretInput,
//                       style: GoogleFonts.cairo(), // Apply Cairo font
//                       maxLines: 4,
//                       decoration: InputDecoration(
//                         hintText: secretInputHint,
//                         hintStyle: GoogleFonts.cairo(), // Apply Cairo font
//                         prefixIcon: Icon(state.operationMode ==
//                                     OperationMode.decrypt ||
//                                 state.operationMode == OperationMode.reveal ||
//                                 state.operationMode ==
//                                     OperationMode.revealAndDecrypt
//                             ? Icons.lock_open_outlined
//                             : Icons.edit_note_outlined),
//                       ),
//                     ),
//                     if (showCoverInput) ...[
//                       const SizedBox(height: 16),
//                       Text(
//                         'نص الغطاء (للإخفاء)',
//                         style: GoogleFonts.cairo(
//                           // Apply Cairo font
//                           textStyle: theme.textTheme.titleMedium
//                               ?.copyWith(fontWeight: FontWeight.bold),
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       TextField(
//                         controller: TextEditingController(
//                             text: state.coverInput)
//                           ..selection = TextSelection.fromPosition(
//                               TextPosition(offset: state.coverInput.length)),
//                         onChanged: notifier.updateCoverInput,
//                         style: GoogleFonts.cairo(), // Apply Cairo font
//                         decoration: InputDecoration(
//                           hintText: 'أدخل نص الغطاء الظاهر...',
//                           hintStyle: GoogleFonts.cairo(), // Apply Cairo font
//                           prefixIcon: const Icon(Icons.text_fields_outlined),
//                         ),
//                       ),
//                     ],
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 16),

//             // Settings Card
//             Card(
//               child: Theme(
//                 data: theme.copyWith(
//                     dividerColor:
//                         Colors.transparent), // Hide divider in ExpansionTile
//                 child: ExpansionTile(
//                   initiallyExpanded: showPasswordInput ||
//                       showUsePasswordSwitch ||
//                       showUseStegoSwitch,
//                   leading:
//                       Icon(Icons.settings_outlined, color: theme.primaryColor),
//                   title: Text('الإعدادات المتقدمة',
//                       style: GoogleFonts.cairo(
//                           // Apply Cairo font
//                           textStyle: theme.textTheme.titleMedium
//                               ?.copyWith(fontWeight: FontWeight.bold))),
//                   children: [
//                     Padding(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 16.0, vertical: 8.0),
//                       child: Column(
//                         children: [
//                           if (showUsePasswordSwitch)
//                             SwitchListTile(
//                               title: Text('استخدام كلمة مرور (AES-GCM)',
//                                   style:
//                                       GoogleFonts.cairo()), // Apply Cairo font
//                               subtitle: Text('مُوصى به للتشفير القوي',
//                                   style:
//                                       GoogleFonts.cairo()), // Apply Cairo font
//                               value: state.usePassword,
//                               onChanged: notifier.toggleUsePassword,
//                               activeColor: theme.primaryColor,
//                               dense: true,
//                               contentPadding: EdgeInsets.zero,
//                             ),
//                           if (showPasswordInput) ...[
//                             const SizedBox(height: 8),
//                             TextField(
//                               controller: TextEditingController(
//                                   text: state.passwordInput)
//                                 ..selection = TextSelection.fromPosition(
//                                     TextPosition(
//                                         offset: state.passwordInput.length)),
//                               onChanged: notifier.updatePasswordInput,
//                               obscureText: !state.isPasswordVisible,
//                               style: GoogleFonts.cairo(), // Apply Cairo font
//                               decoration: InputDecoration(
//                                 labelText: 'كلمة المرور',
//                                 labelStyle:
//                                     GoogleFonts.cairo(), // Apply Cairo font
//                                 prefixIcon: const Icon(Icons.password_outlined),
//                                 suffixIcon: IconButton(
//                                   icon: Icon(state.isPasswordVisible
//                                       ? Icons.visibility_off_outlined
//                                       : Icons.visibility_outlined),
//                                   onPressed: notifier.togglePasswordVisibility,
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(height: 8),
//                             // Password Strength Checker (ensure it's compatible and styled)
//                             // PasswordStrengthChecker(
//                             //   passwordValue: state.passwordInput,
//                             //   strength: PasswordStrength.medium,
//                             // ),
//                           ],
//                           if (showUseStegoSwitch)
//                             SwitchListTile(
//                               title: Text('إخفاء باستخدام Zero-Width',
//                                   style:
//                                       GoogleFonts.cairo()), // Apply Cairo font
//                               subtitle: Text(
//                                   'إخفاء النص (أقل أمانًا من التشفير)',
//                                   style:
//                                       GoogleFonts.cairo()), // Apply Cairo font
//                               value: state.useSteganography,
//                               onChanged: notifier.toggleUseSteganography,
//                               activeColor: theme.primaryColor,
//                               dense: true,
//                               contentPadding: EdgeInsets.zero,
//                             ),
//                         ],
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//             const SizedBox(height: 24),

//             // Action Button
//             ElevatedButton.icon(
//               icon: state.isLoading
//                   ? const SizedBox(
//                       width: 20,
//                       height: 20,
//                       child: CircularProgressIndicator(
//                           strokeWidth: 2, color: Colors.white))
//                   : _getOperationIcon(state.operationMode),
//               label: Text(
//                 state.isLoading
//                     ? 'جاري المعالجة...'
//                     : _getOperationButtonText(state.operationMode),
//                 style: GoogleFonts.cairo(
//                     fontWeight: FontWeight.bold), // Apply Cairo font
//               ),
//               onPressed: state.isLoading
//                   ? null
//                   : () async {
//                       try {
//                         await notifier.performOperation();
//                         // Show success message via SnackBar
//                         if (context.mounted &&
//                             !state.isLoading &&
//                             !state.outputText.startsWith('❌')) {
//                           ScaffoldMessenger.of(context).showSnackBar(
//                             SnackBar(
//                                 content: Text('✅ تمت العملية بنجاح!',
//                                     style: GoogleFonts.cairo()),
//                                 duration: const Duration(seconds: 3)),
//                           );
//                         }
//                       } catch (e) {
//                         // Show error dialog
//                         if (context.mounted) {
//                           showDialog(
//                             context: context,
//                             builder: (context) => AlertDialog(
//                               title: Text('حدث خطأ',
//                                   style:
//                                       GoogleFonts.cairo()), // Apply Cairo font
//                               content: Text(e.toString(),
//                                   style:
//                                       GoogleFonts.cairo()), // Apply Cairo font
//                               actions: [
//                                 TextButton(
//                                   onPressed: () => Navigator.pop(context),
//                                   child: Text('حسنًا',
//                                       style: GoogleFonts
//                                           .cairo()), // Apply Cairo font
//                                 ),
//                               ],
//                             ),
//                           );
//                         }
//                       }
//                     },
//               style: ElevatedButton.styleFrom(
//                 padding: const EdgeInsets.symmetric(vertical: 14),
//               ),
//             ),
//             const SizedBox(height: 16),

//             // Output Card
//             if (state.outputText.isNotEmpty)
//               Card(
//                 color: state.outputText.startsWith('❌')
//                     ? Colors.red.shade50
//                     : (isDark ? theme.colorScheme.surface : Colors.grey[50]),
//                 child: Padding(
//                   padding: const EdgeInsets.all(16.0),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Text(
//                             state.outputText.startsWith('❌')
//                                 ? 'رسالة خطأ'
//                                 : 'النتيجة',
//                             style: GoogleFonts.cairo(
//                               // Apply Cairo font
//                               textStyle: theme.textTheme.titleMedium?.copyWith(
//                                 fontWeight: FontWeight.bold,
//                                 color: state.outputText.startsWith('❌')
//                                     ? Colors.red.shade700
//                                     : theme.textTheme.titleMedium?.color,
//                               ),
//                             ),
//                           ),
//                           if (!state.outputText.startsWith('❌'))
//                             Row(
//                               children: [
//                                 IconButton(
//                                   icon:
//                                       const Icon(Icons.copy_outlined, size: 20),
//                                   tooltip: 'نسخ النتيجة',
//                                   onPressed: () {
//                                     Clipboard.setData(
//                                         ClipboardData(text: state.outputText));
//                                     ScaffoldMessenger.of(context).showSnackBar(
//                                       SnackBar(
//                                           content: Text(
//                                               '✅ تم نسخ النتيجة إلى الحافظة.',
//                                               style: GoogleFonts.cairo()),
//                                           duration: const Duration(seconds: 2)),
//                                     );
//                                     // Clear clipboard after a delay (e.g., 60 seconds)
//                                     Timer(const Duration(seconds: 60), () {
//                                       Clipboard.getData(Clipboard.kTextPlain)
//                                           .then((value) {
//                                         if (value?.text == state.outputText) {
//                                           Clipboard.setData(
//                                               const ClipboardData(text: ''));
//                                           print(
//                                               "Clipboard cleared after 60 seconds.");
//                                         }
//                                       });
//                                     });
//                                   },
//                                 ),
//                                 IconButton(
//                                   icon: const Icon(Icons.share_outlined,
//                                       size: 20),
//                                   tooltip: 'مشاركة النتيجة',
//                                   onPressed: () {
//                                     Share.share(state.outputText);
//                                   },
//                                 ),
//                               ],
//                             ),
//                         ],
//                       ),
//                       const SizedBox(height: 10),
//                       // Animated Text for non-error output
//                       state.outputText.startsWith('❌')
//                           ? SelectableText(
//                               state.outputText
//                                   .substring(2), // Remove error marker
//                               style: GoogleFonts.cairo(
//                                 // Apply Cairo font
//                                 textStyle: TextStyle(
//                                     color: Colors.red.shade900, fontSize: 14),
//                               ),
//                             )
//                           : AnimatedSize(
//                               duration: const Duration(milliseconds: 300),
//                               child: SelectableText(
//                                 state.outputText,
//                                 style: GoogleFonts.cairo(
//                                   // Apply Cairo font
//                                   textStyle: TextStyle(
//                                     fontSize: 14,
//                                     color: isDark
//                                         ? Colors.grey[300]
//                                         : Colors.black87,
//                                     height: 1.5,
//                                   ),
//                                 ),
//                               ),
//                             ),
//                       // Example of AnimatedTextKit (can be used selectively)
//                       // AnimatedTextKit(
//                       //   animatedTexts: [
//                       //     TypewriterAnimatedText(
//                       //       state.outputText,
//                       //       textStyle: TextStyle(
//                       //         fontSize: 14.0,
//                       //         color: isDark ? Colors.grey[300] : Colors.black87,
//                       //       ),
//                       //       speed: const Duration(milliseconds: 50),
//                       //     ),
//                       //   ],
//                       //   totalRepeatCount: 1,
//                       //   displayFullTextOnTap: true,
//                       //   stopPauseOnTap: true,
//                       // ),
//                     ],
//                   ),
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   // Helper to get button text based on mode
//   String _getOperationButtonText(OperationMode mode) {
//     switch (mode) {
//       case OperationMode.encrypt:
//         return 'تشفير النص';
//       case OperationMode.decrypt:
//         return 'فك تشفير النص';
//       case OperationMode.hide:
//         return 'إخفاء النص (Zero-Width)';
//       case OperationMode.reveal:
//         return 'كشف النص (Zero-Width)';
//       case OperationMode.encryptAndHide:
//         return 'تشفير ثم إخفاء';
//       case OperationMode.revealAndDecrypt:
//         return 'كشف ثم فك تشفير';
//     }
//   }

//   // Helper to get icon based on mode
//   Icon _getOperationIcon(OperationMode mode) {
//     switch (mode) {
//       case OperationMode.encrypt:
//         return const Icon(Icons.enhanced_encryption_outlined);
//       case OperationMode.decrypt:
//         return const Icon(Icons.lock_open_outlined);
//       case OperationMode.hide:
//         return const Icon(Icons.visibility_off_outlined);
//       case OperationMode.reveal:
//         return const Icon(Icons.visibility_outlined);
//       case OperationMode.encryptAndHide:
//         return const Icon(Icons.security_outlined);
//       case OperationMode.revealAndDecrypt:
//         return const Icon(Icons.key_outlined);
//     }
//   }

//   // Helper widget for operation mode selection
//   Widget _buildOperationModeSelector(BuildContext context,
//       EncryptionState state, EncryptionNotifier notifier) {
//     final theme = Theme.of(context);
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'اختر العملية المطلوبة:',
//           style: GoogleFonts.cairo(
//             // Apply Cairo font
//             textStyle: theme.textTheme.titleMedium
//                 ?.copyWith(fontWeight: FontWeight.bold),
//           ),
//         ),
//         const SizedBox(height: 8),
//         DropdownButtonFormField<OperationMode>(
//           value: state.operationMode,
//           items: OperationMode.values.map((OperationMode mode) {
//             return DropdownMenuItem<OperationMode>(
//               value: mode,
//               child: Text(_getOperationMenuText(mode),
//                   style: GoogleFonts.cairo()), // Apply Cairo font
//             );
//           }).toList(),
//           onChanged: (OperationMode? newValue) {
//             if (newValue != null) {
//               notifier.setOperationMode(newValue);
//             }
//           },
//           decoration: const InputDecoration(
//             prefixIcon: Icon(Icons.settings_applications_outlined),
//             contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//           ),
//         ),
//       ],
//     );
//   }

//   // Helper to get dropdown menu text
//   String _getOperationMenuText(OperationMode mode) {
//     switch (mode) {
//       case OperationMode.encrypt:
//         return 'تشفير (AES-GCM)';
//       case OperationMode.decrypt:
//         return 'فك تشفير (AES-GCM)';
//       case OperationMode.hide:
//         return 'إخفاء (Zero-Width)';
//       case OperationMode.reveal:
//         return 'كشف (Zero-Width)';
//       case OperationMode.encryptAndHide:
//         return 'تشفير ثم إخفاء';
//       case OperationMode.revealAndDecrypt:
//         return 'كشف ثم فك تشفير';
//     }
//   }
// }
