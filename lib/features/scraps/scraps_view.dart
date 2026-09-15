// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · Index-First editor shell

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../core/design/scrapnote_tokens.dart';
import '../../core/layout/adaptive_workspace.dart';
import '../../domain/scrap.dart';
import '../editor/inline_document_editor.dart';
import '../editor/inline_image.dart';
import '../location/scrap_metadata_drawer.dart';

/// Read-only tab data used by the editor chrome.
@immutable
class ScrapEditorTabData {
  const ScrapEditorTabData({
    required this.id,
    required this.title,
    required this.dirty,
  });

  final String id;
  final String title;
  final bool dirty;
}

/// Index-first Scrap workspace: Inbox hierarchy, document tabs, and editor.
class ScrapsView extends StatefulWidget {
  const ScrapsView({
    required this.scraps,
    required this.tabs,
    required this.activeTabId,
    required this.controller,
    required this.onNewDocument,
    required this.onScrapSelected,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onCloseActive,
    required this.onSave,
    this.onDeleteScrap,
    this.imageDirectory = '',
    this.activeScrapId,
    this.activeScrap,
    this.savedImagePaths = const <String>[],
    this.saving = false,
    this.pendingImagePaths = const <String>[],
    this.onChooseImages,
    this.onImagesDropped,
    this.onPasteImage,
    this.onRemoveImage,
    super.key,
  });

  final ValueChanged<String>? onDeleteScrap;
  final String imageDirectory;
  final List<Scrap> scraps;
  final List<ScrapEditorTabData> tabs;
  final String? activeTabId;
  final String? activeScrapId;
  final Scrap? activeScrap;
  final TextEditingController controller;
  final VoidCallback onNewDocument;
  final ValueChanged<String> onScrapSelected;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final VoidCallback onCloseActive;
  final VoidCallback onSave;
  final bool saving;
  final List<String> pendingImagePaths;
  final List<String> savedImagePaths;
  final VoidCallback? onChooseImages;
  final ValueChanged<List<String>>? onImagesDropped;
  final Future<bool> Function()? onPasteImage;
  final ValueChanged<String>? onRemoveImage;

  @override
  State<ScrapsView> createState() => _ScrapsViewState();
}

class _ScrapsViewState extends State<ScrapsView> {
  final ScrollController _editorScrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _editorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scraps = widget.scraps.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ScrapnoteTokens.paper,
      endDrawer: ScrapMetadataDrawer(scrap: widget.activeScrap),
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
              widget.onSave,
          const SingleActivator(LogicalKeyboardKey.keyS, control: true):
              widget.onSave,
          const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
              widget.onNewDocument,
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              widget.onNewDocument,
          const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
              widget.onCloseActive,
          const SingleActivator(LogicalKeyboardKey.keyW, control: true):
              widget.onCloseActive,
          if (widget.onChooseImages != null)
            const SingleActivator(
              LogicalKeyboardKey.keyI,
              meta: true,
              shift: true,
            ): widget.onChooseImages!,
          if (widget.onChooseImages != null)
            const SingleActivator(
              LogicalKeyboardKey.keyI,
              control: true,
              shift: true,
            ): widget.onChooseImages!,
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _handlePasteShortcut,
          child: AdaptiveWorkspace(
            selection: widget.activeTabId,
            saving: widget.saving,
            onSave: widget.onSave,
            onCreate: widget.onNewDocument,
            onChooseImages: widget.onChooseImages,
            listBuilder: (showEditor) => _InboxHierarchy(
              scraps: scraps,
              onDeleteScrap: widget.onDeleteScrap,
              selectedScrapId: widget.activeScrapId,
              onNewDocument: () {
                widget.onNewDocument();
                showEditor();
              },
              onScrapSelected: (id) {
                widget.onScrapSelected(id);
                showEditor();
              },
            ),
            editor: _DocumentWorkspace(
              imageDirectory: widget.imageDirectory,
              tabs: widget.tabs,
              activeTabId: widget.activeTabId,
              controller: widget.controller,
              editorScrollController: _editorScrollController,
              saving: widget.saving,
              pendingImagePaths: widget.pendingImagePaths,
              savedImagePaths: widget.savedImagePaths,
              onNewDocument: widget.onNewDocument,
              onOpenMetadata: () => _scaffoldKey.currentState?.openEndDrawer(),
              onChooseImages: widget.onChooseImages,
              onTabSelected: widget.onTabSelected,
              onTabClosed: widget.onTabClosed,
              onImagesDropped: widget.onImagesDropped,
              onRemoveImage: widget.onRemoveImage,
              onPasteImage: widget.onPasteImage,
            ),
          ),
        ),
      ),
    );
  }

  KeyEventResult _handlePasteShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (!HardwareKeyboard.instance.isMetaPressed &&
            !HardwareKeyboard.instance.isControlPressed)) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      widget.onSave();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      widget.onNewDocument();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      widget.onCloseActive();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyI &&
        HardwareKeyboard.instance.isShiftPressed) {
      widget.onChooseImages?.call();
      return KeyEventResult.handled;
    }
    // EditableText still needs Cmd/Ctrl+V for ordinary text paste.
    return KeyEventResult.ignored;
  }
}

