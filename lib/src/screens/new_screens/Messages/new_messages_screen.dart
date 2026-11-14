import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/new_screens/Widgets/new_common_widgets.dart';
import '../new_models.dart';
import 'new_messages_controller.dart';

class NewMessagesScreen extends StatelessWidget {
  const NewMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(NewMessagesController());
    return NewAnimatedShell(
      child: Obx(() => AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: controller.selectedThreadId.value == null ? _ThreadList(controller: controller) : _ThreadView(controller: controller))),
    );
  }
}

class _ThreadList extends StatelessWidget {
  const _ThreadList({required this.controller});
  final NewMessagesController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('threads'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
      children: [
        Row(
          children: [
            Expanded(child: Text('Messages', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.7))),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(gradient: NewUi.accentGradient(NewUi.accent), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: NewUi.accent.withAlpha(60), blurRadius: 14)]),
              child: const Icon(Icons.edit_square, color: Colors.white, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 12),
        NewGlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: TextField(
            onChanged: controller.updateSearch,
            style: const TextStyle(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'Search messages...',
              hintStyle: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w700),
              prefixIcon: const Icon(Icons.search_rounded, color: NewUi.accent2),
              border: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Obx(
          () => Column(
            children: controller.filteredThreads.map((thread) {
              return Padding(padding: const EdgeInsets.only(bottom: 10), child: _ThreadTile(thread: thread, onTap: () => controller.openThread(thread)));
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.onTap});

  final NewChatThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NewGlassCard(
      onTap: onTap,
      highlightColor: thread.unreadCount > 0 ? NewUi.accent : null,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(gradient: NewUi.accentGradient(thread.online ? NewUi.success : NewUi.accent), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: (thread.online ? NewUi.success : NewUi.accent).withAlpha(55), blurRadius: 14)]),
                child: Center(child: Text(thread.name.split(' ').map((e) => e[0]).take(2).join(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
              ),
              if (thread.online) const Positioned(right: -2, bottom: -2, child: NewPulseDot(color: NewUi.success, size: 7)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: Text(thread.name, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.1))), Text(thread.timeText, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w800))]),
                const SizedBox(height: 4),
                Text(thread.role, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text(thread.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (thread.unreadCount > 0)
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(gradient: NewUi.accentGradient(NewUi.danger), borderRadius: BorderRadius.circular(99)), child: Text('${thread.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }
}

class _ThreadView extends StatelessWidget {
  const _ThreadView({required this.controller});
  final NewMessagesController controller;

  @override
  Widget build(BuildContext context) {
    final thread = controller.selectedThread;
    return Column(
      key: const ValueKey('thread'),
      children: [
        SafeArea(
          bottom: false,
          child: ClipRRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
                decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? NewUi.bgDark2.withAlpha(235) : Colors.white.withAlpha(245), border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withAlpha(60)))),
                child: Row(
                  children: [
                    IconButton(onPressed: controller.closeThread, icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18)),
                    Container(width: 42, height: 42, decoration: BoxDecoration(gradient: NewUi.accentGradient(thread?.online == true ? NewUi.success : NewUi.accent), borderRadius: BorderRadius.circular(14)), child: Center(child: Text(thread?.name.split(' ').map((e) => e[0]).take(2).join() ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(thread?.name ?? '', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                        Row(children: [if (thread?.online == true) const NewPulseDot(color: NewUi.success, size: 5), if (thread?.online == true) const SizedBox(width: 5), Text(thread?.online == true ? 'Online' : 'Last seen recently', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: thread?.online == true ? NewUi.success : (Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight), fontWeight: FontWeight.w800))]),
                      ]),
                    ),
                    IconButton(onPressed: () => _openInfo(context), icon: const Icon(Icons.info_outline_rounded)),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Obx(
            () => ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              children: controller.activeMessages.map((msg) => _MessageBubble(message: msg)).toList(),
            ),
          ),
        ),
        _MessageComposer(controller: controller),
      ],
    );
  }

  void _openInfo(BuildContext context) {
    Get.dialog(
      Dialog(
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: NewGlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              NewSectionTitle(title: 'Message info', icon: Icons.done_all_rounded),
              _InfoRow(title: 'Read by', value: 'Dispatch · Sarah Chen'),
              _InfoRow(title: 'Delivered to', value: 'BayCrest Team'),
              _InfoRow(title: 'Pending', value: 'No pending recipients'),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900))), Expanded(child: Text(value, textAlign: TextAlign.right, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontWeight: FontWeight.w700)))]),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final NewChatMessage message;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = message.mine ? NewUi.accent : (Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(14) : Colors.white);
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.74),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          gradient: message.mine ? NewUi.accentGradient(NewUi.accent) : null,
          color: message.mine ? null : bubbleColor,
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(message.mine ? 18 : 6), bottomRight: Radius.circular(message.mine ? 6 : 18)),
          border: message.mine ? null : Border.all(color: Theme.of(context).dividerColor.withAlpha(80)),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(18), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachmentLabel != null) _MediaChip(label: message.attachmentLabel!, mine: message.mine, icon: Icons.attach_file_rounded),
            if (message.locationLabel != null) _MediaChip(label: message.locationLabel!, mine: message.mine, icon: Icons.location_on_rounded),
            Text(message.text, style: TextStyle(color: message.mine ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.w600, height: 1.35)),
            const SizedBox(height: 5),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(message.timeText, style: TextStyle(color: message.mine ? Colors.white70 : (Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight), fontSize: 10, fontWeight: FontWeight.w800)),
              if (message.mine) ...[const SizedBox(width: 4), Icon(message.read ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: Colors.white70)],
            ]),
          ],
        ),
      ),
    );
  }
}

