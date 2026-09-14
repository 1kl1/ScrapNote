// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · Index-First workbench

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../core/design/scrapnote_tokens.dart';

/// The Notes workspace shell.
///
/// Note persistence is intentionally not implied here. Until a note repository
/// is connected, the explorer and editor present honest empty states while
/// preserving the final index-first desktop geometry.
class NotesView extends StatelessWidget {
  const NotesView({
    this.loading = false,
    this.vaultPath,
    this.onChooseVault,
    this.onCreateFolder,
    this.onCreateNote,
    super.key,
  });

  static const hierarchyPaneKey = ValueKey<String>('notes-hierarchy-pane');
  static const tabStripKey = ValueKey<String>('notes-tab-strip');

  final bool loading;
  final String? vaultPath;
  final VoidCallback? onChooseVault;
  final VoidCallback? onCreateFolder;
  final VoidCallback? onCreateNote;

  @override
  Widget build(BuildContext context) {
    if (vaultPath == null) {
      return _VaultSetup(loading: loading, onChooseVault: onChooseVault);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final document = _DocumentPane(
          loading: loading,
          onCreateNote: onCreateNote,
        );

        if (constraints.maxWidth < 760) {
          return document;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              key: hierarchyPaneKey,
              width: ScrapnoteTokens.explorerPaneWidth,
              child: _NotesExplorer(
                loading: loading,
                onCreateFolder: onCreateFolder,
              ),
            ),
            const _Hairline(axis: Axis.vertical),
            Expanded(child: document),
          ],
        );
      },
    );
  }
}

class _VaultSetup extends StatelessWidget {
  const _VaultSetup({required this.loading, required this.onChooseVault});

