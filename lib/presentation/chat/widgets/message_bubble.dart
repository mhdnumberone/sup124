// lib/presentation/chat/widgets/message_bubble.dart
import "dart:io"; // Added for getTemporaryDirectory
import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";
import "package:intl/intl.dart" as intl;
// import "package:audioplayers/audioplayers.dart";
import "package:open_file_plus/open_file_plus.dart";
import "package:path_provider/path_provider.dart"; // Added for getTemporaryDirectory
import "package:photo_view/photo_view.dart";
import "package:video_player/video_player.dart";

import "../../../core/logging/logger_provider.dart";
import "../../../core/utils/file_saver.dart";
import "../../../data/models/chat/chat_message.dart";

// Helper to format file size
String _formatBytes(int bytes, int decimals) {
  if (bytes <= 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  var i = (bytes.toString().length - 1) ~/ 3;
  if (i >= suffixes.length) i = suffixes.length - 1;
  return "${(bytes / (1024 * 1024 * i)).toStringAsFixed(decimals)} ${suffixes[i]}";
}

class MessageBubble extends ConsumerStatefulWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  ConsumerState<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends ConsumerState<MessageBubble> {
  VideoPlayerController? _videoController;
  // AudioPlayer? _audioPlayer;
  final bool _isAudioPlaying = false;
  final Duration _audioDuration = Duration.zero;
  final Duration _audioPosition = Duration.zero;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.message.messageType == MessageType.video &&
        widget.message.fileUrl != null) {
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(widget.message.fileUrl!))
            ..initialize().then((_) {
              if (mounted) {
                setState(() {});
              }
            });
    }
