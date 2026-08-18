import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class AzureTokens {
  const AzureTokens();

  static const night = Color(0xFF0D1014);
  static const nightRaise = Color(0xFF151A21);
  static const nightEdge = Color(0xFF1E242D);
  static const paper = Color(0xFFF4F2EC);
  static const paperDim = Color(0xFFEAE7DD);
  static const ink = Color(0xFF13161B);
  static const inkMute = Color(0xFF5D6570);
  static const inkSoft = Color(0xFF8A929C);
  static const frost = Color(0xFFECEEF2);
  static const frostMute = Color(0xFF9BA3AE);
  static const azure = Color(0xFF3E7BFA);
  static const azureDeep = Color(0xFF1E52D9);
  static const azureGlow = Color(0xFF5EA3FF);
  static const ok = Color(0xFF22C55E);
  static const warn = Color(0xFFFFB800);
  static const danger = Color(0xFFFF5E87);
  static const dangerDeep = Color(0xFFC0264E);

  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const cardRadius = 16.0;
  static const pillRadius = 100.0;
  static const bubbleRadius = 20.0;
}

class SecureChatTheme {
  static ThemeData light() {
    return _base(
      ColorScheme.fromSeed(
        seedColor: AzureTokens.azure,
        brightness: Brightness.light,
        surface: Colors.white,
        surfaceContainerHighest: AzureTokens.paperDim,
        error: AzureTokens.dangerDeep,
      ).copyWith(
        // The original Azure 500 with white text is 3.88:1. Azure Deep keeps
        // the same palette while meeting WCAG AA for normal button text.
        primary: AzureTokens.azureDeep,
        secondary: AzureTokens.azureDeep,
        onSurface: AzureTokens.ink,
        error: AzureTokens.dangerDeep,
      ),
    );
  }

  static ThemeData dark() {
    return _base(
      ColorScheme.fromSeed(
        seedColor: AzureTokens.azure,
        brightness: Brightness.dark,
        surface: AzureTokens.nightRaise,
        surfaceContainerHighest: AzureTokens.nightEdge,
        error: AzureTokens.danger,
      ).copyWith(
        primary: AzureTokens.azureGlow,
        onPrimary: AzureTokens.night,
        secondary: AzureTokens.azureGlow,
        onSecondary: AzureTokens.night,
        onSurface: AzureTokens.frost,
        onError: AzureTokens.night,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final textTheme = const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w700,
        fontSize: 40,
        letterSpacing: -1,
        height: 1.1,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'SpaceGrotesk',
        fontWeight: FontWeight.w600,
        fontSize: 24,
        letterSpacing: -.6,
        height: 28 / 24,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 17,
        letterSpacing: -.2,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
      bodyLarge: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w400,
        fontSize: 15,
        height: 22 / 15,
      ),
      bodyMedium: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 20 / 14,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w400,
        fontSize: 12,
      ),
      labelMedium: TextStyle(
        fontFamily: 'JetBrainsMono',
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: .5,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      textTheme: textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      scaffoldBackgroundColor: dark ? AzureTokens.night : AzureTokens.paper,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: dark ? AzureTokens.night : AzureTokens.paper,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark
            ? AzureTokens.nightRaise.withValues(alpha: .72)
            : Colors.white.withValues(alpha: .72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AzureTokens.pillRadius),
          ),
          textStyle: textTheme.titleMedium,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: dark
            ? AzureTokens.night.withValues(alpha: .95)
            : Colors.white.withValues(alpha: .95),
        indicatorColor: scheme.primary.withValues(alpha: .12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontFamily: 'Inter',
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _AzurePageTransitionsBuilder(),
          TargetPlatform.fuchsia: _AzurePageTransitionsBuilder(),
          TargetPlatform.linux: _AzurePageTransitionsBuilder(),
          TargetPlatform.windows: _AzurePageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

class _AzurePageTransitionsBuilder extends PageTransitionsBuilder {
  const _AzurePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final incoming = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    final outgoing = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-.33, 0),
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    return SlideTransition(
      position: secondaryAnimation.drive(outgoing),
      child: SlideTransition(position: animation.drive(incoming), child: child),
    );
  }
}
