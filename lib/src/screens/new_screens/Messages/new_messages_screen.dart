import 'dart:math' as math;
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
      child: Obx(
        () => AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: controller.selectedThreadId.value == null
              ? _ThreadList(controller: controller)
              : _ThreadView(controller: controller),
        ),
      ),
    );
  }
}

class _ThreadList extends StatelessWidget {
  const _ThreadList({required this.controller});
  final NewMessagesController controller;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      key: const ValueKey('threads'),
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 150),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Obx(() {
                      final unread = controller.threads.fold<int>(
                        0,
                        (total, thread) => total + thread.unreadCount,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Messages',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.6,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            unread == 0
                                ? '${controller.threads.length} conversations'
                                : '$unread unread · ${controller.threads.length} conversations',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? NewUi.textMutedDark
                                      : NewUi.textMutedLight,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
                    _MessageSearch(controller: controller),
                    const SizedBox(height: 14),
                    Obx(() {
                      final threads = controller.filteredThreads;
                      if (threads.isEmpty) {
                        return const NewEmptyState(
                          title: 'No conversations found',
                          subtitle: 'Try another name or message keyword.',
                          icon: Icons.search_off_rounded,
                        );
                      }
                      return Column(
                        children: threads
                            .map(
                              (thread) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ThreadTile(
                                  thread: thread,
                                  onTap: () => controller.openThread(thread),
                                ),
                              ),
                            )
                            .toList(),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 18,
          bottom: bottomInset + 76,
          child: _NewMessageFab(onTap: controller.startNewChat),
        ),
      ],
    );
  }
}

class _MessageSearch extends StatelessWidget {
  const _MessageSearch({required this.controller});

  final NewMessagesController controller;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: dark ? Colors.white.withAlpha(9) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? Colors.white.withAlpha(18) : const Color(0xFFE3E8F0),
        ),
        boxShadow: dark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(9),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: TextField(
        onChanged: controller.updateSearch,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Search conversations',
          hintStyle: TextStyle(
            color: dark ? NewUi.textMutedDark : NewUi.textMutedLight,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: NewUi.accent,
            size: 21,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }
}

