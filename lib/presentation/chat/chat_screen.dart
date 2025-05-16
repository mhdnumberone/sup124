// lib/presentation/chat/chat_screen.dart
// import "dart:io"; // Removed unused import

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";
import "package:mime/mime.dart"; // For looking up MIME types

import "../../core/logging/logger_provider.dart";
import "../../data/models/chat/chat_message.dart";
import "providers/auth_providers.dart";
import "providers/chat_providers.dart";
import "widgets/message_bubble.dart";
import "widgets/message_input_bar.dart";

class ChatScreen extends ConsumerWidget {
  final String conversationId;
  final String conversationTitle; 
  final bool showAppBar;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.conversationTitle,
    this.showAppBar = true, 
  });

  MessageType _determineMessageTypeFromFile(PlatformFile file) {
    final mimeType = lookupMimeType(file.name, headerBytes: file.bytes?.take(1024).toList());
    final extension = file.extension?.toLowerCase();
    
    if (mimeType != null) {
        if (mimeType.startsWith("image/")) return MessageType.image;
        if (mimeType.startsWith("video/")) return MessageType.video;
        if (mimeType.startsWith("audio/")) return MessageType.audio;
    }
    // Fallback to extension if MIME type is generic or missing
    if (extension == null) {
      return MessageType.file; 
    }
    switch (extension) {
      case "jpg":
      case "jpeg":
      case "png":
      case "gif":
      case "webp":
      case "bmp":
        return MessageType.image;
      case "mp4":
      case "mov":
      case "avi":
      case "mkv":
      case "webm":
        return MessageType.video;
      case "mp3":
      case "wav":
      case "aac":
      case "ogg":
      case "m4a":
        return MessageType.audio;
      default:
        return MessageType.file;
    }
  }

  void _onMessageLongPress(
      BuildContext context, ChatMessage message, WidgetRef ref) {
    final logger = ref.read(appLoggerProvider);
    final currentTheme = Theme.of(context);

    showModalBottomSheet(
        context: context,
        backgroundColor: currentTheme.bottomSheetTheme.modalBackgroundColor ??
            currentTheme.cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            child: Wrap(
              children: <Widget>[
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(top: 8, bottom: 12),
                    decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (message.text != null && message.text!.isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.copy_all_outlined,
                        color: currentTheme.colorScheme.primary),
                    title: Text("نسخ النص",
                        style: GoogleFonts.cairo(fontSize: 16)),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text!));
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("تم نسخ النص إلى الحافظة",
                              style: GoogleFonts.cairo()),
                          behavior: SnackBarBehavior.floating, 
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      );
                      logger.info("ChatScreen:MessageMenu",
                          "Copied message text: ${message.id}");
                    },
                  ),
              ],
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentCodeAsync = ref.watch(currentAgentCodeProvider);
    final messagesAsyncValue =
        ref.watch(chatMessagesStreamProvider(conversationId));
    final theme = Theme.of(context);
    final logger = ref.read(appLoggerProvider);

    if (agentCodeAsync.isLoading ||
        agentCodeAsync.hasError ||
        agentCodeAsync.value == null ||
        agentCodeAsync.value!.isEmpty) {
      Widget bodyContent;
      if (agentCodeAsync.isLoading) {
        bodyContent = const Center(child: CircularProgressIndicator());
      } else {
        bodyContent = Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              agentCodeAsync.hasError
                  ? "خطأ في تحميل معلومات المستخدم للدردشة."
                  : "الرجاء تسجيل الدخول لعرض الرسائل.",
              style: GoogleFonts.cairo(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return Scaffold(
        appBar: showAppBar
            ? AppBar(title: Text(conversationTitle, style: GoogleFonts.cairo()))
            : null,
        body: bodyContent,
      );
    }

    final currentAgentCode = agentCodeAsync.value!;

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: Text(conversationTitle, style: GoogleFonts.cairo()),
              backgroundColor: theme.appBarTheme.backgroundColor ??
                  theme.colorScheme.primary,
              elevation: theme.appBarTheme.elevation ?? 1.0,
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh_outlined),
                  tooltip: "تحديث الرسائل",
                  onPressed: () {
                    ref.invalidate(chatMessagesStreamProvider(conversationId));
                    logger.info("ChatScreen",
                        "Manually refreshed messages for $conversationId");
                  },
                ),
              ],
            )
          : null, 
      body: Column(
        children: [
          Expanded(
            child: messagesAsyncValue.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 100,
                            color: theme.colorScheme.primary.withOpacity(0.6)),
                        const SizedBox(height: 20),
                        Text(
                          "ابدأ المحادثة!",
                          style: GoogleFonts.cairo(
                              fontSize: 22,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          "لا توجد رسائل في هذه المحادثة بعد.",
                          style: GoogleFonts.cairo(
                              fontSize: 16, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10.0, vertical: 15.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return GestureDetector(
                      onLongPress: () =>
                          _onMessageLongPress(context, message, ref),
                      child: MessageBubble(
                        message: message,
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) {
                logger.error("ChatScreen:StreamBuilder",
                    "Error UI msg for $conversationId", err, stack);
                return Center(
                    child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: Colors.red[300], size: 60),
                      const SizedBox(height: 15),
                      Text(
                        "حدث خطأ أثناء تحميل الرسائل.\n${err.toString()}",
                        style: GoogleFonts.cairo(
                            color: Colors.red[300], fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh_rounded),
                        label:
                            Text("إعادة المحاولة", style: GoogleFonts.cairo()),
                        onPressed: () => ref.invalidate(
                            chatMessagesStreamProvider(conversationId)),
                      )
                    ],
                  ),
                ));
              },
            ),
          ),
          MessageInputBar(
            onSendPressed: (text) async {
              if (text.trim().isNotEmpty) {
                final apiService = ref.read(apiServiceProvider);
                if (apiService == null) {
                  logger.error("ChatScreen:onSendPressed",
                      "ApiService is null. Cannot send message.");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("خدمة إرسال الرسائل غير متاحة.",
                          style: GoogleFonts.cairo()),
                      backgroundColor: Colors.orangeAccent,
                    ));
                  }
                  return;
                }
                final newMessage = ChatMessage(
                  id: "", 
                  senderId: currentAgentCode,
                  text: text,
                  messageType: MessageType.text,
                  timestamp:
                      DateTime.now(), 
                  isSentByCurrentUser:
                      true, 
                );
                try {
                  await apiService.sendMessage(conversationId, newMessage);
                  logger.info("ChatScreen:onSendPressed",
                      "Sent text msg to $conversationId");
                } catch (e, stackTrace) {
                  logger.error("ChatScreen:onSendPressed",
                      "Failed to send text msg", e, stackTrace);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("فشل إرسال الرسالة: ${e.toString()}",
                          style: GoogleFonts.cairo()),
                      backgroundColor: Colors.redAccent,
                    ));
                  }
                }
              } else {
                logger.info("ChatScreen:onSendPressed",
                    "Attempted to send empty text message.");
              }
            },
            onAttachmentPressed: () async {
              final apiService = ref.read(apiServiceProvider);
              if (apiService == null) {
                logger.error("ChatScreen:onAttachmentPressed",
                    "ApiService is null. Cannot send attachment.");
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("خدمة إرسال المرفقات غير متاحة",
                          style: GoogleFonts.cairo())));
                }
                return;
              }
              try {
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.any, 
                  withData: true, // Ensure file bytes are loaded for MIME type detection and upload
                );
                if (result != null && result.files.isNotEmpty) {
                  PlatformFile file = result.files.first;
                  logger.info("ChatScreen:onAttachmentPressed",
                      "Picked file: ${file.name}, size: ${file.size}");

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("جارٍ رفع الملف: ${file.name}...",
                              style: GoogleFonts.cairo())),
                    );
                  }

                  String? downloadUrl = await apiService.uploadFileToStorage(file, conversationId);
                  
                  if (!context.mounted) return; // Check mounted status after async operation

                  if (downloadUrl == null) {
                     logger.error("ChatScreen:onAttachmentPressed", "Upload failed for ${file.name}");
                     ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text("فشل رفع الملف: ${file.name}",
                                style: GoogleFonts.cairo()),
                            backgroundColor: Colors.redAccent,
                        ),
                      );
                    return;
                  }
                  
                  logger.info("ChatScreen:onAttachmentPressed", "File ${file.name} uploaded. URL: $downloadUrl");

                  final newFileMessage = ChatMessage(
                    id: "",
                    senderId: currentAgentCode,
                    text: null, 
                    fileName: file.name,
                    fileUrl: downloadUrl, 
                    fileSize: file.size,
                    messageType: _determineMessageTypeFromFile(file),
                    timestamp: DateTime.now(),
                    isSentByCurrentUser: true,
                  );
                  await apiService.sendMessage(conversationId, newFileMessage);
                  logger.info("ChatScreen:onAttachmentPressed",
                      "Sent file message: ${file.name}");
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove uploading snackbar
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text("تم إرسال الملف: ${file.name}",
                              style: GoogleFonts.cairo())),
                    );
                  }
                } else {
                  logger.info("ChatScreen:onAttachmentPressed",
                      "File picking cancelled or no file selected.");
                }
              } catch (e, stackTrace) {
                logger.error("ChatScreen:onAttachmentPressed",
                    "Error picking or sending file", e, stackTrace);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text("حدث خطأ أثناء معالجة الملف: ${e.toString()}",
                        style: GoogleFonts.cairo()),
                    backgroundColor: Colors.redAccent,
                  ));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}


