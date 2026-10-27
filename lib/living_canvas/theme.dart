import 'package:flutter/material.dart';
import 'package:inspiration_museum/living_canvas/tokens.dart';
import 'package:inspiration_museum/living_canvas/typography.dart';

/// 全局 ThemeData。页面里还写死的黑白颜色不受这里影响，
/// 要等到逐页迁移时再换成 CanvasColors。
abstract final class LivingCanvasTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: CanvasColors.text,
      onPrimary: CanvasColors.textOnInk,
      primaryContainer: CanvasColors.sunken,
      onPrimaryContainer: CanvasColors.text,
      secondary: CanvasColors.forest,
      onSecondary: CanvasColors.textOnInk,
      secondaryContainer: Color(0xFFDCE5E0),
      onSecondaryContainer: Color(0xFF16302A),
      tertiary: CanvasColors.terracotta,
      onTertiary: CanvasColors.textOnInk,
      error: CanvasColors.danger,
      onError: Colors.white,
      surface: CanvasColors.background,
      onSurface: CanvasColors.text,
      onSurfaceVariant: CanvasColors.textSecondary,
      surfaceContainerLowest: CanvasColors.surface,
      surfaceContainerLow: CanvasColors.surface,
      surfaceContainer: CanvasColors.surface,
      surfaceContainerHigh: CanvasColors.sunken,
      surfaceContainerHighest: CanvasColors.sunken,
      outline: CanvasColors.divider,
      outlineVariant: CanvasColors.divider,
      shadow: CanvasColors.text,
      scrim: CanvasColors.scrim,
      inverseSurface: CanvasColors.text,
      onInverseSurface: CanvasColors.textOnInk,
      inversePrimary: CanvasColors.goldLight,
      surfaceTint: Colors.transparent,
    );

    final textTheme = TextTheme(
      displayLarge: CanvasType.display,
      displayMedium: CanvasType.expressive,
      displaySmall: CanvasType.headline,
      headlineLarge: CanvasType.headline,
      headlineMedium: CanvasType.headline.copyWith(fontSize: 24),
      headlineSmall: CanvasType.headline.copyWith(fontSize: 22),
      titleLarge: CanvasType.title,
      titleMedium: CanvasType.titleSmall,
      titleSmall: CanvasType.titleSmall.copyWith(fontSize: 14),
      bodyLarge: CanvasType.body,
      bodyMedium: CanvasType.body,
      bodySmall: CanvasType.bodySmall,
      labelLarge: CanvasType.label,
      labelMedium: CanvasType.caption,
      labelSmall: CanvasType.overline,
    );

    const buttonSize = Size(64, 48);
    const buttonPadding = EdgeInsets.symmetric(horizontal: CanvasSpace.xl);
    const buttonShape = RoundedRectangleBorder(
      borderRadius: CanvasRadius.buttonAll,
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: CanvasRadius.inputAll,
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: CanvasColors.background,
      canvasColor: CanvasColors.background,
      dividerColor: CanvasColors.divider,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: CanvasColors.text.withValues(alpha: 0.04),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CanvasPageTransitionsBuilder(),
          TargetPlatform.iOS: CanvasPageTransitionsBuilder(),
          TargetPlatform.macOS: CanvasPageTransitionsBuilder(),
          TargetPlatform.windows: CanvasPageTransitionsBuilder(),
          TargetPlatform.linux: CanvasPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CanvasPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: CanvasColors.background,
        foregroundColor: CanvasColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: CanvasType.title,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: const DividerThemeData(
        color: CanvasColors.divider,
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        color: CanvasColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: CanvasRadius.cardAll,
          side: BorderSide(color: CanvasColors.divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CanvasColors.text,
          foregroundColor: CanvasColors.textOnInk,
          disabledBackgroundColor: CanvasColors.divider,
          disabledForegroundColor: CanvasColors.textSecondary,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: CanvasType.label,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CanvasColors.surface,
          foregroundColor: CanvasColors.text,
          elevation: 0,
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: CanvasType.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: CanvasColors.text,
          side: const BorderSide(color: CanvasColors.divider),
          minimumSize: buttonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: CanvasType.label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: CanvasColors.text,
          shape: buttonShape,
          textStyle: CanvasType.label,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: CanvasColors.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CanvasColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: CanvasSpace.lg,
          vertical: CanvasSpace.md,
        ),
        hintStyle: CanvasType.body.copyWith(color: CanvasColors.textSecondary),
        labelStyle: CanvasType.bodySmall.copyWith(
          color: CanvasColors.textSecondary,
        ),
        floatingLabelStyle: CanvasType.caption.copyWith(
          color: CanvasColors.text,
        ),
        errorStyle: CanvasType.caption.copyWith(color: CanvasColors.danger),
        border: inputBorder(CanvasColors.divider),
        enabledBorder: inputBorder(CanvasColors.divider),
        focusedBorder: inputBorder(CanvasColors.text, 1.2),
        errorBorder: inputBorder(CanvasColors.danger),
        focusedErrorBorder: inputBorder(CanvasColors.danger, 1.2),
        disabledBorder: inputBorder(CanvasColors.divider),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: CanvasColors.text,
        selectionColor: CanvasColors.gold.withValues(alpha: 0.3),
        selectionHandleColor: CanvasColors.forest,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: CanvasColors.surface,
        selectedColor: CanvasColors.text,
        side: const BorderSide(color: CanvasColors.divider),
        shape: const RoundedRectangleBorder(borderRadius: CanvasRadius.tagAll),
        labelStyle: CanvasType.bodySmall,
        secondaryLabelStyle: CanvasType.bodySmall.copyWith(
          color: CanvasColors.textOnInk,
        ),
        padding: const EdgeInsets.symmetric(horizontal: CanvasSpace.sm),
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: CanvasColors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: CanvasRadius.dialogAll,
        ),
        titleTextStyle: CanvasType.headline.copyWith(fontSize: 22),
        contentTextStyle: CanvasType.body,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: CanvasColors.surface,
        modalBackgroundColor: CanvasColors.surface,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: true,
        dragHandleColor: CanvasColors.divider,
        shape: RoundedRectangleBorder(borderRadius: CanvasRadius.sheetTop),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: CanvasColors.text,
        contentTextStyle: CanvasType.bodySmall.copyWith(
          color: CanvasColors.textOnInk,
        ),
        actionTextColor: CanvasColors.goldLight,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: CanvasRadius.buttonAll,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CanvasColors.forest,
        linearTrackColor: CanvasColors.divider,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: CanvasColors.text,
        inactiveTrackColor: CanvasColors.divider,
        thumbColor: CanvasColors.text,
        overlayColor: CanvasColors.forest.withValues(alpha: 0.12),
        trackHeight: 2,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CanvasColors.surface
              : CanvasColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CanvasColors.forest
              : CanvasColors.divider,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: CanvasColors.text,
        unselectedLabelColor: CanvasColors.textSecondary,
        labelStyle: CanvasType.label,
        unselectedLabelStyle: CanvasType.label.copyWith(
          fontWeight: FontWeight.w500,
        ),
        indicatorColor: CanvasColors.text,
        dividerColor: CanvasColors.divider,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: CanvasColors.background,
        elevation: 0,
        indicatorColor: CanvasColors.tint(CanvasColors.forest),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(CanvasType.caption),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(
          color: CanvasColors.text,
          borderRadius: CanvasRadius.tagAll,
        ),
        textStyle: CanvasType.caption.copyWith(color: CanvasColors.textOnInk),
      ),
    );
  }
}

/// 页面切换：淡入并轻微上移，返回时反过来。比系统默认的横推更安静。
class CanvasPageTransitionsBuilder extends PageTransitionsBuilder {
  const CanvasPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: CanvasMotion.enter,
      reverseCurve: CanvasMotion.exit,
    );
    final leave = CurvedAnimation(
      parent: secondaryAnimation,
      curve: CanvasMotion.standardCurve,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.6).animate(leave),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.03),
            end: Offset.zero,
          ).animate(enter),
          child: child,
        ),
      ),
    );
  }
}