//     if (widget.message.messageType == MessageType.audio && widget.message.fileUrl != null) {
//       _audioPlayer = AudioPlayer();
//       _audioPlayer?.onDurationChanged.listen((d) {
//         if (mounted) {
//           setState(() => _audioDuration = d);
//         }
//       });
//       _audioPlayer?.onPositionChanged.listen((p) {
//         if (mounted) {
//           setState(() => _audioPosition = p);
//         }
//       });
//       _audioPlayer?.onPlayerStateChanged.listen((s) {
//         if (mounted) {
//           setState(() => _isAudioPlaying = s == PlayerState.playing);
//         }
//       });
//       _audioPlayer?.setSourceUrl(widget.message.fileUrl!);
//     }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    // _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _downloadAndSaveFile(
      BuildContext context, String url, String fileName) async {
    final logger = ref.read(appLoggerProvider);
    if (!mounted) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text("بدء تنزيل: $fileName", style: GoogleFonts.cairo())),
    );
    try {
      Dio dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            if (mounted) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          }
        },
      );
      if (response.data != null) {
        final result = await FileSaver.saveFile(
            bytes: Uint8List.fromList(response.data!),
            suggestedFileName: fileName);
        if (mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result, style: GoogleFonts.cairo())),
          );
        }
        logger.info("MessageBubble", "File saved: $fileName. Result: $result");
      } else {
        throw Exception("لم يتم استلام بيانات الملف.");
      }
    } catch (e, s) {
      logger.error(
          "MessageBubble", "Error downloading/saving file: $fileName", e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("فشل تنزيل/حفظ الملف: ${e.toString()}",
                  style: GoogleFonts.cairo()),
              backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
    }
  }

  Future<void> _openFile(
      BuildContext context, String url, String fileName) async {
    final logger = ref.read(appLoggerProvider);
    if (!mounted) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text("جاري فتح الملف: $fileName...", style: GoogleFonts.cairo())),
    );
    try {
      Dio dio = Dio();
      final Directory tempDir = await getTemporaryDirectory(); // Corrected type
      final String localPath = "${tempDir.path}/$fileName"; // Corrected type
      await dio.download(
        url,
        localPath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            if (mounted) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          }
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
      }
      final OpenResult result =
          await OpenFile.open(localPath); // Corrected type
      logger.info("MessageBubble",
          "Attempted to open file: $localPath. Result: ${result.message}");
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "لم يتم العثور على تطبيق لفتح هذا الملف: ${result.message}",
                    style: GoogleFonts.cairo()),
                backgroundColor: Colors.orangeAccent),
          );
        }
      }
    } catch (e, s) {
      logger.error("MessageBubble", "Error opening file: $fileName", e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("فشل فتح الملف: ${e.toString()}",
                  style: GoogleFonts.cairo()),
              backgroundColor: Colors.redAccent),
        );
      }
    }
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isSentByCurrentUser = widget.message.isSentByCurrentUser;
    final theme = Theme.of(context);
    final bubbleColor = isSentByCurrentUser
        ? theme.primaryColor.withOpacity(0.9)
        : (theme.brightness == Brightness.dark
            ? Colors.grey[800]!
            : Colors.grey[200]!);
    final textColor = isSentByCurrentUser
        ? Colors.white
        : (theme.brightness == Brightness.dark
            ? Colors.white.withOpacity(0.9)
            : Colors.black.withOpacity(0.87));

    final timeFormatted =
        intl.DateFormat.Hm("ar").format(widget.message.timestamp);

    Widget messageContent;
    List<Widget> actionButtons = [];

    if (widget.message.fileUrl != null && widget.message.fileName != null) {
      actionButtons.add(IconButton(
        icon: Icon(Icons.download_outlined,
            color: textColor.withOpacity(0.8), size: 20),
        tooltip: "تنزيل الملف",
        onPressed: _isDownloading
            ? null
            : () => _downloadAndSaveFile(
                context, widget.message.fileUrl!, widget.message.fileName!),
      ));
    }

    switch (widget.message.messageType) {
      case MessageType.text:
        messageContent = Text(
          widget.message.text ?? "",
          style: GoogleFonts.cairo(color: textColor, fontSize: 15),
        );
        break;
      case MessageType.image:
        if (widget.message.fileUrl != null) {
          messageContent = GestureDetector(
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) {
                return Scaffold(
                  appBar: AppBar(
                      title: Text(widget.message.fileName ?? "صورة",
                          style: GoogleFonts.cairo()),
                      backgroundColor: Colors.black),
                  body: PhotoView(
                    imageProvider: NetworkImage(widget.message.fileUrl!),
                    loadingBuilder: (context, event) =>
                        const Center(child: CircularProgressIndicator()),
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.black),
                  ),
                );
              }));
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: 250,
                  maxWidth: MediaQuery.of(context).size.width * 0.6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.message.fileUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return child;
                    }
                    return Container(
                      height: 150,
                      color: Colors.grey[300],
                      child: Center(
                          child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null)),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                      height: 150,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image_outlined,
                          color: Colors.grey, size: 50)),
                ),
              ),
            ),
          );
        } else {
          messageContent = Text("[صورة غير متاحة]",
              style: GoogleFonts.cairo(color: textColor));
        }
        break;
      case MessageType.video:
        if (_videoController != null &&
            _videoController!.value.isInitialized &&
            widget.message.fileUrl != null) {
          messageContent = GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) {
                  final VideoPlayerController controller =
                      VideoPlayerController.networkUrl(
                          Uri.parse(widget.message.fileUrl!)); // Corrected type
                  return Scaffold(
                    appBar: AppBar(
                        title: Text(widget.message.fileName ?? "فيديو",
                            style: GoogleFonts.cairo()),
                        backgroundColor: Colors.black),
                    body: Center(
                        child: FutureBuilder(
                      future: controller.initialize(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done) {
                          controller.play();
                          return AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: VideoPlayer(controller));
                        }
                        return const CircularProgressIndicator();
                      },
                    )),
                    floatingActionButton: FloatingActionButton(
                      onPressed: () => controller.value.isPlaying
                          ? controller.pause()
                          : controller.play(),
                      child: Icon(controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow),
                    ),
                  );
                })).then((_) => _videoController?.pause());
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio > 0
                          ? _videoController!.value.aspectRatio
                          : 16 / 9,
                      child: VideoPlayer(_videoController!)),
                  Icon(Icons.play_circle_fill_rounded,
                      color: Colors.white.withOpacity(0.8), size: 50),
                ],
              ));
        } else if (widget.message.fileUrl != null) {
          messageContent = Container(
              height: 150,
              color: Colors.black,
              child: const Center(child: CircularProgressIndicator()));
        } else {
          messageContent = Text("[فيديو غير متاح]",
              style: GoogleFonts.cairo(color: textColor));
        }
        break;
