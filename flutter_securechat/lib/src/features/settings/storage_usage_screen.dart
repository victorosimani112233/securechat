import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_management_service.dart';
import '../../widgets/azure_backdrop.dart';
import '../../widgets/azure_surface.dart';
import '../../widgets/avatar.dart';
import 'chat_storage_screen.dart';

class StorageUsageScreen extends StatefulWidget {
  const StorageUsageScreen({super.key});
  @override
  State<StorageUsageScreen> createState() => _StorageUsageScreenState();
}

class _StorageUsageScreenState extends State<StorageUsageScreen> {
  List<ChatStorageBreakdown>? _items;
  bool _failed = false;
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
    try {
      final items = await service.analyzeAll();
      if (mounted)
        setState(() {
          _items = items;
          _failed = false;
        });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) => AzureBackdrop(
    child: Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings_storage_usage)),
      body: _service == null
          ? Center(child: Text(context.l10n.storage_service_unavailable))
          : _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.l10n.storage_load_failed),
                  IconButton(
                    onPressed: () => _load(_service!),
                    tooltip: context.l10n.storage_reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            )
          : _items == null
          ? const Center(child: CircularProgressIndicator())
          : _items!.isEmpty
          ? Center(child: Text(context.l10n.no_chats_yet))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _items!.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items![index];
                return AzureSurface(
                  child: ListTile(
                    key: ValueKey('storage-chat-${item.conversationId}'),
                    leading: GeneratedAvatar(
                      name: item.displayName,
                      isGroup: item.isGroup,
                    ),
                    title: Text(item.displayName),
                    subtitle: Text(
                      context.l10n.storage_summary(
                        item.messageCount,
                        item.fileCount,
                        _bytes(item.totalBytes),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _manage(item),
                  ),
                );
              },
            ),
    ),
  );

  Future<void> _manage(ChatStorageBreakdown item) async {
    final service = _service;
    if (service == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatStorageScreen(
          conversationId: item.conversationId,
          service: service,
        ),
      ),
    );
    if (mounted) await _load(service);
  }

  static String _bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
