// lib/presentation/image_stego_tab/image_stego_screen.dart
import 'dart:convert'; // لا يزال مطلوبًا لـ utf8
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path; // لا يزال مطلوبًا
import 'package:share_plus/share_plus.dart';

import '../../core/encryption/aes_gcm_service.dart';
import '../../core/history/history_item.dart';
import '../../core/history/history_service.dart';
import '../../core/logging/logger_provider.dart'; // << لاستخدام appLoggerProvider
// import '../../core/logging/logger_service.dart'; // لا حاجة له إذا استخدمنا appLoggerProvider أو loggerServiceProvider
import '../../core/logging/logger_service.dart';
import '../../core/steganography/image_steganography_service.dart';
import '../../core/utils/file_saver.dart';

final imageStegoServiceProvider = Provider<ImageSteganographyService>((ref) {
  // final logger = ref.watch(loggerServiceProvider("ImageSteganographyService"));
  // return ImageSteganographyService(logger);
  return ImageSteganographyService(); // حاليًا بدون logger داخلي
});

enum ImageStegoMode { embed, extract }

class ImageStegoState {
  final PlatformFile? imageFile;
  final String textToEmbed;
  final String extractedText;
  final String outputMessage;
  final bool isLoading;
  final double progress;
  final String password; // كلمة المرور لتشفير النص قبل الإخفاء
  final ImageStegoMode operationMode;

  ImageStegoState({
    this.imageFile,
    this.textToEmbed = '',
    this.extractedText = '',
    this.outputMessage = '',
    this.isLoading = false,
    this.progress = 0.0,
    this.operationMode = ImageStegoMode.embed,
    this.password = '',
  });

  ImageStegoState copyWith({
    PlatformFile? imageFile,
    String? textToEmbed,
    String? extractedText,
    String? outputMessage,
    bool? isLoading,
    double? progress,
    String? password,
    ImageStegoMode? operationMode,
    bool clearImageFile = false,
  }) {
    return ImageStegoState(
      imageFile: clearImageFile ? null : imageFile ?? this.imageFile,
      textToEmbed: textToEmbed ?? this.textToEmbed,
      extractedText: extractedText ?? this.extractedText,
      outputMessage: outputMessage ?? this.outputMessage,
      isLoading: isLoading ?? this.isLoading,
      progress: progress ?? this.progress,
      password: password ?? this.password,
      operationMode: operationMode ?? this.operationMode,
    );
  }
}

class ImageStegoNotifier extends StateNotifier<ImageStegoState> {
  final ImageSteganographyService _stegoService;
  final HistoryService _historyService;
  final AesGcmService _aesService;
  final LoggerService _logger; // <<<< أضف هذا

  ImageStegoNotifier(
    this._stegoService,
    this._historyService,
    this._aesService,
    this._logger, // <<<< أضف هذا
  ) : super(ImageStegoState());

  void setOperationMode(ImageStegoMode mode) => state = state.copyWith(
      operationMode: mode,
      outputMessage: '',
      extractedText: '',
      imageFile: null,
      progress: 0.0);
  void updateTextToEmbed(String value) =>
      state = state.copyWith(textToEmbed: value);
  void updatePassword(String value) => state = state.copyWith(password: value);

  void resetState() {
    state = state.copyWith(
      clearImageFile: true,
      textToEmbed: '',
      extractedText: '',
      outputMessage: '',
      isLoading: false,
      progress: 0.0,
      // password: '', // إبقاء كلمة المرور قد يكون مفيدًا للمستخدم
    );
  }

