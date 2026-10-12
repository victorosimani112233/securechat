import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/native_bridge.dart';

/// Tek gosterimlik icerigi gosteren ekranlari sarar: acikken ekran
/// goruntusu/kaydi engeli (FLAG_SECURE) debug derlemesinin QA istisnasina
/// ragmen zorlanir, kapaninca normal politikaya donulur.
///
/// Onceden goruntuleyici "ekran korumali" yaziyordu ama korumayi kendisi
/// zorlamiyordu; debug derlemede `screencap` icerigi yakaladi (QA 2026-10-12
/// Bulgu 16). Release derlemede FLAG_SECURE zaten varsayilan acik.
class ViewOnceScreenProtection extends StatefulWidget {
  const ViewOnceScreenProtection({
    super.key,
    required this.child,
    this.enabled = true,
    this.bridge = const NativeBridge(),
  });

  final Widget child;
  final bool enabled;
  final NativeBridge bridge;

  @override
  State<ViewOnceScreenProtection> createState() =>
      _ViewOnceScreenProtectionState();
}

class _ViewOnceScreenProtectionState extends State<ViewOnceScreenProtection> {
  bool _forced = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      _forced = true;
      unawaited(widget.bridge.enableScreenProtectionForced());
    }
  }

  @override
  void dispose() {
    if (_forced) unawaited(widget.bridge.releaseForcedScreenProtection());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
