import 'package:dope/core/constants/app_palette.dart';
import 'package:dope/core/extensions/build_context_extensions.dart';
import 'package:flutter/cupertino.dart';

class DisplayListTile extends StatelessWidget {
  final String text;
  final bool isSelected;
  final VoidCallback? onTap;

  const DisplayListTile({
    super.key,
    required this.text,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        AppPalette.selectedTileGradientColor1.withValues(alpha: 0.95),
        const Color(0xFF5BFFE8).withValues(alpha: 0.76),
        AppPalette.selectedTileGradientColor2.withValues(alpha: 0.88),
      ],
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 30,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: isSelected ? selectedGradient : null,
              border: Border.all(
                color: isSelected
                    ? CupertinoColors.white.withValues(alpha: 0.58)
                    : AppPalette.transparentColor,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF5BFFE8).withValues(alpha: 0.24),
                        blurRadius: 10,
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    style: CupertinoTheme.of(context).textTheme.textStyle
                        .copyWith(
                          fontSize: isSelected ? 16.5 : 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? context.appInverseTextColor
                              : context.appPrimaryTextColor,
                          shadows: isSelected
                              ? [
                                  Shadow(
                                    color: CupertinoColors.black.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: isSelected ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(
                    CupertinoIcons.right_chevron,
                    color: context.appInverseTextColor,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
