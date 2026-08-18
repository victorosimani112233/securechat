import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class VideoStreamView extends StatelessWidget {
  const VideoStreamView({
    super.key,
    required this.renderer,
    this.mirror = false,
  });

  final RTCVideoRenderer renderer;
  final bool mirror;

  @override
  Widget build(BuildContext context) => RTCVideoView(
    renderer,
    mirror: mirror,
    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );
}
