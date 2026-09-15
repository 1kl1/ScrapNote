// Hallmark · pre-emit critique: P5 H5 E5 S5 R5 V4
// design-system: DESIGN.md · designed-as-app · chronological reading surface

import 'package:flutter/material.dart';
import 'timeline_route_map.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:scrapnote/core/design/scrapnote_tokens.dart';
import 'package:scrapnote/domain/scrap.dart';
import 'package:scrapnote/features/editor/local_markdown_view.dart';
import 'package:scrapnote/features/timeline/timeline_dial.dart';

/// A chronological reading surface with a clipped linear date dial.
class TimelineView extends StatelessWidget {
  const TimelineView({
    super.key,
    required this.scraps,
    required this.selectedDate,
    required this.onDateChanged,
    required this.vaultPath,
  });

  static const dialClipKey = ValueKey<String>('timeline-dial-clip');
  static const dateStripKey = ValueKey<String>('timeline-date-strip');

  final List<Scrap> scraps;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final String vaultPath;

  @override
  Widget build(BuildContext context) {
    // These are calendar values rather than instants. Converting through the
    // device's current time zone would move travel records to another day.
    final localSelectedDate = _dateOnly(selectedDate);
    final scrapsForDay =
        scraps
            .where(
              (scrap) =>
                  _isSameDate(scrap.localCalendarDate, localSelectedDate),
            )
            .toList()
          ..sort(
            (first, second) => first.createdAt.compareTo(second.createdAt),
          );
    final markedDates = scraps
        .map((scrap) => _dateOnly(scrap.localCalendarDate))
        .toSet();

    return ClipRect(
      child: ColoredBox(
        color: ScrapnoteTokens.paper,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final list = _ChronologicalList(
                    key: ValueKey(localSelectedDate),
                    scraps: scrapsForDay,
                    imageDirectory: path.join(vaultPath, 'scraps'),
                  );
                  final map = TimelineRouteMap(scraps: scrapsForDay);
                  if (constraints.maxWidth >= 850) {
                    return Row(
                      children: [
                        Expanded(flex: 3, child: list),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 2, child: map),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      SizedBox(
                        height: constraints.maxHeight * 0.42,
                        child: map,
                      ),
                      const Divider(height: 1),
                      Expanded(child: list),
                    ],
                  );
                },
              ),
            ),
            const _Hairline(),
            _DateStrip(
              key: dateStripKey,
              date: localSelectedDate,
              scrapCount: scrapsForDay.length,
            ),
            const _Hairline(),
            ClipRect(
              key: dialClipKey,
              child: TimelineDial(
                selectedDate: localSelectedDate,
                markedDates: markedDates,
                onChanged: onDateChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChronologicalList extends StatefulWidget {
  const _ChronologicalList({
    super.key,
    required this.scraps,
    required this.imageDirectory,
  });

  final List<Scrap> scraps;
  final String imageDirectory;

  @override
  State<_ChronologicalList> createState() => _ChronologicalListState();
}

class _ChronologicalListState extends State<_ChronologicalList> {
  final _scrollController = ScrollController();
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scraps = widget.scraps;
    if (scraps.isEmpty) {
      return const Center(
        child: Text(
          'No scraps on this date.',
          style: TextStyle(color: ScrapnoteTokens.mutedInk, fontSize: 13),
        ),
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        key: const ValueKey('timeline-scrap-list'),
        controller: _scrollController,
        primary: false,
        padding: const EdgeInsets.symmetric(vertical: ScrapnoteTokens.space4),
        // Lay out the day's records together. A lazy list estimates its total
        // extent from visible rows; variable Markdown/image heights made that
        // estimate and its scrollbar thumb jump while reading.
        child: Column(
          children: [
            for (var index = 0; index < scraps.length; index++) ...[
              if (index > 0) const _ListRule(),
              _ScrapRow(
                key: ValueKey(scraps[index].id),
                scrap: scraps[index],
                imageDirectory: widget.imageDirectory,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScrapRow extends StatelessWidget {
  const _ScrapRow({
    super.key,
    required this.scrap,
    required this.imageDirectory,
  });

  final Scrap scrap;
  final String imageDirectory;

  @override
  Widget build(BuildContext context) {
    final title = scrap.firstLineTitle.isEmpty
        ? 'Untitled scrap'
        : scrap.firstLineTitle;
    final time = DateFormat('HH:mm').format(_modifiedWallClock(scrap));

    return Semantics(
      container: true,
      label: '$time, $title',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ScrapnoteTokens.space6,
          vertical: ScrapnoteTokens.space4,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: ScrapnoteTokens.space6 * 2,
                  child: Text(
                    time,
                    style: const TextStyle(
                      color: ScrapnoteTokens.charcoalSoft,
                      fontSize: 13,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: ScrapnoteTokens.space4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      LocalMarkdownView(
                        data: scrap.body,
                        imageDirectory: imageDirectory,
                      ),
                    ],
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

class _ListRule extends StatelessWidget {
  const _ListRule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ScrapnoteTokens.space6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: const Padding(
            padding: EdgeInsets.only(
              left: ScrapnoteTokens.space7 + ScrapnoteTokens.space6,
            ),
            child: _Hairline(),
          ),
        ),
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({super.key, required this.date, required this.scrapCount});

  final DateTime date;
  final int scrapCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ScrapnoteTokens.tabStripHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final datePattern = constraints.maxWidth < 430
              ? 'EEE · d MMM yyyy'
              : 'EEEE · d MMMM yyyy';
          final count = scrapCount == 1 ? '1 scrap' : '$scrapCount scraps';

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ScrapnoteTokens.space4,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    DateFormat(datePattern).format(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ScrapnoteTokens.charcoal,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: ScrapnoteTokens.space4),
                Text(
                  count,
                  maxLines: 1,
                  style: const TextStyle(
                    color: ScrapnoteTokens.mutedInk,
                    fontSize: 11,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: ScrapnoteTokens.hairline,
      child: ColoredBox(color: ScrapnoteTokens.rule),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDate(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

DateTime _modifiedWallClock(Scrap scrap) {
  final offset = scrap.utcOffsetMinutes;
  if (offset == null) {
    return scrap.createdAt.toLocal();
  }
  return scrap.createdAt.toUtc().add(Duration(minutes: offset));
}
