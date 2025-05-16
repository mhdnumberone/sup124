import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../core/history/history_item.dart'; // يستخدم هذا
import '../../core/history/history_service.dart';

// --- (باقي الكود كما هو: Providers, HistoryListNotifier, HistoryTab class structure) ---
// Provider for the history list
final historyListProvider =
    StateNotifierProvider<HistoryListNotifier, List<HistoryItem>>((ref) {
  return HistoryListNotifier(ref.watch(historyServiceProvider));
});

class HistoryListNotifier extends StateNotifier<List<HistoryItem>> {
  final HistoryService _historyService;

  HistoryListNotifier(this._historyService) : super([]) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    // افترض أن _historyService.loadHistory() ترجع List<HistoryItem>
    // وأنها تتعامل مع fromJson إذا كان السجل مخزناً في JSON
    state = await _historyService.loadHistory();
  }

  Future<void> deleteItem(String id) async {
    await _historyService.deleteItem(id);
    await loadHistory();
  }

  Future<void> clearAllHistory() async {
    await _historyService.clearHistory();
    state = [];
  }
}

class HistoryTab extends ConsumerWidget {
  const HistoryTab({super.key});

  String _formatDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  void _showItemDetails(BuildContext context, HistoryItem item) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تفاصيل العملية'),
        content: SingleChildScrollView(
          child: ListBody(
            children: <Widget>[
              _buildDetailRow('الوقت:', _formatDate(item.timestamp)),
              _buildDetailRow('النوع:', item.operationDescription),
              // **التعديل هنا: استخدام originalInput**
              if (item.originalInput != null && item.originalInput!.isNotEmpty)
                _buildDetailRow(
                    'الإدخال الأصلي (للتشفير/الإخفاء):', item.originalInput!,
                    isSelectable: true),
              // **التعديل هنا: استخدام processedInput**
              if (item.processedInput != null &&
                  item.processedInput!.isNotEmpty)
                _buildDetailRow(
                    'الإدخال المُعالج (للفك/الكشف):', item.processedInput!,
                    isSelectable: true),
              if (item.coverText != null && item.coverText!.isNotEmpty)
                _buildDetailRow('نص الغطاء:', item.coverText!,
                    isSelectable: true),
              _buildDetailRow('النتيجة:', item.output, isSelectable: true),
              _buildDetailRow(
                  'استخدام كلمة مرور:', item.usedPassword ? 'نعم' : 'لا'),
              _buildDetailRow(
                  'استخدام إخفاء:', item.usedSteganography ? 'نعم' : 'لا'),
            ],
          ),
        ),
        actions: <Widget>[
          if (item.output.isNotEmpty && !item.output.startsWith('❌'))
            TextButton.icon(
              icon: const Icon(Icons.copy_outlined),
              label: const Text('نسخ النتيجة'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: item.output));
                Navigator.of(dialogContext).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('✅ تم نسخ النتيجة'),
                        duration: Duration(seconds: 2)),
                  );
                }
              },
            ),
          TextButton(
            child: const Text('إغلاق'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value,
      {bool isSelectable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: isSelectable
                ? SelectableText(value, textAlign: TextAlign.right)
                : Text(value, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  // --- (باقي الكود لـ _confirmClearHistory و build و _getOperationIcon كما هو) ---
  void _confirmClearHistory(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('مسح السجل'),
        content: const Text(
            'هل أنت متأكد من رغبتك في مسح جميع سجل العمليات؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(historyListProvider.notifier).clearAllHistory();
              Navigator.pop(dialogContext);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('🗑️ تم مسح السجل بنجاح'),
                      duration: Duration(seconds: 2)),
                );
              }
            },
            child: const Text('مسح الكل', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyList = ref.watch(historyListProvider);
    final notifier = ref.read(historyListProvider.notifier);
    final theme = Theme.of(context);

    ref.listen(historyListProvider, (_, __) {});

    if (historyList.isEmpty) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.history_toggle_off_outlined,
                  size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('لا يوجد سجل عمليات بعد',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  final tabController = DefaultTabController.of(context);
                  tabController.animateTo(0);
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('بدء عملية جديدة'),
              ),
            ],
          ),
        ),
      );
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'العمليات السابقة (${historyList.length})',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon:
                      Icon(Icons.delete_sweep_outlined, color: Colors.red[400]),
                  tooltip: 'مسح كل السجل',
                  onPressed: () => _confirmClearHistory(context, ref),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: historyList.length,
              itemBuilder: (_, index) {
                final item = historyList[index];
                return Slidable(
                  key: ValueKey(item.id),
                  endActionPane: ActionPane(
                    motion: const ScrollMotion(),
                    extentRatio: 0.25,
                    children: [
                      SlidableAction(
                        onPressed: (_) async {
                          await notifier.deleteItem(item.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم حذف العنصر'),
                                  duration: Duration(seconds: 1)),
                            );
                          }
                        },
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete_outline,
                        label: 'حذف',
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: Icon(_getOperationIcon(item.operationType),
                        color: theme.primaryColor),
                    title: Text(item.operationDescription,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      'الوقت: ${_formatDate(item.timestamp)}\nالنتيجة: ${item.output.length > 50 ? '${item.output.substring(0, 50)}...' : item.output}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios,
                        size: 16, color: Colors.grey),
                    isThreeLine: true,
                    onTap: () => _showItemDetails(context, item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getOperationIcon(OperationType type) {
    switch (type) {
      case OperationType.encryptAes:
        return Icons.enhanced_encryption_outlined;
      case OperationType.decryptAes:
        return Icons.lock_open_outlined;
      case OperationType.encodeZeroWidth:
        return Icons.visibility_off_outlined;
      case OperationType.decodeZeroWidth:
        return Icons.visibility_outlined;
      case OperationType.encryptThenHide:
        return Icons.security_outlined;
      case OperationType.revealThenDecrypt:
        return Icons.key_outlined;
      case OperationType.encryptFile:
        return Icons.attach_file_outlined; // مثال
      case OperationType.decryptFile:
        return Icons.file_open_outlined; // مثال
      case OperationType.embedImageStego:
        return Icons.image_outlined; // مثال
      case OperationType.extractImageStego:
        return Icons.image_search_outlined; // مثال
    }
  }
}
