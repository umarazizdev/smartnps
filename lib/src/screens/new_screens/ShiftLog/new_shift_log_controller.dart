import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../new_models.dart';

class NewShiftLogController extends GetxController {
  final selectedFilter = NewLogFilter.all.obs;
  final searchText = ''.obs;
  final selectedMonth = 'May 2026'.obs;
  final selectedOfficer = 'All'.obs;
  final attentionMode = false.obs;
  final incidentMode = false.obs;
  final emojiOpen = false.obs;
  final attachName = RxnString();
  final inputCtrl = TextEditingController();
  final logs = <NewShiftLogEntry>[].obs;

  final officers = const ['All', 'Hamid Khan', 'Sarah Chen', 'Dispatch', 'Michael Rivera'];
  final months = const ['March 2026', 'April 2026', 'May 2026', 'June 2026'];
  final emojis = const ['🙂', '👍', '🚨', '✅', '📍', '🙏', '🔒', '👀', '⚠️', '📝', '🚗', '🏢', '🔥', '💬', '📷', '🕒'];

  @override
  void onInit() {
    super.onInit();
    logs.assignAll(const [
      NewShiftLogEntry(id: '1', dayText: 'Today', officerName: 'Hamid Khan', timeText: '21:00', message: 'ON DUTY', isMine: true, isAuto: true, autoType: 'on-duty', colorKey: 'teal'),
      NewShiftLogEntry(id: '2', dayText: 'Today', officerName: 'Hamid Khan', timeText: '21:05', message: 'Clocked in at BayCrest lobby.', isMine: true, locationText: 'BayCrest Lobby', colorKey: 'blue'),
      NewShiftLogEntry(id: '3', dayText: 'Today', officerName: 'Sarah Chen', timeText: '21:18', message: 'Please check visitor log for unit 14B.', attention: true, colorKey: 'amber'),
      NewShiftLogEntry(id: '4', dayText: 'Today', officerName: 'Hamid Khan', timeText: '21:26', message: 'North entrance secured. No issues found.', isMine: true, attachmentName: 'north_entrance.jpg', colorKey: 'blue'),
      NewShiftLogEntry(id: '5', dayText: 'Today', officerName: 'Dispatch', timeText: '22:02', message: 'Noise complaint reported near parking level B2.', incident: true, colorKey: 'amber'),
      NewShiftLogEntry(id: '6', dayText: 'Yesterday', officerName: 'Michael Rivera', timeText: '20:42', message: 'Relief handoff completed. Keys verified.', locationText: 'Security Office', colorKey: 'purple'),
      NewShiftLogEntry(id: '7', dayText: 'Yesterday', officerName: 'Hamid Khan', timeText: '23:15', message: 'ON BREAK', isMine: true, isAuto: true, autoType: 'on-break', colorKey: 'amber'),
      NewShiftLogEntry(id: '8', dayText: 'This Week', officerName: 'Hamid Khan', timeText: 'Mon 23:12', message: 'Fire panel checked and normal.', isMine: true, attachmentName: 'fire_panel.jpg', colorKey: 'teal'),
    ]);
  }

  @override
  void onClose() {
    inputCtrl.dispose();
    super.onClose();
  }

  void changeFilter(NewLogFilter filter) {
    selectedFilter.value = filter;
  }

  void updateSearch(String value) {
    searchText.value = value.trim();
  }

  void clearSearch() {
    searchText.value = '';
  }

  void changeMonth(bool next) {
    final index = months.indexOf(selectedMonth.value);
    if (index == -1) return;
    if (next && index < months.length - 1) selectedMonth.value = months[index + 1];
    if (!next && index > 0) selectedMonth.value = months[index - 1];
  }

  void setOfficer(String officer) {
    selectedOfficer.value = officer;
    selectedFilter.value = NewLogFilter.officer;
  }

  void toggleAttention() {
    attentionMode.toggle();
    if (attentionMode.value) incidentMode.value = false;
  }

  void toggleIncident() {
    incidentMode.toggle();
    if (incidentMode.value) attentionMode.value = false;
  }

  void toggleEmoji() {
    emojiOpen.toggle();
  }

  void mockAttach() {
    attachName.value = 'attachment_ready.jpg';
  }

  void removeAttach() {
    attachName.value = null;
  }

  void insertEmoji(String emoji) {
    inputCtrl.text = '${inputCtrl.text}$emoji';
    inputCtrl.selection = TextSelection.fromPosition(TextPosition(offset: inputCtrl.text.length));
  }

  void sendLog() {
    final text = inputCtrl.text.trim();
    if (text.isEmpty && attachName.value == null) return;
    logs.insert(0, NewShiftLogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dayText: 'Today',
      officerName: 'Hamid Khan',
      timeText: 'Now',
      message: text.isEmpty ? 'Attachment added.' : text,
      isMine: true,
      attention: attentionMode.value,
      incident: incidentMode.value,
      attachmentName: attachName.value,
      colorKey: incidentMode.value || attentionMode.value ? 'amber' : 'blue',
    ));
    inputCtrl.clear();
    attachName.value = null;
    attentionMode.value = false;
    incidentMode.value = false;
    emojiOpen.value = false;
  }

  List<NewShiftLogEntry> get filteredLogs {
    Iterable<NewShiftLogEntry> result = logs;
    switch (selectedFilter.value) {
      case NewLogFilter.today:
        result = result.where((e) => e.dayText == 'Today');
        break;
      case NewLogFilter.yesterday:
        result = result.where((e) => e.dayText == 'Yesterday');
        break;
      case NewLogFilter.week:
        result = result.where((e) => e.dayText == 'Today' || e.dayText == 'Yesterday' || e.dayText == 'This Week');
        break;
      case NewLogFilter.month:
      case NewLogFilter.range:
        result = logs;
        break;
      case NewLogFilter.officer:
        if (selectedOfficer.value != 'All') result = result.where((e) => e.officerName == selectedOfficer.value);
        break;
      case NewLogFilter.attention:
        result = result.where((e) => e.attention);
        break;
      case NewLogFilter.incident:
        result = result.where((e) => e.incident);
        break;
      case NewLogFilter.all:
        break;
    }

    final q = searchText.value.toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((e) =>
          e.message.toLowerCase().contains(q) ||
          e.officerName.toLowerCase().contains(q) ||
          e.timeText.toLowerCase().contains(q) ||
          e.dayText.toLowerCase().contains(q) ||
          (e.attachmentName?.toLowerCase().contains(q) ?? false) ||
          (e.locationText?.toLowerCase().contains(q) ?? false));
    }
    return result.toList();
  }
}
