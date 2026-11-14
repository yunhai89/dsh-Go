// A read-only spreadsheet view for CSV / TSV / XLSX previews — row numbers down
// the left, the first row pinned as the header, both axes scrolling, a tapped
// cell's full text in a bar at the bottom.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../state/sheet_files.dart';
import '../theme/theme.dart';

/// `0` → `A`, `27` → `AB`.
String columnLetters(int index) {
  var n = index + 1;
  final out = StringBuffer();
  final letters = <int>[];
  while (n > 0) {
    final r = (n - 1) % 26;
    letters.add(0x41 + r);
    n = (n - 1) ~/ 26;
  }
  for (final c in letters.reversed) {
    out.writeCharCode(c);
  }
  return out.toString();
}

final _numeric = RegExp(r'^[-+]?(\d{1,3}(,\d{3})+|\d+)?(\.\d+)?%?$');

/// Whether a cell reads as a number (right-aligned, tabular figures).
bool isNumericCell(String text) => text.isNotEmpty && text != '.' && _numeric.hasMatch(text.trim());

/// Row numbers on the left, the first row pinned as the header, scrolling both
/// ways; a tapped cell shows its full text at the bottom.
class SheetTable extends StatefulWidget {
  const SheetTable({super.key, required this.grid, this.maxColumns = 200});

  final SheetGrid grid;

  /// Columns past this are left out (a note says so).
  final int maxColumns;

  static const rowHeight = 36.0;
  static const cellInset = 12.0;
  static const minColumn = 56.0;
  static const maxColumn = 280.0;

  @override
  State<SheetTable> createState() => _SheetTableState();
}

class _SheetTableState extends State<SheetTable> {
  final _headerH = ScrollController();
  final _bodyH = ScrollController();
  final _gutterV = ScrollController();
  final _bodyV = ScrollController();

