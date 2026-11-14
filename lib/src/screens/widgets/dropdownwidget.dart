import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class PaddedOverlayDropdown extends StatefulWidget {
  const PaddedOverlayDropdown({
    super.key,
    this.onOpen,
    required this.label,
    required this.value,
    required this.items,
    required this.hint,
    required this.onChanged,
    this.isLoading = false,
    this.menuHorizontalMargin = 16,
    this.maxMenuHeight = 240,
  });

  final String label;
  final String? value;
  final List<String> items;
  final String hint;
  final ValueChanged<String?> onChanged;
  final bool isLoading;
  final VoidCallback? onOpen;
  final double menuHorizontalMargin;
  final double maxMenuHeight;

  @override
  State<PaddedOverlayDropdown> createState() => _PaddedOverlayDropdownState();
}

class _PaddedOverlayDropdownState extends State<PaddedOverlayDropdown>
    with WidgetsBindingObserver {
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _entry;
  bool _suppressInsert = false;
  final ValueNotifier<bool> _open = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _remove();
    try {
      _open.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _remove();
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
    try {
      _open.value = false;
    } catch (_) {}
    _suppressInsert = true;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      _suppressInsert = false;
    });
  }

  void _toggle() {
    if (_suppressInsert) return;

    if (_entry != null) {
      _remove();
      return;
    }
    if (widget.isLoading || widget.items.isEmpty) return;

    widget.onOpen?.call();

    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final fieldSize = box.size;
    final fieldOffset = box.localToGlobal(Offset.zero);

    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final screenW = media.size.width;
    final bottomInset = media.viewInsets.bottom;

    final m = widget.menuHorizontalMargin;

    final spaceBelow =
        (screenH - bottomInset) - (fieldOffset.dy + fieldSize.height) - 6 - 8;
    final spaceAbove = fieldOffset.dy - 8;

    final openUp = spaceBelow < 160 && spaceAbove > spaceBelow;

    final maxHeight = math.min(
      widget.maxMenuHeight,
      math.max(120.0, openUp ? spaceAbove : spaceBelow),
    );

    final left = fieldOffset.dx.clamp(m, screenW - m);
    final width = fieldSize.width.clamp(0.0, screenW - 2 * m);

    final followerOffset = openUp
        ? Offset(0, -(maxHeight + 6))
        : Offset(0, fieldSize.height + 6);

    _entry = OverlayEntry(
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _remove,
          child: Stack(
            children: [
              Positioned(
                left: left,
                width: width,
                child: CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  offset: followerOffset,
                  child: GestureDetector(
                    onTap: () {}, // Prevent taps from propagating to backdrop
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        constraints: BoxConstraints(maxHeight: maxHeight),
                        decoration: BoxDecoration(
                          color: isDark
                              ? cDarkCardColor
                              : Colors.white.withAlpha(250),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(isDark ? 77 : 46),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          itemCount: widget.items.length,
                          separatorBuilder: (_, _) => Divider(
                            height: 1,
                            thickness: 1,
                            color: isDark
                                ? cDarkBorderColor
                                : Colors.black.withAlpha(15),
                          ),
                          itemBuilder: (_, i) {
                            final item = widget.items[i];
                            final selected = item == widget.value;

                            return InkWell(
                              onTap: () {
                                widget.onChanged(item);
                                _remove();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: selected
                                              ? (isDark
                                                    ? const Color(0xFF3B82F6)
                                                    : cPrimary)
                                              : (isDark
                                                    ? cDarkTextPrimary
                                                    : Colors.black87),
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        Icons.check,
                                        size: 18,
                                        color: isDark
                                            ? const Color(0xFF3B82F6)
                                            : cPrimary,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    Overlay.of(context).insert(_entry!);
    try {
      _open.value = true;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected =
        widget.value != null && widget.items.contains(widget.value);
    final displayText = isSelected ? widget.value! : widget.hint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: isDark ? cDarkTextPrimary : const Color(0xFF374151),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        CompositedTransformTarget(
          link: _link,
          child: InkWell(
            key: _fieldKey,
            borderRadius: BorderRadius.circular(14),
            onTap: _toggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? cDarkInputFillColor
                    : Colors.white.withAlpha(153),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? cDarkBorderColor
                      : Colors.white.withAlpha(179),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: widget.isLoading
                        ? Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    const Color(0xFF007AFF),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Loading...',
                                style: TextStyle(
                                  color: isDark
                                      ? cDarkTextSecondary
                                      : Colors.grey.shade600,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            displayText,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: isSelected
                                  ? (isDark
                                        ? cDarkTextPrimary
                                        : const Color(0xff111827))
                                  : (isDark ? cDarkTextSecondary : Colors.grey),
                            ),
                          ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _open,
                    builder: (_, open, _) {
                      return Icon(
                        open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark
                            ? cDarkIconColor
                            : const Color(0xFF6B7280),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
