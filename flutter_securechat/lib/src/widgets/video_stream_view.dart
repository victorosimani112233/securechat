import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

extension VideoRendererFrameState on RTCVideoRenderer {
  // RTCVideoValue.copyWith may retain renderVideo=false on the first resize.
  // Use the live track/texture and dimensions, not that cached flag.
  bool get hasVideoFrame => renderVideo && videoWidth > 0 && videoHeight > 0;
}

class VideoStreamView extends StatelessWidget {
  const VideoStreamView({
    super.key,
    required this.renderer,
    this.mirror = false,
    this.placeholder,
  });

  final RTCVideoRenderer renderer;
  final bool mirror;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RTCVideoValue>(
    valueListenable: renderer,
    builder: (context, value, _) =>
        !renderer.hasVideoFrame && placeholder != null
        ? placeholder!
        : RTCVideoView(
            renderer,
            mirror: mirror,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          ),
  );
}
