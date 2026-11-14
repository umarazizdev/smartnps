import 'package:flutter/material.dart';

abstract final class NpsWizardColors {
  static const background = Color(0xFF0B192D);
  static const backgroundTop = Color(0xFF10233C);
  static const backgroundBottom = Color(0xFF071222);
  static const panel = Color(0xFF142B46);
  static const panelBottom = Color(0xFF10233B);
  static const surface = Color(0xFF172E4C);
  static const surfaceBorder = Color(0xFF496B94);
  static const focusedBorder = Color(0xFF76B5FF);
  static const heading = Color(0xFFF8FAFF);
  static const body = Color(0xFFCAD5E7);
  static const secondary = Color(0xFFB6C8E0);
  static const hint = Color(0xFFA1B3CD);
  static const inputIcon = Color(0xFFA3B8D2);
  static const blueTop = Color(0xFF2F9BFF);
  static const blueMid = Color(0xFF157BFC);
  static const blueBottom = Color(0xFF065AF0);
  static const success = Color(0xFF39CFA1);
  static const error = Color(0xFFFF858E);
  static const warning = Color(0xFFFFC876);

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, background, backgroundBottom],
    stops: [0, 0.46, 1],
  );

  static const panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [panel, panelBottom],
  );

  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [blueTop, blueMid, blueBottom],
  );
}

abstract final class NpsWizardTheme {
  static final ThemeData data = _build();

  static ThemeData _build() {
    final base = ThemeData.dark(useMaterial3: true);
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(15)),
      borderSide: BorderSide(color: NpsWizardColors.surfaceBorder),
    );
    const focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(15)),
      borderSide: BorderSide(color: NpsWizardColors.focusedBorder, width: 1.4),
    );
    return base.copyWith(
      scaffoldBackgroundColor: NpsWizardColors.background,
      colorScheme: const ColorScheme.dark(
        primary: NpsWizardColors.blueMid,
        onPrimary: Colors.white,
        secondary: NpsWizardColors.focusedBorder,
        onSecondary: NpsWizardColors.background,
        surface: NpsWizardColors.panel,
        onSurface: NpsWizardColors.heading,
        error: NpsWizardColors.error,
        onError: NpsWizardColors.background,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: NpsWizardColors.body,
        displayColor: NpsWizardColors.heading,
      ),
      iconTheme: const IconThemeData(color: NpsWizardColors.inputIcon),
      dividerColor: NpsWizardColors.surfaceBorder.withValues(alpha: 0.4),
      cardColor: NpsWizardColors.panel,
      dialogTheme: const DialogThemeData(
        backgroundColor: NpsWizardColors.panel,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: NpsWizardColors.surface,
        hintStyle: TextStyle(color: NpsWizardColors.hint),
        labelStyle: TextStyle(color: NpsWizardColors.secondary),
        floatingLabelStyle: TextStyle(color: NpsWizardColors.focusedBorder),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: focusBorder,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: NpsWizardColors.focusedBorder,
        selectionColor: NpsWizardColors.blueMid.withValues(alpha: 0.35),
        selectionHandleColor: NpsWizardColors.focusedBorder,
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        checkColor: WidgetStateProperty.all(Colors.white),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? NpsWizardColors.blueMid
              : NpsWizardColors.surface,
        ),
        side: const BorderSide(
          color: NpsWizardColors.surfaceBorder,
          width: 1.3,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: NpsWizardColors.focusedBorder,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NpsWizardColors.blueMid,
          foregroundColor: Colors.white,
          disabledBackgroundColor: NpsWizardColors.surface,
          disabledForegroundColor: NpsWizardColors.hint,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NpsWizardColors.panel,
        contentTextStyle: const TextStyle(color: NpsWizardColors.heading),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: NpsWizardColors.surfaceBorder.withValues(alpha: 0.7),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
