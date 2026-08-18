import 'package:flutter/material.dart';

import '../../media/call_models.dart';

enum CallQuality { good, fair, poor, reconnecting }

extension CallStateQuality on CallState? {
  CallQuality get callQuality => this == CallState.reconnecting
      ? CallQuality.reconnecting
      : CallQuality.good;
}

class CallQualityIndicator extends StatefulWidget {
  const CallQualityIndicator({super.key, required this.quality});
  final CallQuality quality;

  @override
  State<CallQualityIndicator> createState() => _CallQualityIndicatorState();
}

class _CallQualityIndicatorState extends State<CallQualityIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
    lowerBound: 0.3,
    upperBound: 1,
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(CallQualityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.quality == CallQuality.reconnecting) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeBars = switch (widget.quality) {
      CallQuality.good => 3,
      CallQuality.fair => 2,
      CallQuality.poor => 1,
      CallQuality.reconnecting => 0,
    };
    final color = switch (widget.quality) {
      CallQuality.good => const Color(0xFF4CAF50),
      CallQuality.fair => const Color(0xFFFFC107),
      CallQuality.poor => const Color(0xFFF44336),
      CallQuality.reconnecting => const Color(0xFFFF5722),
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) {
          final opacity = widget.quality == CallQuality.reconnecting
              ? _pulse.value
              : index < activeBars
              ? 1.0
              : 0.25;
          return Container(
            key: ValueKey('quality-bar-$index'),
            width: 3,
            height: (index + 2) * 4,
            margin: EdgeInsets.only(left: index == 0 ? 0 : 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        }),
      ),
    );
  }
}

class ReconnectingBanner extends StatelessWidget {
  const ReconnectingBanner({
    super.key,
    required this.label,
    this.disableVideoLabel,
    this.onDisableVideo,
  });

  final String label;
  final String? disableVideoLabel;
  final VoidCallback? onDisableVideo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE64A19).withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CallQualityIndicator(quality: CallQuality.reconnecting),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (disableVideoLabel != null && onDisableVideo != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: onDisableVideo,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  alignment: AlignmentDirectional.centerStart,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  backgroundColor: Colors.black26,
                ),
                child: Text(disableVideoLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
