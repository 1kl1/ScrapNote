import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../core/design/scrapnote_tokens.dart';
import 'scrapnote_theme.dart';

const _activityButtonStyle = FButtonStyleDelta.delta(
  focusedOutlineStyle: FFocusedOutlineStyleDelta.delta(spacing: -2),
);

enum ScrapnoteSection { scraps, notes, timeline }

/// The fixed activity rail around every Scrapnote editor workbench.
class ScrapnoteShell extends StatelessWidget {
  const ScrapnoteShell({
    required this.section,
    required this.onSectionChanged,
    required this.body,
    this.vaultPath,
    this.onChooseVault,
    super.key,
  });

  static const scrapsNavigationKey = ValueKey<String>('nav-scraps');
  static const notesNavigationKey = ValueKey<String>('nav-notes');
  static const timelineNavigationKey = ValueKey<String>('nav-timeline');
  static const vaultActionKey = ValueKey<String>('vault-action');
  static const activityRailKey = ValueKey<String>('activity-rail');
  static const bodyKey = ValueKey<String>('shell-body');

  final ScrapnoteSection section;
  final ValueChanged<ScrapnoteSection> onSectionChanged;
  final String? vaultPath;
  final VoidCallback? onChooseVault;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return FTheme(
      data: ScrapnoteTheme.foruiTheme,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.digit1, meta: true):
              _SelectSectionIntent(ScrapnoteSection.scraps),
          SingleActivator(LogicalKeyboardKey.digit2, meta: true):
              _SelectSectionIntent(ScrapnoteSection.notes),
          SingleActivator(LogicalKeyboardKey.digit3, meta: true):
              _SelectSectionIntent(ScrapnoteSection.timeline),
          SingleActivator(LogicalKeyboardKey.digit1, control: true):
              _SelectSectionIntent(ScrapnoteSection.scraps),
          SingleActivator(LogicalKeyboardKey.digit2, control: true):
              _SelectSectionIntent(ScrapnoteSection.notes),
          SingleActivator(LogicalKeyboardKey.digit3, control: true):
              _SelectSectionIntent(ScrapnoteSection.timeline),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _SelectSectionIntent: CallbackAction<_SelectSectionIntent>(
              onInvoke: (intent) {
                if (intent.section != section) {
                  onSectionChanged(intent.section);
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: FScaffold(
                childPad: false,
                child: Material(
                  color: ScrapnoteTokens.paper,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        key: activityRailKey,
                        width: ScrapnoteTokens.activityRailWidth,
                        child: _ActivityRail(
                          section: section,
                          onSectionChanged: onSectionChanged,
                          vaultPath: vaultPath,
                          onChooseVault: onChooseVault,
                        ),
                      ),
                      Expanded(
                        child: ColoredBox(
                          key: bodyKey,
                          color: ScrapnoteTokens.paper,
                          child: Semantics(
                            container: true,
                            label: '${section.label} workspace',
                            child: body,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityRail extends StatelessWidget {
  const _ActivityRail({
    required this.section,
    required this.onSectionChanged,
    required this.vaultPath,
    required this.onChooseVault,
  });

  final ScrapnoteSection section;
  final ValueChanged<ScrapnoteSection> onSectionChanged;
  final String? vaultPath;
  final VoidCallback? onChooseVault;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: ScrapnoteTokens.paperRaised,
        border: Border(
          right: BorderSide(
            color: ScrapnoteTokens.rule,
            width: ScrapnoteTokens.hairline,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            const SizedBox(height: ScrapnoteTokens.space1),
            _ActivityDestination(
              key: ScrapnoteShell.scrapsNavigationKey,
              order: 1,
              selected: section == ScrapnoteSection.scraps,
              label: ScrapnoteSection.scraps.label,
              shortcut: '1',
              icon: FLucideIcons.inbox,
              onPress: () => onSectionChanged(ScrapnoteSection.scraps),
            ),
            _ActivityDestination(
              key: ScrapnoteShell.notesNavigationKey,
              order: 2,
              selected: section == ScrapnoteSection.notes,
              label: ScrapnoteSection.notes.label,
              shortcut: '2',
              icon: FLucideIcons.notebookText,
              onPress: () => onSectionChanged(ScrapnoteSection.notes),
            ),
            _ActivityDestination(
              key: ScrapnoteShell.timelineNavigationKey,
              order: 3,
              selected: section == ScrapnoteSection.timeline,
              label: ScrapnoteSection.timeline.label,
              shortcut: '3',
              icon: FLucideIcons.calendarClock,
              onPress: () => onSectionChanged(ScrapnoteSection.timeline),
            ),
            const Spacer(),
            _VaultFooter(vaultPath: vaultPath, onChooseVault: onChooseVault),
          ],
        ),
      ),
    );
  }
}

class _ActivityDestination extends StatelessWidget {
  const _ActivityDestination({
    required this.order,
    required this.selected,
    required this.label,
    required this.shortcut,
    required this.icon,
    required this.onPress,
    super.key,
  });

  final double order;
  final bool selected;
  final String label;
  final String shortcut;
  final IconData icon;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final tooltip = '$label · ⌘/Ctrl $shortcut';

    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: AnimatedContainer(
        width: ScrapnoteTokens.activityRailWidth,
        height: ScrapnoteTokens.minimumHitTarget,
        duration: ScrapnoteTokens.quickDuration,
        curve: ScrapnoteTokens.standardCurve,
        decoration: BoxDecoration(
          color: selected
              ? ScrapnoteTokens.signalOrangeWash
              : ScrapnoteTokens.transparent,
          border: Border(
            left: BorderSide(
              color: selected
                  ? ScrapnoteTokens.signalOrange
                  : ScrapnoteTokens.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: SizedBox.square(
            dimension: ScrapnoteTokens.minimumHitTarget,
            child: Tooltip(
              message: tooltip,
              excludeFromSemantics: true,
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                size: FButtonSizeVariant.lg,
                style: _activityButtonStyle,
                selected: selected,
                semanticsLabel: label,
                semanticsTooltip: tooltip,
                onPress: onPress,
                child: Icon(
                  icon,
                  size: 18,
                  color: selected
                      ? ScrapnoteTokens.signalOrange
                      : ScrapnoteTokens.charcoalSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VaultFooter extends StatelessWidget {
  const _VaultFooter({required this.vaultPath, required this.onChooseVault});

  final String? vaultPath;
  final VoidCallback? onChooseVault;

  @override
  Widget build(BuildContext context) {
    final tooltip = vaultPath == null
        ? 'Choose local vault'
        : 'Local vault: $vaultPath';
    final semanticsLabel = vaultPath == null
        ? 'Choose local vault'
        : 'Change local vault. Current path: $vaultPath';

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: ScrapnoteTokens.rule,
            width: ScrapnoteTokens.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ScrapnoteTokens.space1),
        child: SizedBox.square(
          dimension: ScrapnoteTokens.minimumHitTarget,
          child: Tooltip(
            message: tooltip,
            excludeFromSemantics: true,
            child: FButton.icon(
              key: ScrapnoteShell.vaultActionKey,
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.lg,
              style: _activityButtonStyle,
              semanticsLabel: semanticsLabel,
              semanticsTooltip: tooltip,
              onPress: onChooseVault,
              child: Icon(
                vaultPath == null
                    ? FLucideIcons.folderOpen
                    : FLucideIcons.hardDrive,
                size: 18,
                color: onChooseVault == null
                    ? ScrapnoteTokens.mutedInk
                    : ScrapnoteTokens.charcoalSoft,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectSectionIntent extends Intent {
  const _SelectSectionIntent(this.section);

  final ScrapnoteSection section;
}

extension on ScrapnoteSection {
  String get label => switch (this) {
    ScrapnoteSection.scraps => 'Scraps',
    ScrapnoteSection.notes => 'Notes',
    ScrapnoteSection.timeline => 'Timeline',
  };
}
