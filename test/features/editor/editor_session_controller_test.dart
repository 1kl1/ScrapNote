import 'package:flutter_test/flutter_test.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/editor/editor_session_controller.dart';

void main() {
  late List<String> ids;
  late EditorSessionController controller;

  setUp(() {
    ids = <String>['tab-1', 'tab-2', 'tab-3'];
    controller = EditorSessionController(
      sessionIdGenerator: () => ids.removeAt(0),
      now: () => DateTime.utc(2026, 9, 5, 12),
    );
  });

  test('new documents remain Untitled and compare body exactly', () {
    final document = controller.newDocument();

    expect(document.displayName, 'Untitled');
    expect(controller.activeSessionId, 'tab-1');
    expect(controller.activeDocument?.dirty, isFalse);

    expect(controller.updateActiveBody('# First idea'), isTrue);
    expect(controller.activeDocument?.displayName, 'Untitled');
    expect(controller.activeDocument?.dirty, isTrue);

    controller.updateActiveBody('');
    expect(controller.activeDocument?.dirty, isFalse);
  });

  test('opening an already open Scrap focuses its existing tab', () {
    final first = controller.openScrap(_scrap('one', 'First'));
    controller.newDocument();

    final reopened = controller.openScrap(_scrap('one', 'Disk changed'));

    expect(reopened, same(first));
    expect(controller.documents, hasLength(2));
    expect(controller.activeSessionId, first.sessionId);
    expect(controller.activeDocument?.body, 'First');
  });

  test('attachments participate in dirty state and can be removed', () {
    controller.openScrap(_scrap('one', 'Body'));

    expect(controller.addActiveAttachment('/tmp/image.png'), isTrue);
    expect(controller.addActiveAttachment('/tmp/image.png'), isFalse);
    expect(controller.activeDocument?.pendingImagePaths, <String>[
      '/tmp/image.png',
    ]);
    expect(controller.activeDocument?.dirty, isTrue);
    expect(controller.removeActiveAttachment('/tmp/image.png'), isTrue);
    expect(controller.activeDocument?.dirty, isFalse);
  });

  test('markSaved promotes a new tab and clears pending state', () {
    controller.newDocument();
    controller.updateActiveBody('Draft');
    controller.addActiveAttachment('/tmp/image.png');
    final persisted = _scrap('saved-id', 'Draft\n\n![image](asset.png)');

    controller.markSaved(persisted);

    expect(controller.activeDocument?.scrap, persisted);
    expect(controller.activeDocument?.body, persisted.body);
    expect(controller.activeDocument?.pendingImagePaths, isEmpty);
    expect(controller.activeDocument?.dirty, isFalse);
    expect(controller.activeDocument?.displayName, 'Draft');
  });

  test('dirty close is refused until the caller confirms discard', () {
    final dirty = controller.newDocument();
    controller.updateActiveBody('Do not lose me');

    expect(controller.closeDocument(dirty.sessionId), isFalse);
    expect(controller.documents, hasLength(1));
    expect(controller.discardDocument(dirty.sessionId), isTrue);
    expect(controller.documents, isEmpty);
    expect(controller.activeDocument, isNull);
  });

  test('snapshot and restore retain only dirty editor state', () {
    final clean = controller.openScrap(_scrap('clean', 'Clean'));
    final dirty = controller.openScrap(_scrap('dirty', 'Saved'));
    controller.updateActiveBody('Recovered edit');
    controller.addActiveAttachment('/tmp/pending.png');

    final snapshot = controller.toSnapshot();

    expect(snapshot.documents, hasLength(1));
    expect(snapshot.documents.single.sessionId, dirty.sessionId);
    expect(snapshot.activeSessionId, dirty.sessionId);
    expect(snapshot.documents.single.savedBody, 'Saved');
    expect(snapshot.documents.single.pendingImagePaths, <String>[
      '/tmp/pending.png',
    ]);

    final restored = EditorSessionController();
    restored.restore(
      snapshot,
      scraps: <Scrap>[_scrap('clean', 'Clean'), _scrap('dirty', 'Saved')],
    );
    expect(restored.documents, hasLength(1));
    expect(restored.documents.single.sessionId, dirty.sessionId);
    expect(restored.activeDocument?.body, 'Recovered edit');
    expect(restored.activeDocument?.dirty, isTrue);
    expect(
      restored.documents.any((item) => item.sessionId == clean.sessionId),
      isFalse,
    );
  });
}

Scrap _scrap(String id, String body) {
  return Scrap(
    id: id,
    body: body,
    createdAt: DateTime.utc(2026, 9, 5),
    updatedAt: DateTime.utc(2026, 9, 5),
  );
}
