import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../../native_camera/capture_onboarding_step.dart';

class CaptureOnboardingCatalog {
  CaptureOnboardingCatalog._();

  static List<CaptureOnboardingStep> forCurrentPlatform() {
    if (kIsWeb) return const <CaptureOnboardingStep>[];
    if (Platform.isIOS) return iosSteps;
    if (Platform.isAndroid) return androidSteps;
    return androidSteps;
  }

  static const List<CaptureOnboardingStep> androidSteps =
      <CaptureOnboardingStep>[
    CaptureOnboardingStep(
      targetId: 'shutter',
      title: 'Take a photo',
      body: 'Tap the big round button one time to take a photo.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'shutter',
      title: 'Take a video',
      body: 'Press and hold the big button to record a video. Let go to stop.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'shutter',
      title: 'Zoom with the button',
      body: 'While you hold the button, slide it up or down to zoom in or out.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'zoom',
      title: 'Quick zoom',
      body: 'Tap the small zoom buttons (like 1x or 2x) to zoom fast.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'pinch',
      title: 'Zoom with fingers',
      body: 'Put two fingers on the screen and pinch to zoom in or out.',
      arrow: CaptureOnboardingArrow.down,
    ),
    CaptureOnboardingStep(
      targetId: 'flash',
      title: 'Flash light',
      body:
          'Tap the flash button. For photos you can pick Off, On, or Auto. '
          'For video it turns the light on or off.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'focus',
      title: 'Focus',
      body: 'Tap anywhere on the picture to make that part clear and sharp.',
      arrow: CaptureOnboardingArrow.down,
    ),
    CaptureOnboardingStep(
      targetId: 'brightness',
      title: 'Make it brighter',
      body:
          'After you tap to focus, slide your finger up or down on the sun '
          'to make the picture brighter or darker.',
      arrow: CaptureOnboardingArrow.down,
    ),
    CaptureOnboardingStep(
      targetId: 'extensions',
      title: 'Photo modes',
      body:
          'If you see buttons like STD, AUTO, HDR, or Night, tap one to '
          'help in different light.',
      arrow: CaptureOnboardingArrow.down,
    ),
    CaptureOnboardingStep(
      targetId: 'hint',
      title: 'Help text',
      body: 'This short text near the button reminds you how to take photo or video.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'close',
      title: 'Close',
      body: 'Tap X to leave. Your photo or video is saved only after you finish review.',
      arrow: CaptureOnboardingArrow.right,
    ),
  ];

  static const List<CaptureOnboardingStep> iosSteps = <CaptureOnboardingStep>[
    CaptureOnboardingStep(
      targetId: 'shutter',
      title: 'Take a photo',
      body: 'Tap the big round button one time to take a photo.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'shutter',
      title: 'Take a video',
      body: 'Press and hold the big button to record a video. Let go to stop.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'shutter',
      title: 'Zoom while recording',
      body:
          'While you hold the button to record a video, slide left. '
          'The zoom wheel opens. Keep sliding left or right to zoom in or out.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'zoom',
      title: 'Quick zoom',
      body: 'Tap the small zoom buttons (like 1x or 2x) to zoom fast.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'zoom_wheel',
      title: 'Zoom wheel',
      body:
          'Press and hold the small zoom buttons, or scroll left from them. '
          'A tall wheel opens beside them. Slide up or down on the wheel '
          'to zoom carefully.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'pinch',
      title: 'Zoom with fingers',
      body: 'Put two fingers on the screen and pinch to zoom in or out.',
      arrow: CaptureOnboardingArrow.down,
    ),
    CaptureOnboardingStep(
      targetId: 'flash',
      title: 'Flash light',
      body:
          'Tap the flash button. For photos you can pick Off, On, or Auto. '
          'For video it turns the light on or off.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'focus',
      title: 'Focus',
      body: 'Tap anywhere on the picture to make that part clear and sharp.',
      arrow: CaptureOnboardingArrow.down,
    ),
    CaptureOnboardingStep(
      targetId: 'brightness',
      title: 'Make it brighter',
      body:
          'After you tap to focus, slide your finger up or down on the sun '
          'to make the picture brighter or darker.',
      arrow: CaptureOnboardingArrow.down,
    ),
    CaptureOnboardingStep(
      targetId: 'hint',
      title: 'Help text',
      body: 'This short text near the button reminds you how to take photo or video.',
      arrow: CaptureOnboardingArrow.left,
    ),
    CaptureOnboardingStep(
      targetId: 'close',
      title: 'Close',
      body: 'Tap X to leave. Your photo or video is saved only after you finish review.',
      arrow: CaptureOnboardingArrow.right,
    ),
  ];
}
