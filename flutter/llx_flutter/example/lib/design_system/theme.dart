import 'package:flutter/material.dart';
import 'tokens.dart';

/// 统一应用主题：暗色与亮色模式
class AppTheme {
  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      surfaceContainerHighest: AppColors.surfaceHigh,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.outline,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: AppColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.m,
          vertical: AppSpacing.s + 4,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outline.withOpacity(0.6)),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.l),
          side: BorderSide(color: scheme.outline.withOpacity(0.6), width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.textPrimary.withOpacity(0.08),
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.l),
          ),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          hoverColor: Colors.white.withOpacity(0.04),
          focusColor: Colors.white.withOpacity(0.06),
        ),
      ),
    );
  }

  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.light(
      primary: Colors.black,
      secondary: Colors.black87,
      surface: const Color(0xFFF7F8FA),
      surfaceContainerHighest: Colors.white,
      onSurface: Colors.black,
      onSurfaceVariant: Colors.black54,
      outline: const Color(0xFFE1E5EE),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: Colors.black54),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.black12,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.l),
          ),
          side: const BorderSide(color: Color(0xFFE1E5EE)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.black54,
          hoverColor: Colors.black.withOpacity(0.04),
          focusColor: Colors.black.withOpacity(0.06),
        ),
      ),
    );
  }
}
