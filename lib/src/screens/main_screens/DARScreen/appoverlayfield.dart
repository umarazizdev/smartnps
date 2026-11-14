import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class AppOverlayDropdownFormField extends StatefulWidget {
  const AppOverlayDropdownFormField({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.items,
    required this.value,
    required this.onChanged,
    this.validator,
    this.isLoading = false,
    this.isEmptyAfterLoad = false,
    this.enabled = true,
    this.menuHorizontalMargin = 16,
    this.maxMenuHeight = 240,
    this.decoration,
  });

  final String labelText;
  final String hintText;

  /// Items shown in menu (already mapped to strings)
  final List<String> items;

  /// Selected value (string)
  final String? value;

  final ValueChanged<String?> onChanged;
  final FormFieldValidator<String>? validator;

  final bool isLoading;
  final bool isEmptyAfterLoad;
  final bool enabled;

  final double menuHorizontalMargin;
  final double maxMenuHeight;

  /// Optional InputDecoration to match your screen style
  final InputDecoration? decoration;

  @override
  State<AppOverlayDropdownFormField> createState() =>
      _AppOverlayDropdownFormFieldState();
}

class _AppOverlayDropdownFormFieldState
    extends State<AppOverlayDropdownFormField> {
  final GlobalKey _fieldKey = GlobalKey();
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _suppressInsert = false;
  final ValueNotifier<bool> _open = ValueNotifier<bool>(false);

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

  @override
  void dispose() {
    _remove();
    try {
      _open.dispose();
    } catch (_) {}
    super.dispose();
  }

  void _toggle(BuildContext context) {
    if (_suppressInsert) return;

    if (_entry != null) {
      _remove();
      return;
    }

    if (!widget.enabled || widget.isLoading || widget.items.isEmpty) return;

    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final fieldSize = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final screenW = mq.size.width;
    final keyboardH = mq.viewInsets.bottom;

    final availableBelow =
        screenH - keyboardH - (offset.dy + fieldSize.height) - 12;
    final availableAbove = offset.dy - mq.padding.top - 12;

    final maxDesired = widget.maxMenuHeight;
    final showBelow = availableBelow >= 100 || availableBelow >= availableAbove;

    final overlayH = showBelow
        ? availableBelow.clamp(100.0, maxDesired)
        : availableAbove.clamp(100.0, maxDesired);

    final m = widget.menuHorizontalMargin;
    final left = offset.dx.clamp(m, screenW - m);
    final width = fieldSize.width.clamp(0.0, screenW - 2 * m);

    final followerOffset = showBelow
        ? Offset(0, fieldSize.height + 6)
        : Offset(0, -overlayH - 6);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    _entry = OverlayEntry(
      builder: (_) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _remove,
                child: const SizedBox.shrink(),
              ),
            ),
            Positioned(
              left: left,
              width: width,
              top: 0,
              child: CompositedTransformFollower(
                link: _link,
                showWhenUnlinked: false,
                offset: followerOffset,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: BoxConstraints(maxHeight: overlayH),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E293B).withAlpha(250)
                          : Colors.white.withAlpha(250),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(38),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
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
                            ? const Color(0xFF334155)
                            : Colors.black.withAlpha(15),
                      ),
                      itemBuilder: (_, i) {
                        final item = widget.items[i];
                        final selected = widget.value == item;

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
                                                ? const Color(0xFFF1F5F9)
                                                : const Color(0xff111827)),
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
          ],
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_entry!);
    try {
      _open.value = true;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FormField<String>(
      validator: widget.validator,
      initialValue: widget.value,
      builder: (state) {
        final hasValue =
            widget.value != null &&
            widget.value!.isNotEmpty &&
            widget.items.contains(widget.value);

        // show error like normal TextFormField
        final effectiveDecoration =
            (widget.decoration ??
                    InputDecoration(
                      labelText: widget.labelText,
                      hintText: widget.hintText,
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ))
                .copyWith(errorText: state.errorText);

        final borderColor = widget.isEmptyAfterLoad
            ? Colors.orange.withAlpha(128)
            : (state.hasError
                  ? Colors.red
                  : (effectiveDecoration.enabledBorder as OutlineInputBorder?)
                        ?.borderSide
                        .color);

        return CompositedTransformTarget(
          link: _link,
          child: InkWell(
            key: _fieldKey,
            onTap: widget.enabled ? () => _toggle(context) : null,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: effectiveDecoration.copyWith(
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: borderColor ?? Colors.grey.shade300,
                    width: state.hasError ? 1.2 : 1,
                  ),
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
                                    isDark
                                        ? const Color(0xFF94A3B8)
                                        : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Loading...',
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            hasValue ? widget.value! : widget.hintText,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasValue
                                  ? (isDark
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xff111827))
                                  : (widget.isEmptyAfterLoad
                                        ? Colors.orange.shade700
                                        : (isDark
                                              ? const Color(0xFF94A3B8)
                                              : Colors.grey)),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: _open,
                    builder: (_, open, _) {
                      return Icon(
                        open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF6B7280),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