  Future<void> pickImage() async {
    state = state.copyWith(
        outputMessage: '', extractedText: ''); // مسح الرسائل السابقة
    try {
      _logger.info("pickImage", "Attempting to pick image.");
      FilePickerResult? result =
          await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.isNotEmpty) {
        _logger.info("pickImage", "Image picked: ${result.files.first.name}");
        state = state.copyWith(imageFile: result.files.first);
      } else {
        _logger.info("pickImage", "Image picking cancelled by user.");
        state = state.copyWith(outputMessage: 'لم يتم اختيار أي صورة.');
      }
    } catch (e, stackTrace) {
      _logger.error("pickImage", "Error picking image", e, stackTrace);
      state = state.copyWith(
          outputMessage: '❌ خطأ أثناء اختيار الصورة: ${e.toString()}');
    }
  }

  Future<void> performImageStegoOperation() async {
    if (state.imageFile == null) {
      state = state.copyWith(outputMessage: '❌ يرجى اختيار صورة أولاً.');
      return;
    }
    if (state.operationMode == ImageStegoMode.embed &&
        state.textToEmbed.isEmpty) {
      state = state.copyWith(outputMessage: '❌ يرجى إدخال النص المراد إخفاؤه.');
      return;
    }
    if (state.password.isEmpty) {
      // كلمة المرور مطلوبة دائمًا (لتشفير النص قبل الإخفاء)
      state = state.copyWith(outputMessage: '❌ يرجى إدخال كلمة مرور.');
      return;
    }

    state = state.copyWith(
        isLoading: true,
        outputMessage: 'جاري التهيئة...',
        progress: 0.0,
        extractedText: '');
    _logger.info("performImageStegoOperation",
        "Starting. Mode: ${state.operationMode}, Image: ${state.imageFile!.name}");

    try {
      final imageFile = state.imageFile!;
      final inputImageName = imageFile.name;
      final imageBytes = imageFile.bytes;

      if (imageBytes == null) {
        _logger.error("performImageStegoOperation",
            "Image bytes are null for ${imageFile.name}.");
        throw Exception("لا يمكن قراءة بيانات الصورة المختارة.");
      }
      _logger.debug("performImageStegoOperation",
          "Image bytes length: ${imageBytes.length}");

      final isEmbedding = state.operationMode == ImageStegoMode.embed;

      if (isEmbedding) {
        final textToEmbed = state.textToEmbed.trim();
        _logger.info("performImageStegoOperation",
            "Embedding text: '${textToEmbed.substring(0, min(10, textToEmbed.length))}...'");

        state = state.copyWith(
            outputMessage: '1/3: جاري تشفير النص...', progress: 0.1);
        final plainBytes = utf8.encode(textToEmbed); // تحويل النص إلى بايتات
        final encryptedBytes = await _aesService.encryptBytesWithPassword(
            plainBytes, state.password);
        _logger.debug("performImageStegoOperation",
            "Encrypted bytes length: ${encryptedBytes.length}");

        state = state.copyWith(
            outputMessage: '2/3: جاري إخفاء النص المشفر...', progress: 0.4);
        final resultBytesWithHiddenData =
            await _stegoService.embedBytesInImage(imageBytes, encryptedBytes);
        _logger.info("performImageStegoOperation",
            "Embedding complete. Result image bytes length: ${resultBytesWithHiddenData.length}");

        final outputFileName =
            '${path.basenameWithoutExtension(inputImageName)}_stego.png'; // يُفضل PNG للإخفاء بدون فقدان

        state = state.copyWith(
            outputMessage: '3/3: جاري حفظ الصورة الناتجة...', progress: 0.8);
        // استخدام FileSaver (يفترض أنه للويب حاليًا)
        await FileSaver.saveFile(
            bytes: resultBytesWithHiddenData,
            suggestedFileName: outputFileName);
        _logger.info(
            "performImageStegoOperation", "Image saved as: $outputFileName");

        state = state.copyWith(
            isLoading: false,
            outputMessage:
                '✅ تم إخفاء النص وتشفيره وحفظ الصورة بنجاح باسم: $outputFileName',
            progress: 1.0);

        await _historyService.addHistoryItem(HistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          operationType: OperationType.embedImageStego,
          originalInput: textToEmbed, // النص الأصلي
          coverText: "صورة: $inputImageName", // اسم صورة الغطاء
          output: "الصورة الناتجة: $outputFileName",
          usedPassword: true, // استخدمنا كلمة مرور للتشفير
          usedSteganography: true,
        ));
      } else {
        // Extracting
        _logger.info("performImageStegoOperation",
            "Extracting text from image: $inputImageName");
        state = state.copyWith(
            outputMessage: '1/2: جاري استخراج البيانات المخفية...',
            progress: 0.3);
        final extractedEncryptedBytes =
            await _stegoService.extractBytesFromImage(imageBytes);
        _logger.debug("performImageStegoOperation",
            "Extracted encrypted bytes length: ${extractedEncryptedBytes.length}");

        if (extractedEncryptedBytes.isEmpty) {
          throw Exception(
              "لم يتم العثور على بيانات مخفية في الصورة أو أن الصورة غير مدعومة بالشكل الصحيح.");
        }

        state = state.copyWith(
            outputMessage: '2/2: جاري فك تشفير النص المستخرج...',
            progress: 0.6);
        final decryptedBytes = await _aesService.decryptBytesWithPassword(
            extractedEncryptedBytes, state.password);
        _logger.debug("performImageStegoOperation",
            "Decrypted bytes length: ${decryptedBytes.length}");

        final extractedTextResult =
            utf8.decode(decryptedBytes); // تحويل البايتات إلى نص
        _logger.info("performImageStegoOperation",
            "Extraction and decryption successful. Extracted text: '${extractedTextResult.substring(0, min(20, extractedTextResult.length))}...'");

        state = state.copyWith(
          isLoading: false,
          extractedText: extractedTextResult,
          outputMessage: '✅ تم استخراج وفك تشفير النص بنجاح!',
          progress: 1.0,
        );

        await _historyService.addHistoryItem(HistoryItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timestamp: DateTime.now(),
          operationType: OperationType.extractImageStego,
          originalInput:
              "صورة: $inputImageName", // اسم الصورة التي تم الاستخراج منها
          coverText: null,
          output: extractedTextResult,
          usedPassword: true, // استخدمنا كلمة مرور لفك التشفير
          usedSteganography: true,
        ));
      }
    }
    // يجب تحديد نوع الخطأ من _aesService (إذا كانت مكتبة cryptography)
   // في ImageStegoNotifier -> performImageStegoOperation -> on ArgumentError
    on ArgumentError catch (e, stackTrace) {
      _logger.warn("performImageStegoOperation",
          "ArgumentError during extraction/decryption (possibly no hidden data or wrong format): ${e.message}",
          error: e, // <<<< استخدام معامل مسمى
          stackTrace: stackTrace); // <<<< استخدام معامل مسمى
      state = state.copyWith(
        isLoading: false,
        outputMessage:
            '❌ خطأ: لم يتم العثور على بيانات مخفية متوافقة أو أن البيانات تالفة. تأكد من أن الصورة تحتوي على بيانات مخفاة بالشكل الصحيح.',
        progress: 0.0,
      );
    } catch (e, stackTrace) {
      // التقاط الأخطاء العامة
      _logger.error(
          "performImageStegoOperation",
          "Error during image steganography operation",
          e, // المعامل الثالث لـ error
          stackTrace // المعامل الرابع لـ error
          );
      final errorMessage = e.toString().replaceFirst("Exception: ", "");
      state = state.copyWith(
        isLoading: false,
        outputMessage: '❌ خطأ: $errorMessage',
        progress: 0.0,
      );
    }
  }
}

