import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'gen/pigeon.g.dart';

enum AndroidViewMode {
  /// Renders Android View Directly. Can be interactive
  hybrid,

  /// AndroidView can't receive any touch/keyboard input
  texture,
}

class PlayerView extends StatelessWidget {
  final PlayerController controller;

  const PlayerView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    const String viewType = "dev.khaled.kvideo";

    if (controller.androidViewMode == AndroidViewMode.texture) {
      return ValueListenableBuilder(
        valueListenable: controller.textureParams,
        builder: (_, value, _) => AspectRatio(
          aspectRatio: 16 / 9,
          child: Texture(textureId: value.textureId ?? -1),
        ),
      );
    }

    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: {},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        final view = PlatformViewsService.initSurfaceAndroidView(
          id: params.id,
          viewType: viewType,
          creationParams: controller.id,
          layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          creationParamsCodec: PlayerControllerApi.pigeonChannelCodec,
          onFocus: () => params.onFocusChanged(true),
        );
        view.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
        view.create();
        return view;
      },
    );
  }
}
