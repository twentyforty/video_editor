import 'package:flutter/material.dart';
import 'package:video_editor/domain/entities/transform_data.dart';
import 'package:video_editor/ui/crop/crop_grid_painter.dart';
import 'package:video_editor/domain/bloc/controller.dart';
import 'package:video_editor/ui/video_viewer.dart';
import 'package:video_editor/ui/transform.dart';

enum _CropBoundaries {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  inside,
  topCenter,
  centerRight,
  centerLeft,
  bottomCenter,
  none
}

class CropGridViewer extends StatefulWidget {
  ///It is the viewer that allows you to crop the video
  CropGridViewer(
      {Key? key,
      required this.controller,
      this.showGrid = true,
      this.horizontalMargin = 0.0})
      : super(key: key);

  /// If it is true, it shows the grid and allows cropping the video, if it is false
  /// does not show the grid and cannot be cropped
  final bool showGrid;

  ///Essential argument for the functioning of the Widget
  final VideoEditorController controller;

  ///Space to put around the grid to compute when the video is rotated
  final double horizontalMargin;

  @override
  _CropGridViewerState createState() => _CropGridViewerState();
}

class _CropGridViewerState extends State<CropGridViewer> {
  final ValueNotifier<Rect> _rect = ValueNotifier<Rect>(Rect.zero);
  final ValueNotifier<TransformData> _transform = ValueNotifier<TransformData>(
    TransformData(rotation: 0.0, scale: 1.0, translate: Offset.zero),
  );

  Size _layout = Size.zero;
  Offset _margin = Offset.zero;
  _CropBoundaries _boundary = _CropBoundaries.none;

  double? _preferredCropAspectRatio;
  late VideoEditorController _controller;

  @override
  void initState() {
    _controller = widget.controller;
    final length = _controller.cropStyle.boundariesLength;
    _controller.addListener(!widget.showGrid ? _scaleRect : _updateRect);
    _margin = Offset(length, length) * 2;
    if (widget.showGrid) {
      _controller.cacheMaxCrop = _controller.maxCrop;
      _controller.cacheMinCrop = _controller.minCrop;

      // init the crop area with preferredCropAspectRatio
      WidgetsBinding.instance!.addPostFrameCallback((_) {
        _rect.value = _calculateCropRect(
          _controller.cacheMinCrop,
          _controller.cacheMaxCrop,
        );
        _updateRect();
      });
    } else {
      // init the widget with controller values if it is not the croping screen
      WidgetsBinding.instance!.addPostFrameCallback((_) {
        _scaleRect();
      });
    }

    super.initState();
  }

  @override
  void dispose() {
    _controller.removeListener(!widget.showGrid ? _scaleRect : _updateRect);
    _transform.dispose();
    _rect.dispose();
    super.dispose();
  }

  void _updateRect() {
    _transform.value = TransformData.fromController(_controller);
    if (_controller.preferredCropAspectRatio != _preferredCropAspectRatio) {
      _calculatePreferedCrop();
    } else {
      _onPanEnd(force: true);
    }
  }

  void _calculatePreferedCrop() {
    _preferredCropAspectRatio = _controller.preferredCropAspectRatio;

    if (_preferredCropAspectRatio == null) return;

    final double _rectHeight = _rect.value.height;
    final double _rectWidth = _rect.value.width;
    final bool isLandscape = _layout.height > _layout.width;

    // update crop aspect ratio
    Rect _newCrop = Rect.fromCenter(
      center: _rect.value.center,
      height: isLandscape ||
              _preferredCropAspectRatio! >= (_rectHeight / _rectWidth)
          ? _rectWidth / _preferredCropAspectRatio!
          : _rectHeight,
      width: !isLandscape ||
              _preferredCropAspectRatio! < (_rectHeight / _rectWidth)
          ? _rectHeight / _preferredCropAspectRatio!
          : _rectWidth,
    );

    // if new crop is bigger than available space, block to maximum size and avoid out of bounds
    if (_newCrop.width > _layout.width) {
      final _h = _layout.width / _preferredCropAspectRatio!;
      _newCrop = Rect.fromLTWH(
        0.0,
        _newCrop.top.clamp(0, _layout.height - _h),
        _layout.width,
        _h,
      );
    } else if (_newCrop.height > _layout.height) {
      final _w = _layout.height / _preferredCropAspectRatio!;
      _newCrop = Rect.fromLTWH(
        _newCrop.left.clamp(0, _layout.width - _w),
        0.0,
        _layout.width,
        _w,
      );
    } else {
      // if new crop is out of bounds, translate inside layout
      if (_newCrop.bottom > _layout.height) {
        _newCrop = _newCrop.translate(0, _layout.height - _newCrop.bottom);
      }
      if (_newCrop.top < 0.0) {
        _newCrop = _newCrop.translate(0, _newCrop.top.abs());
      }
      if (_newCrop.left < 0.0) {
        _newCrop = _newCrop.translate(_newCrop.left.abs(), 0);
      }
      if (_newCrop.right > _layout.width) {
        _newCrop = _newCrop.translate(_layout.width - _newCrop.right, 0);
      }
    }

    setState(() {
      _rect.value = _newCrop;
      _onPanEnd(force: true);
    });
  }