class _InboxHierarchy extends StatelessWidget {
  const _InboxHierarchy({
    required this.scraps,
    required this.onDeleteScrap,
    required this.selectedScrapId,
    required this.onNewDocument,
    required this.onScrapSelected,
  });

  final ValueChanged<String>? onDeleteScrap;
  final List<Scrap> scraps;
  final String? selectedScrapId;
  final VoidCallback onNewDocument;
  final ValueChanged<String> onScrapSelected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScrapnoteTokens.paperRaised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: ScrapnoteTokens.tabBarHeight,
            child: Row(
              children: <Widget>[
                const SizedBox(width: ScrapnoteTokens.space3),
                const Icon(
                  FLucideIcons.chevronDown,
                  size: 13,
                  color: ScrapnoteTokens.mutedInk,
                ),
                const SizedBox(width: ScrapnoteTokens.space1),
                const Expanded(
                  child: Text(
                    'INBOX',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ScrapnoteTokens.charcoalSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                _EditorIconButton(
                  key: const ValueKey<String>('new-scrap'),
                  icon: FLucideIcons.filePlus2,
                  label: 'New scrap',
                  onPressed: onNewDocument,
                ),
              ],
            ),
          ),
          const _Hairline(),
          Expanded(
            child: scraps.isEmpty
                ? const _EmptyInbox()
                : Scrollbar(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        vertical: ScrapnoteTokens.space1,
                      ),
                      itemCount: scraps.length,
                      itemBuilder: (context, index) {
                        final scrap = scraps[index];
                        return FContextMenu(
                          secondaryPress: true,
                          menuBuilder: (context, controller, menu) => [
                            FItemGroup(
                              children: [
                                FItem(
                                  title: const Text('Delete scrap'),
                                  prefix: const Icon(FLucideIcons.trash2),
                                  onPress: onDeleteScrap == null
                                      ? null
                                      : () {
                                          controller.hide();
                                          onDeleteScrap!(scrap.id);
                                        },
                                ),
                              ],
                            ),
                          ],
                          child: _ScrapHierarchyRow(
                            scrap: scrap,
                            selected: scrap.id == selectedScrapId,
                            onPressed: () => onScrapSelected(scrap.id),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(32, 24, 20, 20),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          'No scraps',
          style: TextStyle(color: ScrapnoteTokens.mutedInk, fontSize: 12),
        ),
      ),
    );
  }
}

class _ScrapHierarchyRow extends StatelessWidget {
  const _ScrapHierarchyRow({
    required this.scrap,
    required this.selected,
    required this.onPressed,
  });

