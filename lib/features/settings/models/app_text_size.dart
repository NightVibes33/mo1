enum AppTextSize {
  small,
  medium,
  large,
  extraLarge;

  String get title {
    switch (this) {
      case AppTextSize.small:
        return 'Small';
      case AppTextSize.medium:
        return 'Medium';
      case AppTextSize.large:
        return 'Large';
      case AppTextSize.extraLarge:
        return 'XL';
    }
  }

  double get scale {
    switch (this) {
      case AppTextSize.small:
        return 0.92;
      case AppTextSize.medium:
        return 1;
      case AppTextSize.large:
        return 1.12;
      case AppTextSize.extraLarge:
        return 1.24;
    }
  }

  AppTextSize get next {
    final values = AppTextSize.values;
    return values[(index + 1) % values.length];
  }

  static AppTextSize fromName(String? name) {
    return AppTextSize.values.firstWhere(
      (textSize) => textSize.name == name,
      orElse: () => AppTextSize.medium,
    );
  }
}
