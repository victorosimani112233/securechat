import 'package:flutter/material.dart';

import '../../services/peer_identity_review_service.dart';
import '../../l10n/l10n.dart';

/// Injectable copy for identity review and its entry point.
class PeerIdentityReviewStrings {
  const PeerIdentityReviewStrings({
    this.title = 'Verify identity',
    this.warning =
        'A changed identity may mean account recovery, a new device, or an '
        'attack. Before approving, compare the current SHA-256 fingerprint '
        'with this person in person or through a trusted independent channel. '
        'Do not rely on a message in this chat. They can compare your '
        'fingerprint on their device too.',
    this.previous = 'Previously trusted fingerprint (SHA-256)',
    this.current = 'Current peer fingerprint (SHA-256)',
    this.local = 'Your fingerprint (SHA-256)',
    this.noPrevious = 'No previously trusted identity',
    this.unchanged = 'The current identity matches the saved identity.',
    this.confirm =
        'I compared this fingerprint through a trusted independent channel.',
    this.approve = 'Approve this identity',
    this.approved = 'Identity approved. You can return to the conversation.',
    this.stale = 'The identity changed during review. Reload and verify again.',
    this.failed =
        'Identity could not be verified. No new identity was approved.',
    this.retry = 'Reload identity',
  });

  factory PeerIdentityReviewStrings.localized(BuildContext context) {
    final l10n = context.l10n;
    return PeerIdentityReviewStrings(
      title: l10n.identity_review_title,
      warning: l10n.identity_review_warning,
      previous: l10n.identity_review_previous,
      current: l10n.identity_review_current,
      local: l10n.identity_review_local,
      noPrevious: l10n.identity_review_no_previous,
      unchanged: l10n.identity_review_unchanged,
      confirm: l10n.identity_review_confirm,
      approve: l10n.identity_review_approve,
      approved: l10n.identity_review_approved,
      stale: l10n.identity_review_stale,
      failed: l10n.identity_review_failed,
      retry: l10n.identity_review_retry,
    );
  }

  final String title;
  final String warning;
  final String previous;
  final String current;
  final String local;
  final String noPrevious;
  final String unchanged;
  final String confirm;
  final String approve;
  final String approved;
  final String stale;
  final String failed;
  final String retry;
}

class PeerIdentityReviewScreen extends StatefulWidget {
  const PeerIdentityReviewScreen({
    super.key,
    required this.service,
    required this.peerId,
    required this.peerName,
    this.strings = const PeerIdentityReviewStrings(),
  });

  final PeerIdentityReviewService service;
  final String peerId;
  final String peerName;
  final PeerIdentityReviewStrings strings;

  @override
  State<PeerIdentityReviewScreen> createState() =>
      _PeerIdentityReviewScreenState();
}

class _PeerIdentityReviewScreenState extends State<PeerIdentityReviewScreen> {
  PeerIdentityReview? _review;
  bool _loading = true;
  bool _approving = false;
  bool _confirmed = false;
  bool _approved = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _review = null;
      _confirmed = false;
      _approved = false;
      _error = null;
    });
    try {
      final review = await widget.service.reviewPeerIdentity(widget.peerId);
      if (mounted) setState(() => _review = review);
    } catch (_) {
      if (mounted) setState(() => _error = widget.strings.failed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve() async {
    final review = _review;
    if (review == null || !_confirmed || _approving) return;
    setState(() => _approving = true);
    try {
      await widget.service.approvePeerIdentity(review);
      if (mounted) setState(() => _approved = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _review = null;
          _confirmed = false;
          _error = error is PeerIdentityReviewStaleException
              ? widget.strings.stale
              : widget.strings.failed;
        });
      }
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final review = _review;
    return PopScope(
      canPop: !_approving,
      child: Scaffold(
        appBar: AppBar(title: Text(strings.title)),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    widget.peerName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Icon(Icons.security_outlined),
                  ),
                  const SizedBox(height: 8),
                  Text(strings.warning),
                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(strings.retry),
                    ),
                  ],
                  if (review != null) ...[
                    const SizedBox(height: 24),
                    _fingerprint(
                      strings.previous,
                      review.previousFingerprint ?? strings.noPrevious,
                    ),
                    const Divider(height: 32),
                    _fingerprint(strings.current, review.currentFingerprint),
                    const Divider(height: 32),
                    _fingerprint(strings.local, review.localFingerprint),
                    const SizedBox(height: 24),
                    if (!review.identityChanged) Text(strings.unchanged),
                    if (_approved)
                      Semantics(liveRegion: true, child: Text(strings.approved))
                    else ...[
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        titleAlignment: ListTileTitleAlignment.top,
                        title: Text(strings.confirm),
                        value: _confirmed,
                        onChanged: _approving
                            ? null
                            : (value) =>
                                  setState(() => _confirmed = value == true),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('identity-review-approve'),
                        onPressed: _confirmed && !_approving ? _approve : null,
                        icon: _approving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.verified_user_outlined),
                        label: Text(strings.approve),
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  Widget _fingerprint(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Directionality(
        textDirection: TextDirection.ltr,
        child: SelectableText(
          value,
          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 16),
        ),
      ),
    ],
  );
}