  final Scrap scrap;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final title = scrap.firstLineTitle.isEmpty
        ? 'Untitled'
        : scrap.firstLineTitle;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title, modified ${_formatTimestamp(scrap.updatedAt)}',
      child: Material(
        color: selected ? ScrapnoteTokens.paperSunken : Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          focusColor: ScrapnoteTokens.signalOrangeWash,
          hoverColor: ScrapnoteTokens.paperSunken,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.fromLTRB(28, 7, 12, 7),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected
                      ? ScrapnoteTokens.signalOrange
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? ScrapnoteTokens.charcoal
                        : ScrapnoteTokens.charcoalSoft,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTimestamp(scrap.updatedAt),
                  maxLines: 1,
                  style: const TextStyle(
                    color: ScrapnoteTokens.mutedInk,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
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

class _DocumentWorkspace extends StatelessWidget {
  const _DocumentWorkspace({
    required this.imageDirectory,
    required this.tabs,
    required this.activeTabId,
    required this.controller,
    required this.editorScrollController,
    required this.saving,
    required this.pendingImagePaths,
    required this.savedImagePaths,
    required this.onNewDocument,
    required this.onOpenMetadata,
    required this.onChooseImages,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onImagesDropped,
    required this.onRemoveImage,
    this.onPasteImage,
  });

  final String imageDirectory;
  final List<ScrapEditorTabData> tabs;
  final String? activeTabId;
  final TextEditingController controller;
  final ScrollController editorScrollController;
  final Future<bool> Function()? onPasteImage;
  final bool saving;
  final List<String> pendingImagePaths;
  final List<String> savedImagePaths;
  final VoidCallback onNewDocument;
  final VoidCallback onOpenMetadata;
  final VoidCallback? onChooseImages;
  final ValueChanged<String> onTabSelected;
  final ValueChanged<String> onTabClosed;
  final ValueChanged<List<String>>? onImagesDropped;
  final ValueChanged<String>? onRemoveImage;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ScrapnoteTokens.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TabStrip(
            tabs: tabs,
            activeTabId: activeTabId,
            onOpenMetadata: onOpenMetadata,
            onChooseImages: onChooseImages,
            onSelected: onTabSelected,
            onClosed: onTabClosed,
          ),
          const _Hairline(),
          Expanded(
            child: activeTabId == null
                ? _NoOpenDocument(onCreate: onNewDocument)
                : _EditorDropSurface(
                    enabled: !saving && onImagesDropped != null,
                    onDropped: onImagesDropped,
                    child: InlineDocumentEditor(
                      key: ValueKey(activeTabId),
                      controller: controller,
                      imageDirectory: imageDirectory,
                      enabled: !saving,
                      onRemoveImage: onRemoveImage,
                      onPasteImage: onPasteImage,
                      editorKey: const ValueKey<String>('scrap-editor'),
                    ),
                  ),
          ),
          if (saving) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.activeTabId,
    required this.onOpenMetadata,
    required this.onChooseImages,
    required this.onSelected,
    required this.onClosed,
  });

  final List<ScrapEditorTabData> tabs;
  final String? activeTabId;
  final VoidCallback onOpenMetadata;
  final VoidCallback? onChooseImages;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onClosed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ScrapnoteTokens.tabBarHeight,
      child: ColoredBox(
        color: ScrapnoteTokens.paperSunken,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  return _DocumentTab(
                    tab: tab,
                    selected: tab.id == activeTabId,
                    onSelected: () => onSelected(tab.id),
                    onClosed: () => onClosed(tab.id),
                  );
                },
              ),
            ),
            _EditorIconButton(
              key: const ValueKey<String>('scrap-metadata'),
              icon: FLucideIcons.mapPin,
              label: 'Scrap information and location',
              onPressed: onOpenMetadata,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTab extends StatefulWidget {
  const _DocumentTab({
    required this.tab,
    required this.selected,
    required this.onSelected,
    required this.onClosed,
  });

  final ScrapEditorTabData tab;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onClosed;

  @override
  State<_DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<_DocumentTab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showClose = _hovered || !widget.tab.dirty;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: widget.selected
            ? ScrapnoteTokens.paper
            : ScrapnoteTokens.paperSunken,
        child: InkWell(
          onTap: widget.onSelected,
          focusColor: ScrapnoteTokens.signalOrangeWash,
          hoverColor: ScrapnoteTokens.paperRaised,
          child: Container(
            width: 176,
            padding: const EdgeInsets.only(left: ScrapnoteTokens.space3),
            decoration: BoxDecoration(
              border: Border(
                right: const BorderSide(color: ScrapnoteTokens.rule),
                top: BorderSide(
                  color: widget.selected
                      ? ScrapnoteTokens.signalOrange
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  FLucideIcons.fileText,
                  size: 14,
                  color: ScrapnoteTokens.mutedInk,
                ),
                const SizedBox(width: ScrapnoteTokens.space2),
                Expanded(
                  child: Text(
                    widget.tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.selected
                          ? ScrapnoteTokens.charcoal
                          : ScrapnoteTokens.charcoalSoft,
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: IconButton(
                    key: ValueKey<String>('close-tab-${widget.tab.id}'),
                    tooltip: widget.tab.dirty
                        ? 'Close unsaved scrap'
                        : 'Close scrap',
                    onPressed: widget.onClosed,
                    iconSize: 14,
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    icon: showClose
                        ? const Icon(
                            FLucideIcons.x,
                            color: ScrapnoteTokens.charcoalSoft,
                          )
                        : const SizedBox.square(
                            key: ValueKey<String>('dirty-indicator'),
                            dimension: 8,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: ScrapnoteTokens.charcoal,
                                shape: BoxShape.circle,
                              ),
                            ),
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

class _EditorIconButton extends StatelessWidget {
  const _EditorIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: SizedBox(
        width: 44,
        child: IconButton(
          onPressed: onPressed,
          tooltip: null,
          iconSize: 16,
          splashRadius: 18,
          color: ScrapnoteTokens.charcoalSoft,
          disabledColor: ScrapnoteTokens.ruleStrong,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _NoOpenDocument extends StatelessWidget {
  const _NoOpenDocument({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FButton(
        variant: FButtonVariant.ghost,
        onPress: onCreate,
        prefix: const Icon(FLucideIcons.filePlus2, size: 16),
        child: const Text('New scrap'),
      ),
    );
  }
}

class _EditorDropSurface extends StatefulWidget {
  const _EditorDropSurface({
    required this.enabled,
    required this.onDropped,
    required this.child,
  });

  final bool enabled;
  final ValueChanged<List<String>>? onDropped;
  final Widget child;

  @override
  State<_EditorDropSurface> createState() => _EditorDropSurfaceState();
}

class _EditorDropSurfaceState extends State<_EditorDropSurface> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        InlineImage.placeCaret(context, detail.globalPosition);
        widget.onDropped?.call(
          detail.files.map((file) => file.path).toList(growable: false),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: _dragging
                ? ScrapnoteTokens.signalOrange
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  final Axis axis = Axis.horizontal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: axis == Axis.vertical ? ScrapnoteTokens.hairline : null,
      height: axis == Axis.horizontal ? ScrapnoteTokens.hairline : null,
      child: const ColoredBox(color: ScrapnoteTokens.rule),
    );
  }
}

String _formatTimestamp(DateTime value) {
  final local = value.toLocal();
  String two(int component) => component.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