//       case MessageType.audio:
//         if (_audioPlayer != null && widget.message.fileUrl != null) {
//           messageContent = Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               IconButton(
//                 icon: Icon(_isAudioPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: textColor, size: 30),
//                 onPressed: () {
//                   if (_isAudioPlaying) {
//                     _audioPlayer?.pause();
//                   } else {
//                     _audioPlayer?.play(UrlSource(widget.message.fileUrl!));
//                   }
//                 },
//               ),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(widget.message.fileName ?? "ملف صوتي", style: GoogleFonts.cairo(color: textColor, fontSize: 14), overflow: TextOverflow.ellipsis),
//                     if (_audioDuration.inSeconds > 0)
//                       SliderTheme(
//                         data: SliderTheme.of(context).copyWith(
//                           thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
//                           overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
//                           trackHeight: 2.0,
//                           activeTrackColor: textColor,
//                           inactiveTrackColor: textColor.withOpacity(0.3),
//                           thumbColor: textColor,
//                         ),
//                         child: Slider(
//                           min: 0.0,
//                           max: _audioDuration.inSeconds.toDouble(),
//                           value: _audioPosition.inSeconds.toDouble().clamp(0.0, _audioDuration.inSeconds.toDouble()),
//                           onChanged: (value) {
//                             _audioPlayer?.seek(Duration(seconds: value.toInt()));
//                           },
//                         ),
//                       )
//                     else Container(height: 10, child: LinearProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(textColor.withOpacity(0.5)))),
//                     Text("${_audioPosition.toString().split(".").first} / ${_audioDuration.toString().split(".").first}", style: GoogleFonts.cairo(color: textColor.withOpacity(0.7), fontSize: 10)),
//                   ],
//                 ),
//               ),
//             ],
//           );
//         } else {
//           messageContent = Text("[ملف صوتي غير متاح]", style: GoogleFonts.cairo(color: textColor));
//         }
//         break;
      case MessageType.audio:
        messageContent = Text("[تشغيل الصوت غير مدعوم حاليًا]",
            style: GoogleFonts.cairo(color: textColor));
        break;
      case MessageType.file:
        actionButtons.insert(
            0,
            IconButton(
              icon: Icon(Icons.open_in_new_outlined,
                  color: textColor.withOpacity(0.8), size: 20),
              tooltip: "فتح الملف",
              onPressed: _isDownloading
                  ? null
                  : () => _openFile(context, widget.message.fileUrl!,
                      widget.message.fileName!),
            ));
        messageContent = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined, color: textColor, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.message.fileName ?? "ملف",
                      style: GoogleFonts.cairo(color: textColor, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  if (widget.message.fileSize != null)
                    Text(_formatBytes(widget.message.fileSize!, 1),
                        style: GoogleFonts.cairo(
                            color: textColor.withOpacity(0.7), fontSize: 10)),
                ],
              ),
            ),
          ],
        );
        break;
      default:
        messageContent = Text("[رسالة غير معروفة]",
            style: GoogleFonts.cairo(color: textColor));
    }

    return Align(
      alignment:
          isSentByCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: isSentByCurrentUser
                  ? const Radius.circular(12)
                  : const Radius.circular(0),
              bottomRight: isSentByCurrentUser
                  ? const Radius.circular(0)
                  : const Radius.circular(12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 3,
                offset: const Offset(0, 1),
              )
            ]),
        child: Column(
          crossAxisAlignment: isSentByCurrentUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            messageContent,
            if (_isDownloading)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: LinearProgressIndicator(
                  value: _downloadProgress > 0
                      ? _downloadProgress
                      : null, // Indeterminate if 0
                  backgroundColor: textColor.withOpacity(0.2),
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (actionButtons.isNotEmpty) ...actionButtons,
                if (actionButtons.isNotEmpty &&
                    widget.message.messageType != MessageType.text)
                  const SizedBox(width: 4),
                Text(
                  timeFormatted,
                  style: GoogleFonts.cairo(
                      color: textColor.withOpacity(0.7), fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
