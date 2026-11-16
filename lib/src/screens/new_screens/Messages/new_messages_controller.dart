import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../new_models.dart';
import '../new_main_controller.dart';

class NewMessagesController extends GetxController {
  final searchText = ''.obs;
  final selectedThreadId = RxnString();
  final attachSheetOpen = false.obs;
  final emojiOpen = false.obs;
  final inputCtrl = TextEditingController();
  final threads = <NewChatThread>[].obs;
  final messages = <NewChatMessage>[].obs;

  @override
  void onInit() {
    super.onInit();
    threads.assignAll(const [
      NewChatThread(
        id: 'dispatch',
        name: 'Dispatch',
        role: 'Operations',
        lastMessage: 'Confirm lobby status.',
        timeText: 'Now',
        unreadCount: 2,
        online: true,
      ),
      NewChatThread(
        id: 'manager',
        name: 'Sarah Chen',
        role: 'Site Manager',
        lastMessage: 'Please review visitor log.',
        timeText: '8:42 PM',
        unreadCount: 1,
        online: true,
      ),
      NewChatThread(
        id: 'team',
        name: 'BayCrest Team',
        role: 'Group Chat',
        lastMessage: 'North gate checked.',
        timeText: '7:18 PM',
      ),
    ]);
    messages.assignAll(const [
      NewChatMessage(
        id: 'm1',
        threadId: 'dispatch',
        text: 'Confirm lobby status.',
        timeText: 'Now',
      ),
      NewChatMessage(
        id: 'm2',
        threadId: 'dispatch',
        text: 'Lobby clear. Visitor log updated.',
        timeText: 'Now',
        mine: true,
        read: true,
      ),
      NewChatMessage(
        id: 'm3',
        threadId: 'manager',
        text: 'Please review visitor log.',
        timeText: '8:42 PM',
      ),
      NewChatMessage(
        id: 'm4',
        threadId: 'team',
        text: 'North gate checked.',
        timeText: '7:18 PM',
        mine: true,
        delivered: true,
      ),
    ]);
  }

  @override
  void onClose() {
    if (Get.isRegistered<NewMainController>()) {
      Get.find<NewMainController>().leaveFocusedView();
    }
    inputCtrl.dispose();
    super.onClose();
  }

  void updateSearch(String value) {
    searchText.value = value.trim();
  }

  void startNewChat() {
    final id = 'new_${DateTime.now().millisecondsSinceEpoch}';
    final thread = NewChatThread(
      id: id,
      name: 'New Conversation',
      role: 'Direct',
      lastMessage: 'Start typing to send a message.',
      timeText: 'Now',
      online: true,
    );
    threads.insert(0, thread);
    openThread(thread);
  }

  void openThread(NewChatThread thread) {
    if (Get.isRegistered<NewMainController>()) {
      Get.find<NewMainController>().enterFocusedView();
    }
    selectedThreadId.value = thread.id;
    final index = threads.indexWhere((e) => e.id == thread.id);
    if (index != -1) threads[index] = thread.copyWith(unreadCount: 0);
  }

  void closeThread() {
    if (Get.isRegistered<NewMainController>()) {
      Get.find<NewMainController>().leaveFocusedView();
    }
    selectedThreadId.value = null;
    attachSheetOpen.value = false;
    emojiOpen.value = false;
  }

  void toggleAttachSheet() {
    attachSheetOpen.toggle();
    if (attachSheetOpen.value) emojiOpen.value = false;
  }

  void toggleEmoji() {
    emojiOpen.toggle();
    if (emojiOpen.value) attachSheetOpen.value = false;
  }

  void insertEmoji(String emoji) {
    inputCtrl.text = '${inputCtrl.text}$emoji';
    inputCtrl.selection = TextSelection.fromPosition(
      TextPosition(offset: inputCtrl.text.length),
    );
  }

  void sendAttachment(String label) {
    final threadId = selectedThreadId.value;
    if (threadId == null) return;
    messages.add(
      NewChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        threadId: threadId,
        text: label,
        timeText: 'Now',
        mine: true,
        attachmentLabel: label,
        read: false,
      ),
    );
    _updateThread(threadId, label);
    attachSheetOpen.value = false;
  }

  void sendLocationRequest() {
    final threadId = selectedThreadId.value;
    if (threadId == null) return;
    messages.add(
      NewChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        threadId: threadId,
        text: 'Location request sent',
        timeText: 'Now',
        mine: true,
        locationLabel: 'Location Request',
      ),
    );
    _updateThread(threadId, 'Location request sent');
    attachSheetOpen.value = false;
  }

  void sendMessage() {
    final text = inputCtrl.text.trim();
    final threadId = selectedThreadId.value;
    if (text.isEmpty || threadId == null) return;
    messages.add(
      NewChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        threadId: threadId,
        text: text,
        timeText: 'Now',
        mine: true,
      ),
    );
    inputCtrl.clear();
    _updateThread(threadId, text);
  }

  void _updateThread(String threadId, String lastMessage) {
    final index = threads.indexWhere((e) => e.id == threadId);
    if (index == -1) return;
    threads[index] = threads[index].copyWith(
      lastMessage: lastMessage,
      timeText: 'Now',
      unreadCount: 0,
    );
  }

  List<NewChatThread> get filteredThreads {
    final q = searchText.value.toLowerCase();
    if (q.isEmpty) return threads;
    return threads
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.lastMessage.toLowerCase().contains(q),
        )
        .toList();
  }

  NewChatThread? get selectedThread {
    final id = selectedThreadId.value;
    if (id == null) return null;
    return threads.firstWhereOrNull((e) => e.id == id);
  }

  List<NewChatMessage> get activeMessages {
    final id = selectedThreadId.value;
    if (id == null) return const [];
    return messages.where((e) => e.threadId == id).toList();
  }
}
