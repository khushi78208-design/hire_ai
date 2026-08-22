import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DrawerItem {
  final IconData icon;
  final String label;
  final int? index;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onTap;

  const DrawerItem({
    required this.icon,
    required this.label,
    this.index,
    this.badge,
    this.badgeColor,
    this.onTap,
  });
}

/// The one dark surface in the app. It anchors the layout and makes the
/// signed-in role obvious the moment it opens.
class AppDrawer extends StatelessWidget {
  final String name;
  final String subtitle;
  final String role;
  final int selectedIndex;
  final List<DrawerItem> items;
  final List<DrawerItem> secondaryItems;
  final void Function(int index) onSelect;

  const AppDrawer({
    super.key,
    required this.name,
    required this.subtitle,
    required this.role,
    required this.selectedIndex,
    required this.items,
    required this.secondaryItems,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final shell = Shell.of(role);
    final accent = Theme.of(context).colorScheme.primary;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Drawer(
      backgroundColor: shell,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.xl,
                Space.xl,
                Space.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Shell.onDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Shell.onDarkMuted,
                    ),
                  ),
                ],
              ),
            ),

            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Space.sm),
                children: [
                  for (final item in items)
                    _DrawerTile(
                      item: item,
                      accent: accent,
                      selected: item.index == selectedIndex,
                      onTap: () {
                        Navigator.pop(context);
                        if (item.index != null) onSelect(item.index!);
                        item.onTap?.call();
                      },
                    ),
                ],
              ),
            ),

            Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),

            Padding(
              padding: const EdgeInsets.all(Space.sm),
              child: Column(
                children: [
                  for (final item in secondaryItems)
                    _DrawerTile(
                      item: item,
                      accent: accent,
                      selected: false,
                      onTap: () {
                        Navigator.pop(context);
                        item.onTap?.call();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final DrawerItem item;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.item,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDanger = item.badgeColor == StatusColors.rejected;
    final fg = isDanger
        ? const Color(0xFFFCA5A5)
        : selected
        ? Colors.white
        : Shell.onDarkMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                Icon(item.icon, size: 20, color: fg),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: fg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (item.badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (item.badgeColor ?? accent).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      item.badge!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
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
