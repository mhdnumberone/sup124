// lib/presentation/chat/chat_list_screen.dart
import "dart:async"; // For unawaited
import "package:cloud_firestore/cloud_firestore.dart"; 
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:google_fonts/google_fonts.dart";

import "../../core/logging/logger_provider.dart";
// Import the whole file, as both ChatConversation and ChatParticipantInfo are used.
import "../../data/models/chat/chat_conversation.dart"; 
import "chat_screen.dart";
import "providers/auth_providers.dart";
import "providers/chat_providers.dart";
import "widgets/chat_list_item.dart";

final chatSearchQueryProvider = StateProvider<String>((ref) => "");

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});
  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) {
        ref.read(chatSearchQueryProvider.notifier).state =
            _searchController.text;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        ref.read(chatSearchQueryProvider.notifier).state = "";
      }
    });
  }

  Future<ChatParticipantInfo?> _fetchAgentInfo(
      String agentCode, WidgetRef ref) async {
    final logger = ref.read(appLoggerProvider);
    final firestore = FirebaseFirestore.instance;
    logger.info("_fetchAgentInfo",
        "Fetching info for agent: $agentCode (direct Firestore access)");
    if (agentCode.isEmpty) return null;
    try {
      final doc =
          await firestore.collection("agent_identities").doc(agentCode).get();
      if (doc.exists) {
        final data = doc.data()!;
        return ChatParticipantInfo(
          agentCode: agentCode,
          displayName: data["displayName"] as String? ?? agentCode,
        );
      }
      logger.warn("_fetchAgentInfo", "Agent info not found for $agentCode.");
      return null;
    } catch (e, s) {
      logger.error(
          "_fetchAgentInfo", "Error fetching agent info for $agentCode", e, s);
      return null;
    }
  }

  void _createNewConversation() async {
    final apiService = ref.read(apiServiceProvider);
    final logger = ref.read(appLoggerProvider);
    final currentAgentCode =
        ref.read(currentAgentCodeProvider).value;
    final bool mainContextMounted = mounted; // Capture mounted state
    final theme = Theme.of(context); // Get theme for styling

    if (apiService == null ||
        currentAgentCode == null ||
        currentAgentCode.isEmpty) {
      logger.warn("ChatListScreen:createNewConversation",
          "ApiService or currentAgentCode is not available.");
      if (mainContextMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("الخدمة غير متاحة أو لم يتم تسجيل الدخول.",
                  style: GoogleFonts.cairo())),
        );
      }
      return;
    }

    String? otherAgentCode = await showDialog<String>(
        context: context, 
        barrierDismissible: false, // Make dialog harder to dismiss accidentally
        builder: (dialogContext) {
          TextEditingController agentCodeController = TextEditingController();
          return AlertDialog(
            title: Text("بدء محادثة جديدة", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min, // Important for Column in AlertDialog
              children: [
                Text("الرجاء إدخال الرمز التعريفي للشخص الذي ترغب في بدء محادثة معه.", style: GoogleFonts.cairo(fontSize: 14)),
                const SizedBox(height: 15),
                TextField(
                  controller: agentCodeController,
                  decoration: InputDecoration(
                      hintText: "الرمز التعريفي للعميل الآخر",
                      hintStyle: GoogleFonts.cairo(),
                      border: const OutlineInputBorder(), // Add border for better visibility
                      prefixIcon: const Icon(Icons.person_search_outlined)
                  ),
                  style: GoogleFonts.cairo(),
                  autofocus: true, // Focus on the text field immediately
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceBetween, // Space out buttons
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text("إلغاء", style: GoogleFonts.cairo(color: theme.colorScheme.error, fontWeight: FontWeight.bold))),
              ElevatedButton.icon(
                  icon: const Icon(Icons.send_outlined),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
                  ),
                  onPressed: () {
                    final code = agentCodeController.text.trim();
                    if (code.isNotEmpty) {
                       Navigator.of(dialogContext).pop(code);
                    } else {
                      // Optionally show a small validation message within the dialog
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text("الرجاء إدخال الرمز التعريفي.", style: GoogleFonts.cairo()), duration: const Duration(seconds: 2))
                      );
                    }
                  },
                  label: Text("بدء المحادثة", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)))
            ],
          );
        });

    if (otherAgentCode == null || otherAgentCode.isEmpty) {
      logger.info("ChatListScreen:createNewConversation",
          "Dialog cancelled or no other agent code entered.");
      return;
    }

    if (otherAgentCode == currentAgentCode) {
      logger.info("ChatListScreen:createNewConversation",
          "Attempted to create chat with self.");
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("لا يمكنك إنشاء محادثة مع نفسك بهذه الطريقة.",
                  style: GoogleFonts.cairo())),
        );
      }
      return;
    }

    final otherAgentInfo =
        await _fetchAgentInfo(otherAgentCode, ref);
    if (otherAgentInfo == null) {
      logger.error("ChatListScreen:createNewConversation",
          "Agent $otherAgentCode not found or error fetching info.");
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("لم يتم العثور على عميل بالرمز: $otherAgentCode",
                  style: GoogleFonts.cairo())),
        );
      }
      return;
    }

    final currentUserInfo = await _fetchAgentInfo(currentAgentCode, ref);
    if (currentUserInfo == null) {
      logger.error("ChatListScreen:CreateNewConversation",
          "Failed to fetch current user ($currentAgentCode) info. This should not happen if login was successful.");
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("خطأ في جلب معلومات المستخدم الحالي.",
                style: GoogleFonts.cairo())));
      }
      return;
    }

    final Map<String, ChatParticipantInfo> participantsInfoMap = {
      currentAgentCode: currentUserInfo,
      otherAgentCode: otherAgentInfo,
    };

    try {
      // Show a loading indicator while creating/getting conversation
      if(mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return Dialog(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 20),
                    Text("جاري إعداد المحادثة...", style: GoogleFonts.cairo()),
                  ],
                ),
              ),
            );
          },
        );
      }

      final newConversationId =
          await apiService.createOrGetConversationWithParticipants(
        [otherAgentCode],
        participantsInfoMap,
      );
      
      if (mounted) Navigator.of(context).pop(); // Dismiss loading dialog

      if (newConversationId != null) {
        logger.info("ChatListScreen",
            "Successfully created/retrieved conversation: $newConversationId");
        if (mounted) { 
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: newConversationId,
                conversationTitle: otherAgentInfo.displayName,
              ),
            ),
          );
        }
      } else {
        logger.warn("ChatListScreen",
            "Failed to create/retrieve conversation with $otherAgentCode.");
        if (mounted) { 
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    "فشل إنشاء/جلب المحادثة. قد تكون المشكلة في الاتصال أو البيانات.",
                    style: GoogleFonts.cairo())),
          );
        }
      }
    } catch (e, stackTrace) {
      if (mounted) Navigator.of(context).pop(); // Dismiss loading dialog on error
      logger.error("ChatListScreen:createNewConversation",
          "Error during conversation creation/retrieval", e, stackTrace);
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text("حدث خطأ: ${e.toString()}", style: GoogleFonts.cairo())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final agentCodeAsync = ref.watch(currentAgentCodeProvider);
    final conversationsAsyncValue = ref.watch(chatConversationsStreamProvider);
    final theme = Theme.of(context);
    final logger = ref.read(appLoggerProvider);
    final currentSearchQuery = ref.watch(chatSearchQueryProvider).toLowerCase();

    if (agentCodeAsync.isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    if (agentCodeAsync.hasError ||
        agentCodeAsync.value == null ||
        agentCodeAsync.value!.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              agentCodeAsync.hasError
                  ? "خطأ في تحميل بيانات المصادقة.\nالرجاء المحاولة مرة أخرى لاحقًا."
                  : "الرجاء تسجيل الدخول للوصول إلى قسم الدردشات.",
              style: GoogleFonts.cairo(fontSize: 17, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), 
              child: Row(
                children: [
                  Expanded(
                    child: _isSearching
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: GoogleFonts.cairo(color: theme.textTheme.bodyLarge?.color ?? (theme.brightness == Brightness.dark ? Colors.white : Colors.black)),
                            decoration: InputDecoration(
                              hintText: "بحث في الدردشات...",
                              hintStyle: GoogleFonts.cairo(color: theme.hintColor),
                              border: InputBorder.none, 
                            ))
                        : Text("الدردشات", style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.bold, color: theme.textTheme.titleLarge?.color)),
                  ),
                  IconButton(
                    icon: Icon(_isSearching ? Icons.close : Icons.search_outlined, color: theme.iconTheme.color),
                    tooltip: _isSearching ? "إغلاق البحث" : "بحث",
                    onPressed: _toggleSearch,
                  ),
                  if (!_isSearching)
                    IconButton(
                      icon: Icon(Icons.refresh_outlined, color: theme.iconTheme.color),
                      tooltip: "تحديث",
                      onPressed: () {
                        unawaited(ref.refresh(chatConversationsStreamProvider.future));
                        logger.info("ChatListScreen",
                            "Manually refreshed conversations stream.");
                        if (_isSearching) _toggleSearch();
                        _searchController.clear();
                      },
                    ),
                ],
              ),
            ),
            Expanded(
              child: conversationsAsyncValue.when(
                data: (conversations) {
                  final filteredConversations = currentSearchQuery.isEmpty
                      ? conversations
                      : conversations.where((conv) {
                          return conv.conversationTitle
                                  .toLowerCase()
                                  .contains(currentSearchQuery) ||
                              (conv.lastMessageText ?? "")
                                  .toLowerCase()
                                  .contains(currentSearchQuery);
                        }).toList();

                  if (filteredConversations.isEmpty && currentSearchQuery.isEmpty) { // Show button only if no chats and not searching
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded, size: 80, color: Colors.grey[400]),
                          const SizedBox(height: 20),
                          Text(
                            "لا توجد دردشات حتى الآن.",
                            style: GoogleFonts.cairo(
                                fontSize: 18, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add_comment_outlined),
                            label: Text("بدء محادثة جديدة", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                            onPressed: _createNewConversation,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: theme.colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                textStyle: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold)
                            ),
                          ),
                        ],
                      ),
                    );
                  } else if (filteredConversations.isEmpty && currentSearchQuery.isNotEmpty) {
                     return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[400]),
                            const SizedBox(height: 20),
                            Text(
                              "لا توجد نتائج بحث تطابق \"$currentSearchQuery\".",
                              style: GoogleFonts.cairo(fontSize: 18, color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    itemCount: filteredConversations.length,
                    itemBuilder: (context, index) {
                      final conversation = filteredConversations[index];
                      return ChatListItem(
                        conversation: conversation,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                conversationId: conversation.id,
                                conversationTitle: conversation.conversationTitle,
                              ),
                            ),
                          );
                        },
                      );
                    },
                    separatorBuilder: (context, index) => Divider(
                      height: 0.5,
                      indent: 75,
                      endIndent: 15,
                      color: theme.brightness == Brightness.dark
                          ? Colors.grey[700]
                          : Colors.grey[300],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) {
                  logger.error(
                      "ChatListScreen:StreamBuilder", "Error in stream UI", err, stack);
                  return Center(
                      child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "حدث خطأ أثناء تحميل المحادثات.\nالرجاء المحاولة مرة أخرى لاحقًا.",
                      style: GoogleFonts.cairo(color: Colors.red[400], fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ));
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewConversation,
        backgroundColor: theme.primaryColor,
        foregroundColor: theme.colorScheme.onPrimary,
        tooltip: "بدء محادثة جديدة",
        icon: const Icon(Icons.add_comment_outlined),
        label: Text("محادثة جديدة", style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

