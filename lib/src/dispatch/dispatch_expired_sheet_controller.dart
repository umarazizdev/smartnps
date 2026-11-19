import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DispatchExpiredSheetController extends GetxController {
  DispatchExpiredSheetController({required this.onSubmitted});

  static const String tag = 'dispatch-expired-sheet';

  final VoidCallback onSubmitted;

  final textController = TextEditingController();
  final errorMessage = RxnString();
  final voiceNotePath = RxnString();

  bool get hasTextNote => textController.text.trim().isNotEmpty;

  bool get hasVoiceNote {
    final path = voiceNotePath.value;
    return path != null && path.trim().isNotEmpty;
  }

  @override
  void onClose() {
    textController.dispose();
    super.onClose();
  }

  void clearError() {
    errorMessage.value = null;
  }

  void setVoicePath(String? path) {
    voiceNotePath.value = path;
    if (errorMessage.value != null) {
      errorMessage.value = null;
    }
  }

  void submit() {
    if (!hasTextNote && !hasVoiceNote) {
      errorMessage.value = 'Please add a text note or record a voice note.';
      return;
    }
    errorMessage.value = null;
    onSubmitted();
  }
}
