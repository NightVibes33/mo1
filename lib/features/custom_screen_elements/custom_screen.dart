import 'dart:async';

import 'package:dopi/core/extensions/build_context_extensions.dart';
import 'package:dopi/core/extensions/go_router_extensions.dart';
import 'package:dopi/core/services/audio_player_service.dart';
import 'package:dopi/features/device/models/device_action.dart';
import 'package:dopi/features/device/services/device_buttons_service_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

mixin CustomScreen<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  abstract final String routeName;
  abstract final List displayItems;
  int selectedDisplayItem = 0;
  int extraDisplayItems = 0;
  int topStatusBarHeight = 30;
  final double displayTileHeight = 30;
  final ScrollController scrollController = ScrollController();
  double get listViewEdgePadding => 4;
  EdgeInsets get listViewPadding => EdgeInsets.symmetric(
    vertical: listViewEdgePadding,
  );

  void onSelectPressed();

  void onSelectLongPress() {}

  void scrollForward() {
    if (selectedDisplayItem < displayItems.length + extraDisplayItems - 1) {
      setState(() {
        selectedDisplayItem++;
      });
      _keepSelectedItemVisible();
    }
  }

  void scrollBackward() {
    if (selectedDisplayItem > 0) {
      setState(() {
        selectedDisplayItem--;
      });
      _keepSelectedItemVisible();
    }
  }

  void _keepSelectedItemVisible() {
    if (!scrollController.hasClients) {
      return;
    }

    final position = scrollController.position;
    final viewportStart = position.pixels;
    final viewportEnd = viewportStart + position.viewportDimension;
    const edgePadding = 4.0;
    final selectedTop =
        listViewEdgePadding + selectedDisplayItem * displayTileHeight;
    final selectedBottom = selectedTop + displayTileHeight;
    double targetOffset = viewportStart;

    if (selectedBottom + edgePadding > viewportEnd) {
      targetOffset = selectedBottom + edgePadding - position.viewportDimension;
    } else if (selectedTop - edgePadding < viewportStart) {
      targetOffset = selectedTop - edgePadding;
    }

    final clampedOffset = targetOffset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ).toDouble();

    if ((clampedOffset - viewportStart).abs() < 0.5) {
      return;
    }

    unawaited(
      scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void onMenuButtonPressed() {
    context.pop();
  }

  Future<void> seekForward() async {
    await ref.read(audioPlayerServiceProvider.notifier).nextSong();
  }

  Future<void> seekBackward() async {
    await ref.read(audioPlayerServiceProvider.notifier).seekBackwards();
  }

  Future<void> deviceControlHandler(_, DeviceAction? newState) async {
    if (newState == null || context.router.locationNamed != routeName) {
      return;
    }
    switch (newState) {
      case DeviceAction.menu:
        onMenuButtonPressed();
        break;
      case DeviceAction.select:
        onSelectPressed();
        break;
      case DeviceAction.selectLongPress:
        onSelectLongPress();
        break;
      case DeviceAction.rotateForward:
        scrollForward();
        break;
      case DeviceAction.rotateBackward:
        scrollBackward();
        break;
      case DeviceAction.seekForward:
        await seekForward();
        break;
      case DeviceAction.seekBackward:
        await seekBackward();
        break;
      case DeviceAction.seekForwardLongPress:
        break;
      case DeviceAction.seekBackwardLongPress:
        break;
      case DeviceAction.playPause:
        break;
      case DeviceAction.longPressEnd:
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(deviceButtonsServiceProvider, deviceControlHandler);
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }
}
