import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:scrapnote/app/scrapnote_theme.dart';
import 'package:scrapnote/features/notes/naver_blog_export.dart';
import 'package:scrapnote/features/notes/naver_blog_export_dialog.dart';

void main() {
  testWidgets('copies title and body and opens Naver Blog', (tester) async {
    final copied = <String>[];
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ScrapnoteTheme.materialTheme,
        home: FTheme(
          data: ScrapnoteTheme.foruiTheme,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => NaverBlogExportDialog(
                    export: const NaverBlogExport(
                      title: '제목',
                      body: '본문',
                      images: <NaverBlogExportImage>[],
                    ),
                    clipboardWriter: (value) async => copied.add(value),
                    openNaverBlog: () async {
                      opened = true;
                      return true;
                    },
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('네이버 블로그로 내보내기'), findsOneWidget);

    await tester.tap(find.byTooltip('제목 복사'));
    await tester.pump();
    await tester.tap(find.byTooltip('본문 복사'));
    await tester.pump();
    expect(copied, <String>['제목', '본문']);
    expect(find.text('본문을 복사했습니다.'), findsOneWidget);

    await tester.tap(find.text('네이버 블로그 열기'));
    await tester.pump();
    expect(opened, isTrue);
  });
}