class _MediaChip extends StatelessWidget {
  const _MediaChip({required this.label, required this.mine, required this.icon});
  final String label;
  final bool mine;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: mine ? Colors.white.withAlpha(22) : NewUi.warning.withAlpha(22), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: mine ? Colors.white : NewUi.warning), const SizedBox(width: 5), Flexible(child: Text(label, style: TextStyle(color: mine ? Colors.white : NewUi.warning, fontWeight: FontWeight.w900, fontSize: 11)))]),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({required this.controller});
  final NewMessagesController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? NewUi.bgDark2.withAlpha(235) : Colors.white.withAlpha(245), border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withAlpha(70)))),
            child: Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _AttachSheet(controller: controller),
                    crossFadeState: controller.attachSheetOpen.value ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 220),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _EmojiRow(controller: controller),
                    crossFadeState: controller.emojiOpen.value ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 220),
                  ),
                  Row(
                    children: [
                      IconButton(onPressed: controller.toggleAttachSheet, icon: const Icon(Icons.add_circle_outline_rounded, color: NewUi.accent2)),
                      Expanded(
                        child: TextField(
                          controller: controller.inputCtrl,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(hintText: 'Write a message...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none), filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withAlpha(10) : const Color(0xFFF8FAFC), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                        ),
                      ),
                      IconButton(onPressed: controller.toggleEmoji, icon: const Icon(Icons.emoji_emotions_outlined, color: NewUi.warning)),
                      GestureDetector(onTap: controller.sendMessage, child: Container(width: 42, height: 42, decoration: BoxDecoration(gradient: NewUi.accentGradient(NewUi.accent), shape: BoxShape.circle, boxShadow: [BoxShadow(color: NewUi.accent.withAlpha(60), blurRadius: 14)]), child: const Icon(Icons.send_rounded, color: Colors.white, size: 18))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet({required this.controller});
  final NewMessagesController controller;

  @override
  Widget build(BuildContext context) {
    return NewGlassCard(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        _AttachRow(icon: Icons.photo_camera_rounded, title: 'Photo or Camera', sub: 'Take a photo or choose from device', color: NewUi.accent, onTap: () => controller.sendAttachment('Photo attached')),
        _AttachRow(icon: Icons.description_rounded, title: 'Document', sub: 'PDF, Word, or file', color: NewUi.purple, onTap: () => controller.sendAttachment('Document attached')),
        _AttachRow(icon: Icons.my_location_rounded, title: 'Share My Location', sub: 'Send current GPS coordinates', color: NewUi.success, onTap: () => controller.sendAttachment('Current location shared')),
        _AttachRow(icon: Icons.location_searching_rounded, title: 'Request Location', sub: 'Ask recipient to share location', color: NewUi.warning, onTap: controller.sendLocationRequest),
      ]),
    );
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({required this.icon, required this.title, required this.sub, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 19)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(sub, style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? NewUi.textMutedDark : NewUi.textMutedLight, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmojiRow extends StatelessWidget {
  const _EmojiRow({required this.controller});
  final NewMessagesController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: ['🙂', '👍', '🚨', '✅', '📍', '🙏'].map((e) => InkWell(onTap: () => controller.insertEmoji(e), child: Text(e, style: const TextStyle(fontSize: 24)))).toList()),
    );
  }
}
