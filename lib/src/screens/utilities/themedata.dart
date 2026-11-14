import 'package:flutter/material.dart';
import 'package:smartnps360/src/screens/utilities/const.dart';

final ThemeData appTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'PTSans',
  brightness: Brightness.light,
  scaffoldBackgroundColor: cBackground,
  colorScheme: ColorScheme.fromSeed(
    seedColor: cPrimary,
    primary: cPrimary,
    secondary: cOrange,
    brightness: Brightness.light,
  ),

  // ✅ iOS-friendly font scale
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 34, // iOS Large Title
      letterSpacing: 0,
    ),
    displayMedium: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 28, // Title 1
    ),
    displaySmall: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 22, // Title 2
    ),
    headlineLarge: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 20, // Title 3
    ),
    headlineMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 17, // Headline
    ),
    headlineSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 15, // Subheadline
    ),
    titleLarge: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 17, // Body (emphasized)
    ),
    titleMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 17, // Body
      letterSpacing: 0,
    ),
    titleSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 15, // Callout
      letterSpacing: 0,
    ),
    bodyLarge: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 17, // Body
      letterSpacing: 0,
    ),
    bodyMedium: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 15, // Subheadline-like body
      letterSpacing: 0,
    ),
    bodySmall: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 13, // Footnote
      letterSpacing: 0,
    ),
    labelLarge: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 15, // Buttons
      letterSpacing: 0,
    ),
    labelMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 13,
      letterSpacing: 0,
    ),
    labelSmall: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 11,
      letterSpacing: 0,
    ),
  ),
);

final ThemeData appDarkTheme = ThemeData(
  useMaterial3: true,
  fontFamily: 'PTSans',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: cDarkBackground,
  colorScheme: ColorScheme.fromSeed(
    seedColor: cOrange,
    primary: cOrange,
    secondary: cOrange,
    brightness: Brightness.dark,
    surface: cDarkCardColor,
  ),

  cardColor: cDarkCardColor,
  dividerColor: cDarkDividerColor,
  canvasColor: cDarkBackground,

  appBarTheme: AppBarTheme(
    backgroundColor: cDarkAppBarColor,
    foregroundColor: cDarkTextPrimary,
    elevation: 0,
    iconTheme: IconThemeData(color: cDarkIconColor),
  ),

  iconTheme: IconThemeData(color: cDarkIconColor),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: cDarkInputFillColor,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cDarkBorderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cDarkBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: cOrange),
    ),
  ),

  dialogTheme: DialogThemeData(
    backgroundColor: cDarkCardColor,
    surfaceTintColor: Colors.transparent,
  ),

  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: cDarkCardColor,
    surfaceTintColor: Colors.transparent,
  ),

  // ✅ iOS-friendly font scale
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 34,
      letterSpacing: 0,
      color: cDarkTextPrimary,
    ),
    displayMedium: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 28,
      color: cDarkTextPrimary,
    ),
    displaySmall: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 22,
      color: cDarkTextPrimary,
    ),
    headlineLarge: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 20,
      color: cDarkTextPrimary,
    ),
    headlineMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 17,
      color: cDarkTextPrimary,
    ),
    headlineSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 15,
      color: cDarkTextPrimary,
    ),
    titleLarge: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 17,
      color: cDarkTextPrimary,
      letterSpacing: 0,
    ),
    titleMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 17,
      letterSpacing: 0,
      color: cDarkTextPrimary,
    ),
    titleSmall: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 15,
      letterSpacing: 0,
      color: cDarkTextSecondary,
    ),
    bodyLarge: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 17,
      letterSpacing: 0,
      color: cDarkTextPrimary,
    ),
    bodyMedium: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 15,
      letterSpacing: 0,
      color: cDarkTextSecondary,
    ),
    bodySmall: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 13,
      letterSpacing: 0,
      color: cDarkTextSecondary,
    ),
    labelLarge: TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 15,
      letterSpacing: 0,
      color: cDarkTextPrimary,
    ),
    labelMedium: TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 13,
      letterSpacing: 0,
      color: cDarkTextSecondary,
    ),
    labelSmall: TextStyle(
      fontWeight: FontWeight.w400,
      fontSize: 11,
      letterSpacing: 0,
      color: cDarkTextSecondary,
    ),
  ),
);
