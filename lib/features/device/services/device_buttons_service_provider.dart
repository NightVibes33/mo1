import 'dart:async';
import 'dart:io';

import 'package:dope/core/services/audio_player_service.dart';
import 'package:dope/features/device/models/device_action.dart';
import 'package:dope/features/settings/controller/settings_preferences_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

final deviceButtonsServiceProvider =
    NotifierProvider<DeviceButtonsServiceNotifier, DeviceAction?>(
      DeviceButtonsServiceNotifier.new,
    );

class DeviceButtonsServiceNotifier extends Notifier<DeviceAction?> {
  static const Duration _feedbackMinimumGap = Duration(milliseconds: 45);
  static const Duration _feedbackTimeout = Duration(milliseconds: 120);

  bool _feedbackInFlight = false;
  DateTime? _lastFeedbackAt;

  @override
  DeviceAction? build() {
    return null;
  }

  Future<void> buttonPressVibrate() async {
    if (!ref.read(settingsPreferencesControllerProvider).vibrate) {
      return;
    }

    if (kIsWeb || Platform.isAndroid) {
      await Vibration.vibrate(duration: 5);
    } else if (Platform.isIOS) {
      await HapticFeedback.selectionClick();
    }
  }

  Future<void> clickWheelSound() async {
    if (!kIsWeb &&
        ref.read(settingsPreferencesControllerProvider).clickWheelSound) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  void playClickFeedback() {
    final now = DateTime.now();
    if (_feedbackInFlight ||
        (_lastFeedbackAt != null &&
            now.difference(_lastFeedbackAt!) < _feedbackMinimumGap)) {
      return;
    }

    _feedbackInFlight = true;
    _lastFeedbackAt = now;
    unawaited(_runClickFeedback());
  }

  Future<void> _runClickFeedback() async {
    try {
      await Future.wait([
        buttonPressVibrate(),
        clickWheelSound(),
      ]).timeout(_feedbackTimeout);
    } catch (_) {
      // Feedback must never block or break click-wheel control.
    } finally {
      _feedbackInFlight = false;
    }
  }

  Future<void> setDeviceAction(
    DeviceAction action, {
    bool feedback = true,
  }) {
    state = null;
    state = action;
    if (feedback) {
      playClickFeedback();
    }
    return Future.value();
  }

  Future<void> playPauseButtonClick() async {
    playClickFeedback();
    await ref.read(audioPlayerServiceProvider.notifier).togglePlayback();
  }

  void resetDeviceAction() {
    state = null;
  }
}
