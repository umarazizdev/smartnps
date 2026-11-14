import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/controllers/passwordvisibiltycontroller.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class CustomPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final double? iconSize;
  final String controllerTag;
  final ValueChanged<bool>? onFocusChanged;

  const CustomPasswordField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.iconSize,
    required this.controllerTag,
    this.onFocusChanged,
  });

  @override
  State<CustomPasswordField> createState() => _CustomPasswordFieldState();
}

class _CustomPasswordFieldState extends State<CustomPasswordField>
    with WidgetsBindingObserver {
  late FocusNode _focusNode;
  late PasswordVisibilityController _controller;
  final RxBool _isFocused = false.obs;
  bool _ownsController = false;
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
    WidgetsBinding.instance.addObserver(this);

    // Lazy initialization - only register if needed
    if (Get.isRegistered<PasswordVisibilityController>(
      tag: widget.controllerTag,
    )) {
      _controller = Get.find<PasswordVisibilityController>(
        tag: widget.controllerTag,
      );
    } else {
      _controller = Get.put(
        PasswordVisibilityController(),
        tag: widget.controllerTag,
      );
      _ownsController = true;
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus != _isFocused.value) {
      _isFocused.value = _focusNode.hasFocus;

      // Notify parent about focus change for custom keyboard height
      widget.onFocusChanged?.call(_focusNode.hasFocus);

      // When field gains focus, schedule multiple scroll attempts
      if (_focusNode.hasFocus && mounted) {
        _scheduleKeyboardScroll(120);
        _scheduleKeyboardScroll(260);
      }
    }
  }

  void _scheduleKeyboardScroll(int delayMs) {
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted && _focusNode.hasFocus) {
        _scrollIntoView();
      }
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    // Keyboard metrics changed - try to scroll if this field is focused
    if (mounted && _focusNode.hasFocus) {
      final mediaKeyboardHeight = MediaQuery.of(context).viewInsets.bottom;
      final viewKeyboardHeight = View.of(context).viewInsets.bottom;
      final keyboardHeight = viewKeyboardHeight > 0
          ? viewKeyboardHeight
          : mediaKeyboardHeight;
      final keyboardVisible = keyboardHeight > 50;

      // Only scroll when keyboard becomes visible or changes size
      if (keyboardVisible) {
        _scheduleMetricsScroll();
      }
    }
  }

  void _scheduleMetricsScroll() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 70), () {
        _scrollScheduled = false;
        if (mounted && _focusNode.hasFocus) {
          _scrollIntoView();
        }
      });
    });
  }

  void _scrollIntoView() {
    if (!mounted) return;

    try {
      // Always scroll for password fields - they're typically at bottom
      _attemptScroll();
    } catch (e) {
      // Silently handle errors
    }
  }

  void _attemptScroll() {
    try {
      // Use aggressive alignment to position field near top (well above keyboard)
      Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );

      // Also try alternative scroll as backup
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _focusNode.hasFocus) {
          _tryAlternativeScroll();
        }
      });
    } catch (e) {
      _tryAlternativeScroll();
    }
  }

  void _tryAlternativeScroll() {
    try {
      final scrollable = context.findAncestorStateOfType<ScrollableState>();
      if (scrollable == null) return;

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;

      final position = renderBox.localToGlobal(Offset.zero);
      final screenHeight = MediaQuery.of(context).size.height;

      // Target: position field at 30% from top (safely above keyboard)
      final targetFieldY = screenHeight * 0.3;
      final currentFieldY = position.dy;

      // Calculate how much to scroll: move field from current Y to target Y
      final scrollDelta = currentFieldY - targetFieldY;
      final currentOffset = scrollable.position.pixels;
      final targetOffset = (currentOffset + scrollDelta).clamp(
        0.0,
        scrollable.position.maxScrollExtent,
      );

      // Only scroll if we need to move down (field is below target position)
      if (targetOffset > currentOffset && targetOffset > 0) {
        scrollable.position.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (e) {
      // Silently handle errors
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController &&
        Get.isRegistered<PasswordVisibilityController>(
          tag: widget.controllerTag,
        )) {
      Get.delete<PasswordVisibilityController>(tag: widget.controllerTag);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final w = MediaQuery.sizeOf(context).width;
    final textTheme = Theme.of(context).textTheme;

    return Obx(() {
      return Container(
        height: h * 0.063,
        width: w * 0.87,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: cWhite,
            width: _isFocused.value ? 1.8 : 1.2,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: w * 0.045),
          child: Row(
            children: [
              Icon(
                widget.icon,
                color: cWhite,

                size: widget.iconSize ?? h * 0.03,
              ),
              SizedBox(width: w * 0.045),
              Expanded(
                child: TextField(
                  focusNode: _focusNode,
                  controller: widget.controller,
                  obscureText: !_controller.isVisible.value,
                  obscuringCharacter: '•',
                  cursorColor: cPrimary,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.password],
                  style: textTheme.titleMedium?.copyWith(
                    color: cWhite,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                    hintText: widget.hintText,
                    hintStyle: textTheme.titleMedium?.copyWith(
                      fontSize: 15.5,
                      color: cWhite.withAlpha(230),
                      fontWeight: FontWeight.w400,
                    ),
                    isCollapsed: true,
                    contentPadding: EdgeInsets.only(top: h * 0.015),
                    suffixIcon: GestureDetector(
                      onTap: () => _controller.toggleVisibility(),
                      child: Icon(
                        _controller.isVisible.value
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: cWhite.withAlpha(230),
                        size: h * 0.027,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