class _NewMessageFab extends StatelessWidget {
  const _NewMessageFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Start a new conversation',
      child: Tooltip(
        message: 'New conversation',
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: NewUi.accentGradient(NewUi.accent),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return Colors.white.withAlpha(30);
                }
                if (states.contains(WidgetState.focused)) {
                  return Colors.white.withAlpha(20);
                }
                return null;
              }),
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: CustomPaint(painter: _ChatPlusIconPainter()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatPlusIconPainter extends CustomPainter {
  const _ChatPlusIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24;
    final sy = size.height / 24;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * sx
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final bubble = Path()
      ..moveTo(5.5 * sx, 3.5 * sy)
      ..lineTo(18.5 * sx, 3.5 * sy)
      ..quadraticBezierTo(21.5 * sx, 3.5 * sy, 21.5 * sx, 6.5 * sy)
      ..lineTo(21.5 * sx, 14 * sy)
      ..quadraticBezierTo(21.5 * sx, 17 * sy, 18.5 * sx, 17 * sy)
      ..lineTo(10 * sx, 17 * sy)
      ..lineTo(5 * sx, 20.5 * sy)
      ..lineTo(6 * sx, 16.8 * sy)
      ..quadraticBezierTo(2.5 * sx, 16.5 * sy, 2.5 * sx, 13.3 * sy)
      ..lineTo(2.5 * sx, 6.5 * sy)
      ..quadraticBezierTo(2.5 * sx, 3.5 * sy, 5.5 * sx, 3.5 * sy)
      ..close();
    canvas.drawPath(bubble, paint);

    canvas.drawLine(Offset(9 * sx, 10 * sy), Offset(15 * sx, 10 * sy), paint);
    canvas.drawLine(Offset(12 * sx, 7 * sy), Offset(12 * sx, 13 * sy), paint);
  }

  @override
  bool shouldRepaint(covariant _ChatPlusIconPainter oldDelegate) => false;
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.onTap});

  final NewChatThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final unread = thread.unreadCount > 0;
    final muted = dark ? NewUi.textMutedDark : NewUi.textMutedLight;
    final avatarColor = thread.online ? NewUi.success : NewUi.accent;

    return Material(
      color: unread
          ? NewUi.accent.withAlpha(dark ? 18 : 9)
          : (dark ? const Color(0xFF11162A) : Colors.white),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        overlayColor: WidgetStatePropertyAll(NewUi.accent.withAlpha(18)),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unread
                  ? NewUi.accent.withAlpha(dark ? 75 : 55)
                  : (dark
                        ? Colors.white.withAlpha(18)
                        : const Color(0xFFE4E9F0)),
            ),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: NewUi.accentGradient(avatarColor),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        thread.name.split(' ').map((e) => e[0]).take(2).join(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (thread.online)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: NewUi.success,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: dark
                                ? const Color(0xFF11162A)
                                : Colors.white,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontSize: 14.5,
                                  fontWeight: unread
                                      ? FontWeight.w900
                                      : FontWeight.w800,
                                  letterSpacing: -0.15,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          thread.timeText,
                          style: TextStyle(
                            color: unread ? NewUi.accent : muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      thread.role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread
                                  ? Theme.of(context).textTheme.bodyLarge?.color
                                  : muted,
                              fontSize: 12.5,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: NewUi.danger,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${thread.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.closeThread();
      },
      child: Column(
        key: const ValueKey('thread'),
        children: [
          SafeArea(
            bottom: false,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 6, 8, 7),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? NewUi.bgDark2.withAlpha(235)
                        : Colors.white.withAlpha(245),
                    border: Border(
                      bottom: BorderSide(
                        color: Theme.of(context).dividerColor.withAlpha(60),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      NewBackButton(onPressed: controller.closeThread),
                      const SizedBox(width: 8),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: NewUi.accentGradient(
                            thread?.online == true
                                ? NewUi.success
                                : NewUi.accent,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            thread?.name
                                    .split(' ')
                                    .map((e) => e[0])
                                    .take(2)
                                    .join() ??
                                '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              thread?.name ?? '',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            Row(
                              children: [
                                if (thread?.online == true)
                                  const NewPulseDot(
                                    color: NewUi.success,
                                    size: 5,
                                  ),
                                if (thread?.online == true)
                                  const SizedBox(width: 5),
                                Text(
                                  thread?.online == true
                                      ? 'Online'
                                      : 'Last seen recently',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: thread?.online == true
                                            ? NewUi.success
                                            : (Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? NewUi.textMutedDark
                                                  : NewUi.textMutedLight),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10.5,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Obx(
              () => ListView(
                reverse: true,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                children: [
                  ...controller.activeMessages.reversed.map(
                    (msg) => _MessageBubble(message: msg),
                  ),
                  const _ChatDateDivider(label: 'Today'),
                ],
              ),
            ),
          ),
          _MessageComposer(controller: controller),
        ],
      ),
    );
  }
}

class _ChatDateDivider extends StatelessWidget {
  const _ChatDateDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: dark ? Colors.white.withAlpha(10) : const Color(0xFFE9EEF5),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: dark ? NewUi.textMutedDark : NewUi.textMutedLight,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final NewChatMessage message;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = dark
        ? Colors.white.withAlpha(14)
        : const Color(0xFFF0F3F7);
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 7),
        constraints: BoxConstraints(
          maxWidth: math.min(320, MediaQuery.sizeOf(context).width * .78),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 7),
        decoration: BoxDecoration(
          gradient: message.mine ? NewUi.accentGradient(NewUi.accent) : null,
          color: message.mine ? null : bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(17),
            topRight: const Radius.circular(17),
            bottomLeft: Radius.circular(message.mine ? 17 : 5),
            bottomRight: Radius.circular(message.mine ? 5 : 17),
          ),
          border: message.mine
              ? null
              : Border.all(color: Theme.of(context).dividerColor.withAlpha(80)),
          boxShadow: message.mine
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachmentLabel != null)
              _MediaChip(
                label: message.attachmentLabel!,
                mine: message.mine,
                icon: Icons.attach_file_rounded,
              ),
            if (message.locationLabel != null)
              _MediaChip(
                label: message.locationLabel!,
                mine: message.mine,
                icon: Icons.location_on_rounded,
              ),
            Text(
              message.text,
              style: TextStyle(
                color: message.mine
                    ? Colors.white
                    : Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.timeText,
                  style: TextStyle(
                    color: message.mine
                        ? Colors.white70
                        : (Theme.of(context).brightness == Brightness.dark
                              ? NewUi.textMutedDark
                              : NewUi.textMutedLight),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (message.mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.read ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: Colors.white70,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaChip extends StatelessWidget {
  const _MediaChip({
    required this.label,
    required this.mine,
    required this.icon,
  });
  final String label;
  final bool mine;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: mine ? Colors.white.withAlpha(22) : NewUi.warning.withAlpha(22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: mine ? Colors.white : NewUi.warning),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: mine ? Colors.white : NewUi.warning,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
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
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? NewUi.bgDark2.withAlpha(235)
                  : Colors.white.withAlpha(245),
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withAlpha(70),
                ),
              ),
            ),
            child: Obx(
              () => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _AttachSheet(controller: controller),
                    crossFadeState: controller.attachSheetOpen.value
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 220),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _EmojiRow(controller: controller),
                    crossFadeState: controller.emojiOpen.value
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 220),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _ComposerAction(
                        onTap: controller.toggleAttachSheet,
                        tooltip: 'Add attachment',
                        icon: Icons.add_rounded,
                        color: NewUi.accent,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: TextField(
                          controller: controller.inputCtrl,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: 'Message',
                            hintStyle: TextStyle(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? NewUi.textMutedDark
                                  : NewUi.textMutedLight,
                              fontSize: 13.5,
                            ),
                            suffixIcon: IconButton(
                              onPressed: controller.toggleEmoji,
                              tooltip: 'Emoji',
                              icon: Icon(
                                Icons.sentiment_satisfied_alt_rounded,
                                size: 20,
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? NewUi.textMutedDark
                                    : NewUi.textMutedLight,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(21),
                              borderSide: BorderSide(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withAlpha(65),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(21),
                              borderSide: BorderSide(
                                color: Theme.of(
                                  context,
                                ).dividerColor.withAlpha(65),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(21),
                              borderSide: const BorderSide(color: NewUi.accent),
                            ),
                            filled: true,
                            fillColor:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withAlpha(9)
                                : const Color(0xFFF5F7FA),
                            isDense: true,
                            contentPadding: const EdgeInsets.fromLTRB(
                              13,
                              10,
                              4,
                              10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: controller.sendMessage,
                          customBorder: const CircleBorder(),
                          child: Ink(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: NewUi.accentGradient(NewUi.accent),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
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

class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.onTap,
    required this.tooltip,
    required this.icon,
    required this.color,
  });

  final VoidCallback onTap;
  final String tooltip;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withAlpha(18),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, size: 21, color: color),
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
      child: Column(
        children: [
          _AttachRow(
            icon: Icons.photo_camera_rounded,
            title: 'Photo or Camera',
            sub: 'Take a photo or choose from device',
            color: NewUi.accent,
            onTap: () => controller.sendAttachment('Photo attached'),
          ),
          _AttachRow(
            icon: Icons.description_rounded,
            title: 'Document',
            sub: 'PDF, Word, or file',
            color: NewUi.purple,
            onTap: () => controller.sendAttachment('Document attached'),
          ),
          _AttachRow(
            icon: Icons.my_location_rounded,
            title: 'Share My Location',
            sub: 'Send current GPS coordinates',
            color: NewUi.success,
            onTap: () => controller.sendAttachment('Current location shared'),
          ),
          _AttachRow(
            icon: Icons.location_searching_rounded,
            title: 'Request Location',
            sub: 'Ask recipient to share location',
            color: NewUi.warning,
            onTap: controller.sendLocationRequest,
          ),
        ],
      ),
    );
  }
}

class _AttachRow extends StatelessWidget {
  const _AttachRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).brightness == Brightness.dark
        ? NewUi.textMutedDark
        : NewUi.textMutedLight;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withAlpha(28),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ['🙂', '👍', '🚨', '✅', '📍', '🙏']
            .map(
              (e) => InkWell(
                onTap: () => controller.insertEmoji(e),
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            )
            .toList(),
      ),
    );
  }
}
