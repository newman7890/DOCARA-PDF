import 'package:uuid/uuid.dart';

enum SpreadsheetColumnType {
  text,
  number,
  currency,
  date,
  boolean,
  select,
}

class SpreadsheetColumn {
  final String id;
  final String title;
  final SpreadsheetColumnType type;
  final String? format;
  final List<String>? options;

  SpreadsheetColumn({
    required this.id,
    required this.title,
    this.type = SpreadsheetColumnType.text,
    this.format,
    this.options,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'type': type.index,
        'format': format,
        'options': options,
      };

  factory SpreadsheetColumn.fromMap(Map<String, dynamic> map) => SpreadsheetColumn(
        id: map['id'],
        title: map['title'],
        type: SpreadsheetColumnType.values[map['type'] ?? 0],
        format: map['format'],
        options: map['options'] != null ? List<String>.from(map['options']) : null,
      );
}

class SpreadsheetCell {
  final dynamic value;

  SpreadsheetCell({this.value});

  Map<String, dynamic> toMap() {
    return {
      'value': value,
    };
  }

  factory SpreadsheetCell.fromMap(Map<String, dynamic> map) {
    return SpreadsheetCell(
      value: map['value'],
    );
  }
}

class SpreadsheetSheet {
  final String name;
  final List<SpreadsheetColumn> columns;
  final List<Map<String, SpreadsheetCell>> rows;

  SpreadsheetSheet({
    required this.name,
    required this.columns,
    required this.rows,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'columns': columns.map((c) => c.toMap()).toList(),
        'rows': rows.map((row) => row.map((key, cell) => MapEntry(key, cell.toMap()))).toList(),
      };

  factory SpreadsheetSheet.fromMap(Map<String, dynamic> map) => SpreadsheetSheet(
        name: map['name'] ?? 'Sheet',
        columns: (map['columns'] as List).map((c) => SpreadsheetColumn.fromMap(c)).toList(),
        rows: (map['rows'] as List).map((row) => (row as Map<String, dynamic>).map((key, value) => MapEntry(key, SpreadsheetCell.fromMap(value)))).toList(),
      );

  SpreadsheetSheet copyWith({
    String? name,
    List<SpreadsheetColumn>? columns,
    List<Map<String, SpreadsheetCell>>? rows,
  }) {
    return SpreadsheetSheet(
      name: name ?? this.name,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
    );
  }
}

class Spreadsheet {
  final String id;
  final String title;
  final List<SpreadsheetSheet> sheets;
  final int activeSheetIndex;
  final DateTime dateCreated;
  final DateTime dateModified;

  Spreadsheet({
    required this.id,
    required this.title,
    required this.sheets,
    this.activeSheetIndex = 0,
    required this.dateCreated,
    required this.dateModified,
  });

  SpreadsheetSheet get activeSheet => sheets[activeSheetIndex];

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'sheets': sheets.map((s) => s.toMap()).toList(),
        'activeSheetIndex': activeSheetIndex,
        'dateCreated': dateCreated.toIso8601String(),
        'dateModified': dateModified.toIso8601String(),
      };

  factory Spreadsheet.fromMap(Map<String, dynamic> map) {
    List<SpreadsheetSheet> sheets;
    if (map['sheets'] != null) {
      sheets = (map['sheets'] as List).map((s) => SpreadsheetSheet.fromMap(s)).toList();
    } else {
      // Legacy support for single-sheet data
      sheets = [
        SpreadsheetSheet(
          name: 'Sheet1',
          columns: (map['columns'] as List).map((c) => SpreadsheetColumn.fromMap(c)).toList(),
          rows: (map['rows'] as List).map((row) => (row as Map<String, dynamic>).map((key, value) => MapEntry(key, SpreadsheetCell.fromMap(value)))).toList(),
        )
      ];
    }

    return Spreadsheet(
      id: map['id'],
      title: map['title'],
      sheets: sheets,
      activeSheetIndex: map['activeSheetIndex'] ?? 0,
      dateCreated: DateTime.parse(map['dateCreated']),
      dateModified: DateTime.parse(map['dateModified']),
    );
  }

  Spreadsheet removeSheet(int index) {
    if (sheets.length <= 1) return this;
    final newSheets = List<SpreadsheetSheet>.from(sheets);
    newSheets.removeAt(index);

    int newActiveIndex = activeSheetIndex;
    if (activeSheetIndex > index) {
      newActiveIndex = activeSheetIndex - 1;
    } else if (activeSheetIndex == index) {
      newActiveIndex = activeSheetIndex.clamp(0, newSheets.length - 1);
    }

    return copyWith(
      sheets: newSheets,
      activeSheetIndex: newActiveIndex,
      dateModified: DateTime.now(),
    );
  }

  Spreadsheet copyWith({
    String? title,
    List<SpreadsheetSheet>? sheets,
    int? activeSheetIndex,
    DateTime? dateModified,
  }) {
    return Spreadsheet(
      id: id,
      title: title ?? this.title,
      sheets: sheets ?? this.sheets,
      activeSheetIndex: activeSheetIndex ?? this.activeSheetIndex,
      dateCreated: dateCreated,
      dateModified: dateModified ?? this.dateModified,
    );
  }

  static Spreadsheet createEmpty(String title) {
    final now = DateTime.now();
    return Spreadsheet(
      id: const Uuid().v4(),
      title: title,
      sheets: [
        SpreadsheetSheet(
          name: 'Sheet1',
          columns: [
            SpreadsheetColumn(id: 'col1', title: 'Column 1'),
            SpreadsheetColumn(id: 'col2', title: 'Column 2'),
            SpreadsheetColumn(id: 'col3', title: 'Column 3'),
          ],
          rows: List.generate(10, (_) => {}),
        ),
      ],
      dateCreated: now,
      dateModified: now,
    );
  }
}
