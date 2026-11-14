import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

class CustomTextField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final double? iconSize;
  final TextInputType keyboardType;
  final bool obscureText;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.iconSize,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  late FocusNode _focusNode;
  final RxBool _isFocused = false.obs;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus != _isFocused.value) {
      _isFocused.value = _focusNode.hasFocus;

      // Auto-scroll to make field visible above keyboard
      if (_focusNode.hasFocus && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              );
            } catch (_) {
              // Ignore if not in scrollable context
            }
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final h = size.height;
    final w = size.width;
    final textTheme = Theme.of(context).textTheme;

    return Obx(
      () => Container(
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
                color: cWhite.withAlpha(230),
                size: widget.iconSize ?? h * 0.03,
              ),
              SizedBox(width: w * 0.045),
              Expanded(
                child: TextField(
                  focusNode: _focusNode,
                  controller: widget.controller,
                  keyboardType: widget.keyboardType,
                  obscureText: widget.obscureText,
                  cursorColor: cPrimary,
                  enableInteractiveSelection: true,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 15.5,
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
                      color: cWhite.withAlpha(230),
                      fontSize: 15.5,
                      fontWeight: FontWeight.w400,
                    ),
                    isCollapsed: true,
                    contentPadding: EdgeInsets.only(bottom: h * 0.002),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
