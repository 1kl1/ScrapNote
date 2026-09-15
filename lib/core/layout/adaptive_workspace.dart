import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../design/scrapnote_tokens.dart';

/// Keeps both panes mounted through folding, rotation and list navigation.
class AdaptiveWorkspace extends StatefulWidget {
  const AdaptiveWorkspace({
    required this.listBuilder,
    required this.editor,
    required this.onSave,
    required this.onCreate,
    required this.onChooseImages,
    required this.saving,
    this.selection,
    this.extraAction,
    super.key,
  });

  final Widget Function(VoidCallback showEditor) listBuilder;
  final Widget editor;
  final VoidCallback onSave;
  final VoidCallback onCreate;
  final VoidCallback? onChooseImages;
  final bool saving;
  final Object? selection;
  final Widget? extraAction;

  @override
  State<AdaptiveWorkspace> createState() => _AdaptiveWorkspaceState();
}

class _AdaptiveWorkspaceState extends State<AdaptiveWorkspace> {
  bool _listVisible = false;

  @override
  void didUpdateWidget(AdaptiveWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) _listVisible = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 700;
      final touch =
          Theme.of(context).platform == TargetPlatform.android ||
          Theme.of(context).platform == TargetPlatform.iOS;
      final listVisible = !compact || _listVisible;
      final editorVisible = !compact || !_listVisible;
      return PopScope(
        canPop: !compact || _listVisible,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && compact) setState(() => _listVisible = true);
        },
        child: Column(
          children: [
            if (compact || touch)
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    if (compact)
                      _action(
                        _listVisible ? '편집기로 돌아가기' : '목록 열기',
                        _listVisible
                            ? FLucideIcons.arrowRight
                            : FLucideIcons.panelLeft,
                        () => setState(() => _listVisible = !_listVisible),
                        key: 'workspace-list-toggle',
                      ),
                    const Spacer(),
                    if (widget.extraAction != null) widget.extraAction!,
                    _action(
                      '새 문서',
                      FLucideIcons.plus,
                      widget.onCreate,
                      key: 'workspace-new',
                    ),
                    _action(
                      '이미지 첨부',
                      FLucideIcons.image,
                      widget.onChooseImages,
                      key: 'workspace-image',
                    ),
                    _action(
                      widget.saving ? '저장 중' : '저장',
                      FLucideIcons.save,
                      widget.saving ? null : widget.onSave,
                      key: 'workspace-save',
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: compact
                        ? constraints.maxWidth
                        : ScrapnoteTokens.explorerWidth,
                    child: Offstage(
                      offstage: !listVisible,
                      child: TickerMode(
                        enabled: listVisible,
                        child: widget.listBuilder(
                          () => setState(() => _listVisible = false),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: compact ? 0 : ScrapnoteTokens.explorerWidth + 1,
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Offstage(
                      offstage: !editorVisible,
                      child: TickerMode(
                        enabled: editorVisible,
                        child: widget.editor,
                      ),
                    ),
                  ),
                  if (!compact)
                    const Positioned(
                      left: ScrapnoteTokens.explorerWidth,
                      top: 0,
                      bottom: 0,
                      child: VerticalDivider(
                        width: 1,
                        color: ScrapnoteTokens.rule,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? action, {
    required String key,
  }) => SizedBox.square(
    dimension: 48,
    child: FButton.icon(
      key: ValueKey(key),
      variant: FButtonVariant.ghost,
      semanticsLabel: label,
      onPress: action,
      child: Icon(icon, size: 20),
    ),
  );
}