  void _scaleRect() {
    _rect.value = _calculateCropRect();
    _transform.value = TransformData.fromRect(
      _rect.value,
      _layout,
      _controller,
    );
  }

  void _onPanStart(DragStartDetails details) {
    final Offset pos = details.localPosition;
    final Offset max = _rect.value.bottomRight;
    final Offset min = _rect.value.topLeft;

    final List<Offset> minMargin = [min - _margin, min + _margin];
    final List<Offset> maxMargin = [max - _margin, max + _margin];

    if (pos >= minMargin[0] && pos <= maxMargin[1]) {
      final Rect topLeft = Rect.fromPoints(minMargin[0], minMargin[1]);
      final Rect bottomRight = Rect.fromPoints(maxMargin[0], maxMargin[1]);
      final Rect topRight = Rect.fromPoints(
        Offset(maxMargin[0].dx, minMargin[0].dy),
        Offset(maxMargin[1].dx, minMargin[1].dy),
      );
      final Rect bottomLeft = Rect.fromPoints(
        Offset(minMargin[0].dx, maxMargin[0].dy),
        Offset(minMargin[1].dx, maxMargin[1].dy),
      );

      //CORNERS
      if (pos >= topLeft.topLeft && pos <= topLeft.bottomRight) {
        _boundary = _CropBoundaries.topLeft;
      } else if (pos >= topRight.topLeft && pos <= topRight.bottomRight) {
        _boundary = _CropBoundaries.topRight;
      } else if (pos >= bottomRight.topLeft && pos <= bottomRight.bottomRight) {
        _boundary = _CropBoundaries.bottomRight;
      } else if (pos >= bottomLeft.topLeft && pos <= bottomLeft.bottomRight) {
        _boundary = _CropBoundaries.bottomLeft;
      } else if (_controller.preferredCropAspectRatio == null) {
        //CENTERS
        if (pos >= topLeft.topRight && pos <= topRight.bottomLeft) {
          _boundary = _CropBoundaries.topCenter;
        } else if (pos >= bottomLeft.topRight &&
            pos <= bottomRight.bottomLeft) {
          _boundary = _CropBoundaries.bottomCenter;
        } else if (pos >= topLeft.bottomLeft && pos <= bottomLeft.topRight) {
          _boundary = _CropBoundaries.centerLeft;
        } else if (pos >= topRight.bottomLeft && pos <= bottomRight.topRight) {
          _boundary = _CropBoundaries.centerRight;
        }
        //OTHERS
        _boundary = _CropBoundaries.inside;
      } else {
        _boundary = _CropBoundaries.inside;
      }
    } else {
      _boundary = _CropBoundaries.none;
    }
    _controller.isCropping = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_boundary != _CropBoundaries.none) {
      final Offset delta = details.delta;

      switch (_boundary) {
        case _CropBoundaries.inside:
          final Offset pos = _rect.value.topLeft + delta;
          _rect.value = Rect.fromLTWH(
              pos.dx.clamp(0, _layout.width - _rect.value.width),
              pos.dy.clamp(0, _layout.height - _rect.value.height),
              _rect.value.width,
              _rect.value.height);
          break;
        //CORNERS
        case _CropBoundaries.topLeft:
          final Offset pos = _rect.value.topLeft + delta;
          _changeRect(left: pos.dx, top: pos.dy);
          break;
        case _CropBoundaries.topRight:
          final Offset pos = _rect.value.topRight + delta;
          _changeRect(right: pos.dx, top: pos.dy);
          break;
        case _CropBoundaries.bottomRight:
          final Offset pos = _rect.value.bottomRight + delta;
          _changeRect(right: pos.dx, bottom: pos.dy);
          break;
        case _CropBoundaries.bottomLeft:
          final Offset pos = _rect.value.bottomLeft + delta;
          _changeRect(left: pos.dx, bottom: pos.dy);
          break;
        //CENTERS
        case _CropBoundaries.topCenter:
          _changeRect(top: _rect.value.top + delta.dy);
          break;
        case _CropBoundaries.bottomCenter:
          _changeRect(bottom: _rect.value.bottom + delta.dy);
          break;
        case _CropBoundaries.centerLeft:
          _changeRect(left: _rect.value.left + delta.dx);
          break;
        case _CropBoundaries.centerRight:
          _changeRect(right: _rect.value.right + delta.dx);
          break;
        case _CropBoundaries.none:
          break;
      }
    }
  }

  void _onPanEnd({bool force = false}) {
    if (_boundary != _CropBoundaries.none || force) {
      final Rect rect = _rect.value;
      _controller.cacheMinCrop = Offset(
        rect.left / _layout.width,
        rect.top / _layout.height,
      );
      _controller.cacheMaxCrop = Offset(
        rect.right / _layout.width,
        rect.bottom / _layout.height,
      );
      _controller.isCropping = false;
    }
  }

  //-----------//
  //RECT CHANGE//
  //-----------//
  void _changeRect({
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    top = (top ?? _rect.value.top).clamp(0, _rect.value.bottom - _margin.dy);
    left = (left ?? _rect.value.left).clamp(0, _rect.value.right - _margin.dx);
    right = (right ?? _rect.value.right)
        .clamp(_rect.value.left + _margin.dx, _layout.width);
    bottom = (bottom ?? _rect.value.bottom)
        .clamp(_rect.value.top + _margin.dy, _layout.height);

    // update crop height or width to adjust to the selected aspect ratio
    if (_preferredCropAspectRatio != null) {
      final width = right - left;
      final height = bottom - top;

      if (width / height > _preferredCropAspectRatio!) {
        switch (_boundary) {
          case _CropBoundaries.topLeft:
          case _CropBoundaries.bottomLeft:
            left = right - height * _preferredCropAspectRatio!;
            break;
          case _CropBoundaries.topRight:
          case _CropBoundaries.bottomRight:
            right = left + height * _preferredCropAspectRatio!;
            break;
          default:
            assert(false);
        }
      } else {
        switch (_boundary) {
          case _CropBoundaries.topLeft:
          case _CropBoundaries.topRight:
            top = bottom - width / _preferredCropAspectRatio!;
            break;
          case _CropBoundaries.bottomLeft:
          case _CropBoundaries.bottomRight:
            bottom = top + width / _preferredCropAspectRatio!;
            break;
          default:
            assert(false);
        }
      }
    }

    _rect.value = Rect.fromLTRB(left, top, right, bottom);
  }

  Rect _calculateCropRect([Offset? min, Offset? max]) {
    final Offset minCrop = min ?? _controller.minCrop;
    final Offset maxCrop = max ?? _controller.maxCrop;

    return Rect.fromPoints(
      Offset(minCrop.dx * _layout.width, minCrop.dy * _layout.height),
      Offset(maxCrop.dx * _layout.width, maxCrop.dy * _layout.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _transform,
      builder: (_, TransformData transform, __) => Center(
          child: Container(
              constraints: BoxConstraints(
                  maxHeight: ((_controller.rotation == 90 ||
                          _controller.rotation == 270))
                      ? MediaQuery.of(context).size.width -
                          widget.horizontalMargin
                      : Size.infinite.height),
              child: CropTransform(
                  transform: transform,
                  child: VideoViewer(
                    controller: _controller,
                    child: LayoutBuilder(builder: (_, constraints) {
                      Size size =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      if (_layout != size) {
                        _layout = size;
                        if (widget.showGrid) {
                          WidgetsBinding.instance!.addPostFrameCallback((_) {
                            _calculatePreferedCrop();
                          });
                        } else {
                          _rect.value = _calculateCropRect();
                        }
                      }
                      return widget.showGrid
                          ? Stack(children: [
                              _paint(),
                              GestureDetector(
                                onPanEnd: (_) => _onPanEnd(),
                                onPanStart: _onPanStart,
                                onPanUpdate: _onPanUpdate,
                                child: ValueListenableBuilder(
                                  valueListenable: _rect,
                                  builder: (_, Rect value, __) {
                                    final left = value.left - _margin.dx;
                                    final top = value.top - _margin.dy;
                                    return Container(
                                      margin: EdgeInsets.only(
                                        left: left < 0.0 ? 0.0 : left,
                                        top: top < 0.0 ? 0.0 : top,
                                      ),
                                      color: Colors.transparent,
                                      width: value.width + _margin.dx * 2,
                                      height: value.height + _margin.dy * 2,
                                    );
                                  },
                                ),
                              ),
                            ])
                          : _paint();
                    }),
                  )))),
    );
  }

  Widget _paint() {
    return ValueListenableBuilder(
      valueListenable: _rect,
      builder: (_, Rect value, __) {
        return CustomPaint(
          size: Size.infinite,
          painter: CropGridPainter(
            value,
            style: _controller.cropStyle,
            showGrid: widget.showGrid,
            showCenterRects: _controller.preferredCropAspectRatio == null,
          ),
        );
      },
    );
  }
}
