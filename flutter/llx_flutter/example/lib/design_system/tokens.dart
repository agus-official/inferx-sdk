import 'package:flutter/material.dart';

/// 基础设计 Tokens：集中管理颜色、圆角、阴影、间距与动效
/// 通过修改这里的值即可快速调整整体风格
class AppColors {
  AppColors._();

  // 语义色
  static const Color primary = Color(0xFFF2F3F5); // 白色系·高亮
  static const Color secondary = Color(0xFFE6E9EF); // 白色系·次级
  static const Color success = Color(0xFF36C78A);
  static const Color warning = Color(0xFFFFC857);
  static const Color danger = Color(0xFFFF6B6B);

  // 暗色背景层级（可根据品牌调节）
  static const Color bg = Color(0xFF0A0B0D);
  static const Color surface = Color(0xFF121417);
  static const Color surfaceHigh = Color(0xFF1A1D22);
  static const Color outline = Color(0xFF2A2F36);

  // 文本
  static const Color textPrimary = Color(0xFFF2F3F5);
  static const Color textSecondary = Color(0xFFB8BDC7);
}

class AppRadius {
  AppRadius._();
  static const double s = 6;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
}

class AppShadow {
  AppShadow._();
  static List<BoxShadow> elevation1 = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withOpacity(0.12),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];
  static List<BoxShadow> elevationUp = <BoxShadow>[
    BoxShadow(
      color: Colors.black.withOpacity(0.16),
      blurRadius: 10,
      offset: const Offset(0, -2),
    ),
  ];
}

class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);
  static const Curve ease = Curves.easeInOut;
}
