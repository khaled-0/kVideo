import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'gen/pigeon.g.dart';
import 'player_controller.dart';

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

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: controller.id,
        layoutDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        creationParamsCodec: PlayerControllerApi.pigeonChannelCodec,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      if (controller.androidViewMode == AndroidViewMode.texture) {
        return ValueListenableBuilder(
          valueListenable: controller.textureParams,
          builder: (_, value, _) {
            if (value.size.isEmpty) return const SizedBox();
            return FittedBox(
              fit: value.fit == BoxFitMode.fill ? BoxFit.cover : BoxFit.contain,
              child: SizedBox.fromSize(
                size: value.size,
                child: Texture(textureId: value.textureId ?? -1),
              ),
            );
          },
        );
      }

      /// AndroidView issue: https://github.com/flutter/flutter/issues/154613
      return PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const {},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (params) {
          final view = PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: viewType,
            creationParams: controller.id,
            layoutDirection:
                Directionality.maybeOf(context) ?? TextDirection.ltr,
            creationParamsCodec: PlayerControllerApi.pigeonChannelCodec,
            onFocus: () => params.onFocusChanged(true),
          );
          view.addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
          view.create();
          return view;
        },
      );
    }

    throw UnimplementedError("Unsupported platform: $defaultTargetPlatform");
  }
}