  List<double>? _widths;
  List<double>? _offsets;
  double? _gutter;
  TextScaler? _scaler;
  (int row, int col)? _selected;
  ({int first, int last})? _shown;
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    _bodyH.addListener(() {
      if (_headerH.hasClients && _headerH.offset != _bodyH.offset) {
        _headerH.jumpTo(_bodyH.offset);
      }
      final next = _visibleRange();
      if (next != _shown) setState(() => _shown = next);
    });
    _bodyV.addListener(() {
      if (_gutterV.hasClients && _gutterV.offset != _bodyV.offset) {
        _gutterV.jumpTo(_bodyV.offset);
      }
    });
  }

  @override
  void didUpdateWidget(SheetTable old) {
    super.didUpdateWidget(old);
    if (!identical(old.grid, widget.grid)) {
      _widths = null;
      _offsets = null;
      _shown = null;
      _selected = null;
    }
  }

  /// Columns whose cells can touch the viewport, plus one column of lead-in
  /// and one of overscan. A 200-column table must not build 200 cells for
  /// every visible row.
  ({int first, int last}) _visibleRange() {
    final offsets = _offsets;
    if (offsets == null || _columns == 0) return (first: 0, last: -1);
    final start = _bodyH.hasClients ? _bodyH.offset : 0.0;
    final end = start + (_viewport > 0 ? _viewport : 400);
    var first = 0;
    while (first < _columns - 1 && offsets[first + 1] <= start) {
      first++;
    }
    var last = first;
    while (last < _columns - 1 && offsets[last + 1] < end) {
      last++;
    }
    return (first: math.max(0, first - 1), last: math.min(_columns - 1, last + 1));
  }

  @override
  void dispose() {
    _headerH.dispose();
    _bodyH.dispose();
    _gutterV.dispose();
    _bodyV.dispose();
    super.dispose();
  }

  int get _columns => math.min(widget.grid.columns, widget.maxColumns);

  TextStyle _cellStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(fontSize: 13.5, height: 1.3);

  /// Column widths from the header and the first rows' text.
  ///
  /// A wide table can have 200 columns and thousands of rows. Laying out every
  /// sampled cell would run tens of thousands of text measurements on the frame
  /// that opens it, so only the longest few candidates per column are measured.
  void _measure(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    if (_widths != null && _scaler == scaler) return;
    _scaler = scaler;
    final style = _cellStyle(context);
    final bold = style.copyWith(fontWeight: FontWeight.w600);
    final rows = widget.grid.rows;
    final sample = math.min(rows.length, 120);
    final painter = TextPainter(textDirection: TextDirection.ltr, maxLines: 1, textScaler: scaler);
    final widths = List<double>.filled(_columns, SheetTable.minColumn);
    double measured(String text, TextStyle textStyle) {
      painter.text = TextSpan(text: text.length > 60 ? text.substring(0, 60) : text, style: textStyle);
      painter.layout();
      return painter.width;
    }

    for (var c = 0; c < _columns; c++) {
      var widest = 0.0;
      if (rows.isNotEmpty && c < rows.first.length && rows.first[c].isNotEmpty) {
        widest = measured(rows.first[c], bold);
      }
      if (widest < SheetTable.maxColumn) {
        final candidates = <String>[];
        for (var r = 1; r < sample; r++) {
          final row = rows[r];
          final text = c < row.length ? row[c] : '';
          if (text.isNotEmpty) candidates.add(text);
        }
        // Text widths grow with the amount of text far more reliably than with
        // glyph count, and the longest two cover the usual narrow/wide mixes.
        if (candidates.length > 2) {
          candidates.sort((a, b) => b.length.compareTo(a.length));
          candidates.length = 2;
        }
        for (final text in candidates) {
          widest = math.max(widest, measured(text, style));
          if (widest >= SheetTable.maxColumn) break;
        }
      }
      widths[c] = (widest + SheetTable.cellInset * 2 + 1).clamp(SheetTable.minColumn, SheetTable.maxColumn);
    }
    final offsets = List<double>.filled(_columns + 1, 0);
    for (var c = 0; c < _columns; c++) {
      offsets[c + 1] = offsets[c] + widths[c];
    }
    _offsets = offsets;
    painter.text = TextSpan(
      text: '${math.max(rows.length, 1)}',
      style: AppType.tabular(Theme.of(context).textTheme.bodySmall!),
    );
    painter.layout();
    _gutter = math.max(36, painter.width + 20);
    painter.dispose();
    _widths = widths;
  }

  @override
  Widget build(BuildContext context) {
    _measure(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dsh = DshColors.of(context);
    final dark = theme.brightness == Brightness.dark;
    final widths = _widths!;
    final gutter = _gutter!;
    final total = widths.fold(0.0, (a, b) => a + b);
    final rows = widget.grid.rows;
    final body = rows.length > 1 ? rows.length - 1 : 0;
    final line = scheme.outlineVariant.withValues(alpha: dark ? 0.35 : 0.55);
    final headerFill = dark ? Colors.white.withValues(alpha: 0.06) : scheme.onSurface.withValues(alpha: 0.04);
    final style = _cellStyle(context);
    final numberStyle = AppType.tabular(theme.textTheme.bodySmall!.copyWith(color: dsh.textTertiary));

    Widget cell(int r, int c, {bool header = false}) {
      final row = rows[r];
      final text = c < row.length ? row[c] : '';
      final numeric = !header && isNumericCell(text);
      final selected = _selected == (r, c);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selected = selected ? null : (r, c));
        },
        child: Container(
          width: widths[c],
          height: SheetTable.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: SheetTable.cellInset),
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
            border: Border(
              right: BorderSide(color: line, width: 0.5),
              bottom: BorderSide(color: line, width: 0.5),
            ),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: header
                ? style.copyWith(fontWeight: FontWeight.w600)
                : numeric
                ? AppType.tabular(style)
                : style,
          ),
        ),
      );
    }

    Widget numberCell(String label, {Color? fill}) => Container(
      width: gutter,
      height: SheetTable.rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        border: Border(
          right: BorderSide(color: line, width: 0.5),
          bottom: BorderSide(color: line, width: 0.5),
        ),
      ),
      child: Text(label, maxLines: 1, style: numberStyle),
    );

    Widget row(({int first, int last}) visible, int r, {bool header = false}) {
      final offsets = _offsets!;
      final leading = offsets[visible.first];
      final trailing = total - offsets[visible.last + 1];
      return Row(
        children: [
          if (leading > 0) SizedBox(width: leading),
          for (var c = visible.first; c <= visible.last; c++) cell(r, c, header: header),
          if (trailing > 0) SizedBox(width: trailing),
        ],
      );
    }

    final table = LayoutBuilder(
      builder: (context, constraints) {
        _viewport = math.max(0, constraints.maxWidth - gutter);
        final visible = _visibleRange();
        _shown = visible;
        final header = rows.isEmpty
            ? const SizedBox.shrink()
            : SizedBox(width: total, child: row(visible, 0, header: true));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: headerFill,
              child: Row(
                children: [
                  numberCell('1'),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _headerH,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: header,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: gutter,
                    child: ListView.builder(
                      controller: _gutterV,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemExtent: SheetTable.rowHeight,
                      itemCount: body,
                      itemBuilder: (context, i) => numberCell('${i + 2}', fill: headerFill),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _bodyH,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: total,
                        child: ListView.builder(
                          controller: _bodyV,
                          padding: EdgeInsets.zero,
                          itemExtent: SheetTable.rowHeight,
                          itemCount: body,
                          itemBuilder: (context, i) => row(visible, i + 1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    final selected = _selected;
    final picked = selected == null
        ? null
        : (selected.$2 < rows[selected.$1].length ? rows[selected.$1][selected.$2] : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: table),
        if (selected != null) _CellBar(label: '${columnLetters(selected.$2)}${selected.$1 + 1}', text: picked ?? ''),
      ],
    );
  }
}

/// The tapped cell: its address and full text (selectable).
class _CellBar extends StatelessWidget {
  const _CellBar({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6), width: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 132),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 48,
                child: Text(label, style: AppType.monoLabel(color: dsh.textTertiary)),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text.isEmpty ? l10n.botsEmptyCell : text,
                    style: theme.textTheme.bodyMedium?.copyWith(color: text.isEmpty ? dsh.textTertiary : null),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
