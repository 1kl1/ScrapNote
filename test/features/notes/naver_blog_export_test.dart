import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:scrapnote/features/notes/naver_blog_export.dart';

void main() {
  group('NaverBlogExport', () {
    test('converts Markdown to paste-safe text and preserves image order', () {
      final export = NaverBlogExport.fromMarkdown(
        title: '  서울 여행  ',
        imageDirectory: '/vault/notes/trips',
        markdown: '''
# 첫날

**반가워요**. [지도](https://map.naver.com/example)

- 한강 산책
- [x] 사진 정리

![야경](assets/night.jpg "center:50")

<!-- scrapnote:begin:scrap-1 -->
## 메모
`따뜻한 밤`
<!-- scrapnote:end -->
''',
      );

      expect(export.title, '서울 여행');
      expect(export.body, contains('첫날'));
      expect(export.body, contains('반가워요. 지도\nhttps://map.naver.com/example'));
      expect(export.body, contains('• 한강 산책'));
      expect(export.body, contains('☑ 사진 정리'));
      expect(export.body, contains('[사진 1 · 야경]'));
      expect(export.body, contains('메모\n따뜻한 밤'));
      expect(export.body, isNot(contains('**')));
      expect(export.body, isNot(contains('scrapnote:')));
      expect(export.images, hasLength(1));
      expect(
        export.images.single.localPath,
        path.normalize('/vault/notes/trips/assets/night.jpg'),
      );
    });

    test('writes a collision-safe package with copied images', () async {
      final root = Directory.systemTemp.createTempSync('naver_export_');
      addTearDown(() => root.deleteSync(recursive: true));
      final source = File(path.join(root.path, 'photo.png'))
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final export = NaverBlogExport.fromMarkdown(
        title: '후기: 1/2',
        imageDirectory: root.path,
        markdown: '본문\n\n![사진](${source.uri})',
      );

      final first = await export.writeTo(root);
      final second = await export.writeTo(root);

      expect(path.basename(first.path), '후기- 1-2_naver');
      expect(path.basename(second.path), '후기- 1-2_naver (2)');
      expect(
        File(path.join(first.path, '제목.txt')).readAsStringSync(),
        '후기: 1/2\n',
      );
      expect(
        File(path.join(first.path, '본문.txt')).readAsStringSync(),
        contains('[사진 1 · 사진]'),
      );
      expect(
        File(path.join(first.path, 'images', '01-photo.png')).existsSync(),
        isTrue,
      );
      expect(
        File(path.join(first.path, '작성 안내.txt')).readAsStringSync(),
        contains('직접 발행'),
      );
    });
  });
}
