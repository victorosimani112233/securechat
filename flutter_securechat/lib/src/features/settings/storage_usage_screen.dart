import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_management_service.dart';
import '../../widgets/azure_backdrop.dart';

class StorageUsageScreen extends StatefulWidget {
  const StorageUsageScreen({super.key});
  @override
  State<StorageUsageScreen> createState() => _StorageUsageScreenState();
}

class _StorageUsageScreenState extends State<StorageUsageScreen> {
  List<ChatStorageBreakdown>? _items;
  String? _cleaning;
  StorageManagementService? _service;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    _service = AppContainerScope.of(context).storageRuntime?.service;
    final service = _service;
    if (service != null) _load(service);
  }

  Future<void> _load(StorageManagementService service) async {
    final items = await service.analyzeAll();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) => AzureBackdrop(
    child: Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings_storage_usage)),
      body: _service == null
          ? Center(child: Text(context.l10n.storage_service_unavailable))
          : _items == null
          ? const Center(child: CircularProgressIndicator())
          : _items!.isEmpty
          ? Center(child: Text(context.l10n.no_chats_yet))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items![index];
                return Card(
                  child: ListTile(
                    leading: Icon(item.isGroup ? Icons.group : Icons.person),
                    title: Text(item.displayName),
                    subtitle: Text(
                      context.l10n.storage_summary(
                        item.messageCount,
                        item.fileCount,
                        _bytes(item.totalBytes),
                      ),
                    ),
                    trailing: _cleaning == item.conversationId
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : item.fileCount == 0
                        ? null
                        : IconButton(
                            tooltip: context.l10n.clear_media,
                            icon: const Icon(Icons.cleaning_services_outlined),
                            onPressed: () => _clean(item),
                          ),
                  ),
                );
              },
            ),
    ),
  );

  Future<void> _clean(ChatStorageBreakdown item) async {
    final service = _service;
    if (service == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clear_media),
        content: Text(context.l10n.clear_media_body(item.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.cd_clear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cleaning = item.conversationId);
    await service.cleanFiles(item.conversationId);
    await _load(service);
    if (mounted) setState(() => _cleaning = null);
  }

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
