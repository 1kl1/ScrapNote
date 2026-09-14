import '../../domain/scrap.dart';

/// A captured Scrap remains readable Markdown on disk; comments delimit its
/// atomic editor representation and preserve provenance across reopenings.
abstract final class ScrapEmbed {
  static final pattern = RegExp(
    r'<!-- scrapnote:begin:([^\s]+) -->\n([\s\S]*?)\n<!-- scrapnote:end -->',
  );

  static String wrap(Scrap scrap, String body) =>
      '<!-- scrapnote:begin:${Uri.encodeComponent(scrap.id)} -->\n$body\n<!-- scrapnote:end -->';

  static Set<String> usedIds(String body) => pattern
      .allMatches(body)
      .map((match) => Uri.decodeComponent(match.group(1)!))
      .toSet();

  static String content(String block) =>
      pattern.firstMatch(block)?.group(2) ?? block;
  static String title(String block) {
    for (final line in content(block).split('\n')) {
      if (line.trim().isNotEmpty) {
        return line.trim().replaceFirst(RegExp(r'^#{1,6}\s+'), '');
      }
    }
    return 'Untitled Scrap';
  }
}
