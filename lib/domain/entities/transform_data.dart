import 'package:flutter/material.dart';
import "dart:math" show pi;
import 'package:video_editor/domain/bloc/controller.dart';

class TransformData {
  TransformData({
    required this.scale,
    required this.rotation,
    required this.translate,
  });
  double rotation, scale;
  Offset translate;

  factory TransformData.fromRect(
    Rect rect,
    Size layout,
    VideoEditorController controller,
  ) {
    final double videoAspect = controller.video.value.aspectRatio;
    final double relativeAspect = rect.width / rect.height;

    final double xScale = layout.width / rect.width;
    final double yScale = layout.height / rect.height;

    // TODO: on rotation 90 or 270 the crop area is bit lower on x axis (when crop dimension is around 1:1)
    final double scale = videoAspect < 0.8
        ? relativeAspect <= 1
            ? yScale
            : xScale + videoAspect
        : relativeAspect < 0.8
            ? yScale + videoAspect
            : xScale;

    // convert degrees to radians
    final double rotation = -controller.rotation * (pi / 180.0);
    final Offset translate = Offset(
      ((layout.width - rect.width) / 2) - rect.left,
      ((layout.height - rect.height) / 2) - rect.top,
    );

    return TransformData(
      rotation: rotation,
      scale: scale,
      translate: translate,
    );
  }

  factory TransformData.fromController(
    VideoEditorController controller,
  ) {
    return TransformData(
      rotation: -controller.rotation * (pi / 180.0),
      scale: 1.0,
      translate: Offset.zero,
    );
  }
}
