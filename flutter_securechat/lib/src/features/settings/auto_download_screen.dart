import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/app_container.dart';
import '../../storage/storage_management_service.dart';
import '../../widgets/azure_backdrop.dart';

class AutoDownloadScreen extends StatefulWidget {
  const AutoDownloadScreen({super.key});
  @override
  State<AutoDownloadScreen> createState() => _AutoDownloadScreenState();
}

class _AutoDownloadScreenState extends State<AutoDownloadScreen> {
  AutoDownloadPolicy? _policy;
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
    final policy = await service.loadPolicy();
    if (mounted) setState(() => _policy = policy);
  }

  Future<void> _save(AutoDownloadPolicy next) async {
    final service = _service;
    if (service == null) return;
    setState(() => _policy = next);
    await service.savePolicy(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = _policy;
    return AzureBackdrop(
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.settings_auto_download)),
        body: _service == null
            ? Center(child: Text(context.l10n.storage_service_unavailable))
            : p == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  _Header(context.l10n.over_wifi),
                  _row(
                    context.l10n.photos,
                    p.photosOnWifi,
                    (v) => _save(p.copyWith(photosOnWifi: v)),
                  ),
                  _row(
                    context.l10n.videos,
                    p.videosOnWifi,
                    (v) => _save(p.copyWith(videosOnWifi: v)),
                  ),
                  _row(
                    context.l10n.documents,
                    p.documentsOnWifi,
                    (v) => _save(p.copyWith(documentsOnWifi: v)),
                  ),
                  const Divider(),
                  _Header(context.l10n.over_cellular),
                  _row(
                    context.l10n.photos,
                    p.photosOnCellular,
                    (v) => _save(p.copyWith(photosOnCellular: v)),
                  ),
                  _row(
                    context.l10n.videos,
                    p.videosOnCellular,
                    (v) => _save(p.copyWith(videosOnCellular: v)),
                  ),
                  _row(
                    context.l10n.documents,
                    p.documentsOnCellular,
                    (v) => _save(p.copyWith(documentsOnCellular: v)),
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(
                      context.l10n.cellular_limit(
                        p.maxAutoDownloadBytes ~/ (1024 * 1024),
                      ),
                    ),
                    subtitle: Slider(
                      value: (p.maxAutoDownloadBytes / (1024 * 1024)).clamp(
                        1,
                        100,
                      ),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '${p.maxAutoDownloadBytes ~/ (1024 * 1024)} MB',
                      onChanged: (value) => setState(
                        () => _policy = p.copyWith(
                          maxAutoDownloadBytes: value.round() * 1024 * 1024,
                        ),
                      ),
                      onChangeEnd: (value) => _save(
                        p.copyWith(
                          maxAutoDownloadBytes: value.round() * 1024 * 1024,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _row(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(title: Text(label), value: value, onChanged: onChanged);
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
