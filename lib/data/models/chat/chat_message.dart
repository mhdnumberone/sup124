// lib/data/models/chat/chat_message.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, audio, video, file }

String messageTypeToString(MessageType type) {
  return type.toString().split('.').last;
}

MessageType stringToMessageType(String? typeStr) {
  if (typeStr == null) return MessageType.text;
  return MessageType.values.firstWhere(
      (e) =>
          e.toString().split('.').last.toLowerCase() == typeStr.toLowerCase(),
      orElse: () => MessageType.text);
}

class ChatMessage {
  final String id;
  final String senderId; //  agent_code
  final String? text;
  final MessageType messageType;
  final DateTime timestamp;
  final bool isSentByCurrentUser;

  final String? fileName;
  final String? fileUrl;
  final int? fileSize;

  ChatMessage({
    required this.id,
    required this.senderId,
    this.text,
    required this.messageType,
    required this.timestamp,
    required this.isSentByCurrentUser,
    this.fileName,
    this.fileUrl,
    this.fileSize,
  });

  factory ChatMessage.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc, String currentAgentCode) {
    final data = doc.data();
    if (data == null) {
      // يمكنك رمي استثناء أو إرجاع قيمة افتراضية إذا كان المستند فارغًا بشكل غير متوقع
      throw Exception(
          "ChatMessage document data is null for doc ID: ${doc.id}");
    }
    final senderAgentCode = data['senderAgentCode'] as String? ?? '';
    return ChatMessage(
      id: doc.id,
      senderId: senderAgentCode,
      text: data['text'] as String?,
      messageType: stringToMessageType(data['messageType'] as String?),
      timestamp: (data['timestamp'] as Timestamp? ?? Timestamp.now())
          .toDate(), // استخدام Timestamp من Firestore
      isSentByCurrentUser: senderAgentCode == currentAgentCode,
      fileName: data['fileName'] as String?,
      fileUrl: data['fileUrl'] as String?,
      fileSize: data['fileSize'] as int?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderAgentCode': senderId,
      if (text != null && text!.isNotEmpty) 'text': text,
      'messageType': messageTypeToString(messageType),
      // سيتم تعيين timestamp كـ FieldValue.serverTimestamp() في ApiService
      // أو يمكنك استخدام Timestamp.fromDate(timestamp) إذا كنت تريد وقت العميل
      'timestamp':
          Timestamp.fromDate(timestamp), // أو اتركه ليتم تعيينه في ApiService
      if (fileName != null) 'fileName': fileName,
      if (fileUrl != null) 'fileUrl': fileUrl,
      if (fileSize != null) 'fileSize': fileSize,
    };
  }
}