final imageStegoScreenProvider =
    StateNotifierProvider<ImageStegoNotifier, ImageStegoState>((ref) {
  return ImageStegoNotifier(
    ref.watch(imageStegoServiceProvider),
    ref.watch(historyServiceProvider),
    ref.watch(aesGcmServiceProvider),
    ref.watch(
        appLoggerProvider), //  <<<< استخدم appLoggerProvider أو loggerServiceProvider('ImageStegoScreen')
  );
});

// تم تغيير اسم الكلاس
class ImageStegoScreen extends ConsumerWidget {
  const ImageStegoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(imageStegoScreenProvider);
    final notifier = ref.read(imageStegoScreenProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildImageStegoModeSelector(context, state, notifier),
              const SizedBox(height: 20),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.image_search_rounded,
                            color: Colors.white.withOpacity(0.9)),
                        label: Text('اختر صورة الغلاف',
                            style: GoogleFonts.cairo(
                                fontSize: 16, fontWeight: FontWeight.w500)),
                        onPressed: state.isLoading ? null : notifier.pickImage,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          elevation: 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (state.imageFile != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: theme.primaryColor.withOpacity(0.3))),
                          child: Row(
                            children: [
                              Icon(Icons.image_rounded,
                                  color: theme.primaryColor, size: 32),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      state.imageFile!.name,
                                      style: GoogleFonts.cairo(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (state.imageFile!.size > 0)
                                      Text(
                                        'الحجم: ${(state.imageFile!.size / 1024).toStringAsFixed(2)} KB',
                                        style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            color: Colors.grey[600]),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close_rounded,
                                    size: 20, color: Colors.grey[700]),
                                onPressed: state.isLoading
                                    ? null
                                    : notifier.resetState,
                                tooltip: 'إلغاء اختيار الصورة',
                              )
                            ],
                          ),
                        )
                      else
                        Text('لم يتم اختيار أي صورة بعد.',
                            style: GoogleFonts.cairo(
                                textStyle: TextStyle(
                                    color: Colors.grey[600], fontSize: 14))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: TextEditingController(text: state.password)
                      ..selection = TextSelection.fromPosition(
                          TextPosition(offset: state.password.length)),
                    onChanged: notifier.updatePassword,
                    obscureText: true,
                    style: GoogleFonts.cairo(fontSize: 16, letterSpacing: 1),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور (للتشفير/فك التشفير)',
                      labelStyle: GoogleFonts.cairo(),
                      hintText: 'مطلوبة لحماية البيانات المخفية',
                      hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.lock_person_outlined,
                          color: theme.iconTheme.color?.withOpacity(0.7)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (state.operationMode == ImageStegoMode.embed)
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: TextEditingController(text: state.textToEmbed)
                        ..selection = TextSelection.fromPosition(
                            TextPosition(offset: state.textToEmbed.length)),
                      onChanged: notifier.updateTextToEmbed,
                      maxLines: 4,
                      minLines: 2,
                      style: GoogleFonts.cairo(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: 'النص السري المراد إخفاؤه',
                        labelStyle: GoogleFonts.cairo(),
                        hintText:
                            'اكتب النص الذي تريد إخفاءه وتشفيره داخل الصورة...',
                        hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                        prefixIcon: Icon(Icons.edit_note_rounded,
                            color: theme.iconTheme.color?.withOpacity(0.7)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
              if (state.operationMode == ImageStegoMode.embed)
                const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: state.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white))
                    : Icon(state.operationMode == ImageStegoMode.embed
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded),
                label: Text(
                  state.isLoading
                      ? 'جاري المعالجة...'
                      : (state.operationMode == ImageStegoMode.embed
                          ? 'إخفاء النص وتشفيره في الصورة'
                          : 'استخراج وفك تشفير النص من الصورة'),
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                onPressed: (state.isLoading ||
                        state.imageFile == null ||
                        state.password.isEmpty ||
                        (state.operationMode == ImageStegoMode.embed &&
                            state.textToEmbed.isEmpty))
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        try {
                          await notifier.performImageStegoOperation();
                          if (context.mounted &&
                              !state.isLoading &&
                              (ref
                                      .read(imageStegoScreenProvider)
                                      .outputMessage
                                      .isNotEmpty &&
                                  !ref
                                      .read(imageStegoScreenProvider)
                                      .outputMessage
                                      .startsWith('❌'))) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      ref
                                          .read(imageStegoScreenProvider)
                                          .outputMessage,
                                      style: GoogleFonts.cairo()),
                                  behavior: SnackBarBehavior.floating,
                                  backgroundColor: Colors.green[700],
                                  duration: const Duration(seconds: 4)),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text('حدث خطأ في العملية',
                                    style: GoogleFonts.cairo()),
                                content: Text(
                                    e
                                        .toString()
                                        .replaceFirst("Exception: ", ""),
                                    style: GoogleFonts.cairo()),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: Text('حسنًا',
                                          style: GoogleFonts.cairo(
                                              color: theme.primaryColor)))
                                ],
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 3,
                ),
              ),
              const SizedBox(height: 16),
              if (state.isLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: state.progress,
                        backgroundColor: theme.primaryColor.withOpacity(0.2),
                        color: theme.primaryColor,
                        minHeight: 6,
                      ),
                      const SizedBox(height: 8),
                      Text(state.outputMessage,
                          style: GoogleFonts.cairo(
                              textStyle: TextStyle(
                                  color: theme.primaryColor, fontSize: 14))),
                    ],
                  ),
                )
              else if (state.extractedText.isNotEmpty ||
                  state.outputMessage.startsWith('❌'))
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  color: state.outputMessage.startsWith('❌')
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
                              state.outputMessage.startsWith('❌')
                                  ? 'رسالة خطأ'
                                  : 'النص المستخرج',
                              style: GoogleFonts.cairo(
                                  textStyle:
                                      theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: state.outputMessage.startsWith('❌')
                                    ? Colors.red.shade700
                                    : theme.textTheme.titleMedium?.color,
                              )),
                            ),
                            if (state.extractedText.isNotEmpty &&
                                !state.outputMessage.startsWith('❌'))
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.copy_all_outlined,
                                        size: 22),
                                    tooltip: 'نسخ النص المستخرج',
                                    color:
                                        theme.iconTheme.color?.withOpacity(0.8),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(
                                          text: state.extractedText));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '✅ تم نسخ النص إلى الحافظة.',
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
                                    tooltip: 'مشاركة النص المستخرج',
                                    color:
                                        theme.iconTheme.color?.withOpacity(0.8),
                                    onPressed: () {
                                      Share.share(state.extractedText);
                                    },
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          state.outputMessage.startsWith('❌')
                              ? state.outputMessage.substring(2)
                              : state.extractedText,
                          style: GoogleFonts.cairo(
                              textStyle: TextStyle(
                            fontSize: 14.5,
                            color: state.outputMessage.startsWith('❌')
                                ? Colors.red.shade800
                                : theme.textTheme.bodyMedium?.color,
                            height: 1.6,
                          )),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageStegoModeSelector(BuildContext context,
      ImageStegoState state, ImageStegoNotifier notifier) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'اختر العملية المطلوبة للصورة:',
          style: GoogleFonts.cairo(
              textStyle: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 8),
        SegmentedButton<ImageStegoMode>(
          segments: <ButtonSegment<ImageStegoMode>>[
            ButtonSegment<ImageStegoMode>(
                value: ImageStegoMode.embed,
                label: Text('إخفاء',
                    style: GoogleFonts.cairo(
                        fontWeight: state.operationMode == ImageStegoMode.embed
                            ? FontWeight.w600
                            : FontWeight.normal)),
                icon: const Icon(Icons.visibility_off_outlined, size: 20)),
            ButtonSegment<ImageStegoMode>(
                value: ImageStegoMode.extract,
                label: Text('استخراج',
                    style: GoogleFonts.cairo(
                        fontWeight:
                            state.operationMode == ImageStegoMode.extract
                                ? FontWeight.w600
                                : FontWeight.normal)),
                icon: const Icon(Icons.visibility_outlined, size: 20)),
          ],
          selected: {state.operationMode},
          onSelectionChanged: (Set<ImageStegoMode> newSelection) {
            notifier.setOperationMode(newSelection.first);
          },
          style: SegmentedButton.styleFrom(
            backgroundColor:
                theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            selectedBackgroundColor: theme.primaryColor.withOpacity(0.9),
            selectedForegroundColor: Colors.white,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            textStyle: GoogleFonts.cairo(fontSize: 13),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          showSelectedIcon: false,
        ),
      ],
    );
  }
}
