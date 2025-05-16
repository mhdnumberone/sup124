 // lib/data/models/chat/chat_conversation.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math'; // لـ Math.min

class ChatParticipantInfo {
  final String agentCode;
  final String displayName;
  // final String? photoUrl; // يمكنك إضافته لاحقًا إذا أردت صورًا للمستخدمين

  ChatParticipantInfo({
    required this.agentCode,
    required this.displayName,
    // this.photoUrl,
  });

  factory ChatParticipantInfo.fromMap(
      String agentCode, Map<String, dynamic> map) {
    return ChatParticipantInfo(
      agentCode: agentCode,
      displayName: map['displayName'] as String? ?? agentCode,
      // photoUrl: map['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      // if (photoUrl != null) 'photoUrl': photoUrl,
    };
  }
}

class ChatConversation {
  final String id;
  final List<String> participants;
  final Map<String, ChatParticipantInfo> participantInfo;
  final String conversationTitle;
  final String? lastMessageText;
  final DateTime? lastMessageTimestamp;
  final String? lastMessageSenderAgentCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, bool> deletedForUsers; // Added field

  ChatConversation({
    required this.id,
    required this.participants,
    required this.participantInfo,
    required this.conversationTitle,
    this.lastMessageText,
    this.lastMessageTimestamp,
    this.lastMessageSenderAgentCode,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedForUsers, // Added to constructor
  });

  factory ChatConversation.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc, String currentAgentCode) {
    final data = doc.data();
    if (data == null) {
      throw Exception(
          "ChatConversation document data is null for doc ID: ${doc.id}");
    }

    final participantsList =
        List<String>.from(data['participants'] as List<dynamic>? ?? []);

    Map<String, ChatParticipantInfo> pInfoMap = {};
    if (data['participantInfo'] != null && data['participantInfo'] is Map) {
      (data['participantInfo'] as Map<String, dynamic>).forEach((key, value) {
        if (value is Map<String, dynamic>) {
          pInfoMap[key] = ChatParticipantInfo.fromMap(key, value);
        }
      });
    }

    String determinedConversationTitle;
    if (participantsList.length == 1 &&
        participantsList.contains(currentAgentCode)) {
      determinedConversationTitle = pInfoMap[currentAgentCode]?.displayName ??
          "ملاحظاتي (${currentAgentCode.substring(0, min(3, currentAgentCode.length))}..)";
    } else if (participantsList.length == 2) {
      String? otherAgentCode = participantsList
          .firstWhere((p) => p != currentAgentCode, orElse: () => '');
      if (otherAgentCode.isNotEmpty && pInfoMap.containsKey(otherAgentCode)) {
        determinedConversationTitle = pInfoMap[otherAgentCode]!.displayName;
      } else if (otherAgentCode.isNotEmpty) {
        determinedConversationTitle =
            "العميل ${otherAgentCode.substring(0, min(3, otherAgentCode.length))}..";
      } else {
        determinedConversationTitle = "محادثة خاصة";
      }
    } else if (participantsList.length > 2) {
      if (data['title'] != null && (data['title'] as String).isNotEmpty) {
        determinedConversationTitle = data['title'] as String;
      } else {
        List<String> otherParticipantNames = pInfoMap.entries
            .where((entry) =>
                entry.key != currentAgentCode &&
                entry.value.displayName.isNotEmpty)
            .map((entry) => entry.value.displayName)
            .take(2)
            .toList();
        if (otherParticipantNames.isNotEmpty) {
          determinedConversationTitle =
              "مجموعة: ${otherParticipantNames.join(', ')}";
          if (pInfoMap.length - 1 > 2) {
            determinedConversationTitle += "...";
          }
        } else {
          determinedConversationTitle =
              "مجموعة (${participantsList.length})";
        }
      }
    } else {
      determinedConversationTitle = "محادثة غير معروفة";
    }

    final deletedForUsersData = data['deletedForUsers'] as Map<String, dynamic>? ?? {};
    final Map<String, bool> typedDeletedForUsers = deletedForUsersData.map((key, value) => MapEntry(key, value as bool));

    return ChatConversation(
      id: doc.id,
      participants: participantsList,
      participantInfo: pInfoMap,
      conversationTitle: determinedConversationTitle,
      lastMessageText: data['lastMessageText'] as String?,
      lastMessageTimestamp:
          (data['lastMessageTimestamp'] as Timestamp?)?.toDate(),
      lastMessageSenderAgentCode: data['lastMessageSenderAgentCode'] as String?,
      createdAt: (data['createdAt'] as Timestamp? ?? Timestamp.now()).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp? ?? Timestamp.now()).toDate(),
      deletedForUsers: typedDeletedForUsers, // Use parsed map
    );
  }

  Map<String, dynamic> toFirestore() {
    final Map<String, dynamic> dataMap = {
      'participants': participants..sort(),
      'participantInfo':
          participantInfo.map((key, value) => MapEntry(key, value.toMap())),
      'lastMessageText': lastMessageText,
      'lastMessageTimestamp': lastMessageTimestamp != null
          ? Timestamp.fromDate(lastMessageTimestamp!)
          : null,
      'lastMessageSenderAgentCode': lastMessageSenderAgentCode,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'deletedForUsers': deletedForUsers, // Add to Firestore map
    };

    if (participants.length > 2 &&
        conversationTitle != "مجموعة جديدة" &&
        !conversationTitle.startsWith("مجموعة: ")) {
      dataMap['title'] = conversationTitle;
    }
    return dataMap;
  }
}