  final bool loading;
  final VoidCallback? onChooseVault;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScrapnoteTokens.paper,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ScrapnoteTokens.space5),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  loading ? 'Opening vault…' : 'Choose a local vault',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: ScrapnoteTokens.charcoal,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: ScrapnoteTokens.space2),
                const Text(
                  'Notes can open after a vault folder is selected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: ScrapnoteTokens.mutedInk,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                if (!loading && onChooseVault != null) ...<Widget>[
                  const SizedBox(height: ScrapnoteTokens.space5),
                  SizedBox(
                    height: ScrapnoteTokens.minimumHitTarget,
                    child: FButton(
                      variant: FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: onChooseVault,
                      prefix: const Icon(FLucideIcons.folderOpen, size: 16),
                      child: const Text('Choose vault'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesExplorer extends StatelessWidget {
  const _NotesExplorer({required this.loading, required this.onCreateFolder});

  final bool loading;
  final VoidCallback? onCreateFolder;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScrapnoteTokens.paperRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(
            height: ScrapnoteTokens.tabStripHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ScrapnoteTokens.space4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'NOTES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ScrapnoteTokens.charcoal,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
          const _Hairline(),
          _ExplorerSectionHeader(
            label: 'FOLDERS',
            action: onCreateFolder == null
                ? null
                : _ExplorerAction(
                    enabled: !loading,
                    tooltip: 'New folder',
                    icon: FLucideIcons.folderPlus,
                    onPress: onCreateFolder!,
                  ),
          ),
          if (loading)
            const _ExplorerLoadingRow(widthFactor: 0.62)
          else
            const _ExplorerEmptyRow(
              icon: FLucideIcons.folder,
              label: 'No folders yet',
            ),
          const _Hairline(),
          const _ExplorerSectionHeader(label: 'NOTES'),
          Expanded(
            child: loading
                ? const _ExplorerLoadingList()
                : const Align(
                    alignment: Alignment.topLeft,
                    child: _ExplorerEmptyRow(
                      icon: FLucideIcons.notebookText,
                      label: 'No notes yet',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExplorerSectionHeader extends StatelessWidget {
  const _ExplorerSectionHeader({required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ScrapnoteTokens.minimumHitTarget,
      child: Padding(
        padding: const EdgeInsets.only(left: ScrapnoteTokens.space4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ScrapnoteTokens.mutedInk,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.05,
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _ExplorerAction extends StatelessWidget {
  const _ExplorerAction({
    required this.enabled,
    required this.tooltip,
    required this.icon,
    required this.onPress,
  });

  final bool enabled;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: ScrapnoteTokens.minimumHitTarget,
        child: FButton.icon(
          variant: FButtonVariant.ghost,
          size: FButtonSizeVariant.sm,
          semanticsLabel: tooltip,
          onPress: enabled ? onPress : null,
          child: Icon(icon, size: 15),
        ),
      ),
    );
  }
}

class _ExplorerEmptyRow extends StatelessWidget {
  const _ExplorerEmptyRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ScrapnoteTokens.minimumHitTarget,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ScrapnoteTokens.space4),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 14, color: ScrapnoteTokens.mutedInk),
            const SizedBox(width: ScrapnoteTokens.space2),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ScrapnoteTokens.mutedInk,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorerLoadingRow extends StatelessWidget {
  const _ExplorerLoadingRow({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ScrapnoteTokens.minimumHitTarget,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ScrapnoteTokens.space4,
          vertical: ScrapnoteTokens.space4,
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: const ColoredBox(color: ScrapnoteTokens.paperSunken),
        ),
      ),
    );
  }
}

class _ExplorerLoadingList extends StatelessWidget {
  const _ExplorerLoadingList();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading notes',
      child: const Column(
        children: <Widget>[
          _ExplorerLoadingRow(widthFactor: 0.72),
          _ExplorerLoadingRow(widthFactor: 0.48),
          _ExplorerLoadingRow(widthFactor: 0.64),
        ],
      ),
    );
  }
}

class _DocumentPane extends StatelessWidget {
  const _DocumentPane({required this.loading, required this.onCreateNote});

  final bool loading;
  final VoidCallback? onCreateNote;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScrapnoteTokens.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            key: NotesView.tabStripKey,
            height: ScrapnoteTokens.tabStripHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ScrapnoteTokens.space4,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    FLucideIcons.fileText,
                    size: 14,
                    color: ScrapnoteTokens.mutedInk,
                  ),
                  const SizedBox(width: ScrapnoteTokens.space2),
                  Text(
                    loading ? 'Opening notes…' : 'No open notes',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ScrapnoteTokens.mutedInk,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const _Hairline(),
          Expanded(
            child: loading
                ? const _EditorLoading()
                : _EditorEmpty(onCreateNote: onCreateNote),
          ),
        ],
      ),
    );
  }
}

class _EditorEmpty extends StatelessWidget {
  const _EditorEmpty({required this.onCreateNote});

  final VoidCallback? onCreateNote;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(
          width: ScrapnoteTokens.space7,
          child: Padding(
            padding: EdgeInsets.only(
              top: ScrapnoteTokens.space5,
              right: ScrapnoteTokens.space3,
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Text(
                '1',
                style: TextStyle(
                  color: ScrapnoteTokens.mutedInk,
                  fontSize: 12,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        const _Hairline(axis: Axis.vertical),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ScrapnoteTokens.space5,
              ScrapnoteTokens.space5,
              ScrapnoteTokens.space5,
              ScrapnoteTokens.space5,
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: onCreateNote == null
                  ? const Text(
                      'Note editing is not available yet. This view does not load or save note files.',
                      style: TextStyle(
                        color: ScrapnoteTokens.mutedInk,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          'No note is open.',
                          style: TextStyle(
                            color: ScrapnoteTokens.charcoalSoft,
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: ScrapnoteTokens.space4),
                        SizedBox(
                          height: ScrapnoteTokens.minimumHitTarget,
                          child: FButton(
                            variant: FButtonVariant.outline,
                            mainAxisSize: MainAxisSize.min,
                            onPress: onCreateNote,
                            prefix: const Icon(
                              FLucideIcons.filePlus2,
                              size: 16,
                            ),
                            child: const Text('New note'),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditorLoading extends StatelessWidget {
  const _EditorLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading note editor',
      child: const Padding(
        padding: EdgeInsets.fromLTRB(
          ScrapnoteTokens.space7 +
              ScrapnoteTokens.hairline +
              ScrapnoteTokens.space5,
          ScrapnoteTokens.space5,
          ScrapnoteTokens.space6,
          ScrapnoteTokens.space5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _EditorLoadingLine(widthFactor: 0.44),
            SizedBox(height: ScrapnoteTokens.space5),
            _EditorLoadingLine(widthFactor: 0.82),
            SizedBox(height: ScrapnoteTokens.space3),
            _EditorLoadingLine(widthFactor: 0.68),
          ],
        ),
      ),
    );
  }
}

class _EditorLoadingLine extends StatelessWidget {
  const _EditorLoadingLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: const SizedBox(
        height: ScrapnoteTokens.space3,
        child: ColoredBox(color: ScrapnoteTokens.paperSunken),
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({this.axis = Axis.horizontal});

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScrapnoteTokens.rule,
      child: SizedBox(
        width: axis == Axis.vertical ? ScrapnoteTokens.hairline : null,
        height: axis == Axis.horizontal ? ScrapnoteTokens.hairline : null,
      ),
    );
  }
}
