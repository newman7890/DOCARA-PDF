import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import '../models/spreadsheet_model.dart';

class SpreadsheetService {
  static const String _sheetsFile = 'spreadsheets_metadata.json';

  Future<List<Spreadsheet>> loadAllSheets() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(appDir.path, _sheetsFile));

      if (!file.existsSync()) {
        return [];
      }

      final content = await file.readAsString();
      final List<dynamic> jsonList = json.decode(content);
      return jsonList.map((e) => Spreadsheet.fromMap(e)).toList()
        ..sort((a, b) => b.dateModified.compareTo(a.dateModified));
    } catch (e) {
      debugPrint("Error loading spreadsheets: $e");
      return [];
    }
  }

  bool _isSaving = false;

  Future<void> saveSheet(Spreadsheet sheet) async {
    while (_isSaving) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _isSaving = true;
    
    try {
      debugPrint("SpreadsheetService: Saving metadata for [${sheet.title}] (${sheet.id})");
      debugPrint("Sheets count: ${sheet.sheets.length}. Active Rows: ${sheet.activeSheet.rows.length}");
      
      final sheets = await loadAllSheets();
      final index = sheets.indexWhere((s) => s.id == sheet.id);

      final updatedSheet = sheet.copyWith(dateModified: DateTime.now());

      if (index != -1) {
        sheets[index] = updatedSheet;
      } else {
        sheets.add(updatedSheet);
      }

      await _saveMetadata(sheets);
      debugPrint("SpreadsheetService: Metadata write complete");
    } finally {
      _isSaving = false;
    }
  }

  Future<void> deleteSheet(String id) async {
    while (_isSaving) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _isSaving = true;
    try {
      final sheets = await loadAllSheets();
      sheets.removeWhere((s) => s.id == id);
      await _saveMetadata(sheets);
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _saveMetadata(List<Spreadsheet> sheets) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File(path.join(appDir.path, _sheetsFile));
    final jsonContent = json.encode(sheets.map((e) => e.toMap()).toList());
    await file.writeAsString(jsonContent);
  }

  /// Calculates basic formulas like SUM, AVG etc.
  /// For now, this is a placeholder where results are computed before rendering.
  double evaluateFormula(String formula, List<double> values) {
    final cleanFormula = formula.toUpperCase().trim();
    
    if (cleanFormula.startsWith('=SUM')) {
      return values.fold(0, (prev, element) => prev + element);
    } else if (cleanFormula.startsWith('=AVG')) {
      if (values.isEmpty) return 0;
      return values.fold(0.0, (prev, element) => prev + element) / values.length;
    } else if (cleanFormula.startsWith('=MIN')) {
      if (values.isEmpty) return 0;
      return values.reduce((curr, next) => curr < next ? curr : next);
    } else if (cleanFormula.startsWith('=MAX')) {
      if (values.isEmpty) return 0;
      return values.reduce((curr, next) => curr > next ? curr : next);
    } else if (cleanFormula.startsWith('=COUNT')) {
      return values.length.toDouble();
    } else if (cleanFormula.startsWith('=IF')) {
      // Very basic IF parser: =IF(value > 10, trueVal, falseVal)
      // For now, if the first value in range > 0, return trueVal (usually 1), else 0
      if (values.isEmpty) return 0;
      return values.first > 0 ? 1 : 0;
    }
    return 0;
  }

  Future<Spreadsheet?> importFile(File file) async {
    final extension = path.extension(file.path).toLowerCase();
    
    List<List<dynamic>> rows = [];
    String title = path.basenameWithoutExtension(file.path);

    try {
      if (extension == '.xlsx' || extension == '.xls') {
        final bytes = file.readAsBytesSync();
        var excel = excel_pkg.Excel.decodeBytes(bytes);
        
        // Take the first table/sheet
        for (var table in excel.tables.keys) {
          final sheet = excel.tables[table];
          if (sheet != null) {
            for (var row in sheet.rows) {
              rows.add(row.map((cell) => cell?.value?.toString() ?? '').toList());
            }
            break; // Just one sheet for now
          }
        }
      } else if (extension == '.csv') {
        final input = file.readAsStringSync();
        rows = const CsvToListConverter().convert(input);
      } else {
        throw Exception("Unsupported file format: $extension");
      }

      if (rows.isEmpty) return null;

      // Determine columns (use first row as headers or A, B, C...)
      final headerRow = rows[0];
      final List<SpreadsheetColumn> columns = [];
      for (int i = 0; i < headerRow.length; i++) {
        columns.add(SpreadsheetColumn(
          id: 'col_$i',
          title: headerRow[i].toString().isNotEmpty ? headerRow[i].toString() : 'Column ${i + 1}',
          type: SpreadsheetColumnType.text,
        ));
      }

      // Map rows (starting from row 1 if headerRow was used, or row 0)
      final List<Map<String, SpreadsheetCell>> spreadsheetRows = [];
      for (int i = 1; i < rows.length; i++) {
        final Map<String, SpreadsheetCell> rowData = {};
        for (int j = 0; j < columns.length; j++) {
          final value = j < rows[i].length ? rows[i][j].toString() : '';
          rowData[columns[j].id] = SpreadsheetCell(value: value);
        }
        spreadsheetRows.add(rowData);
      }

      final newSpreadsheet = Spreadsheet(
        id: const Uuid().v4(),
        title: title,
        sheets: [
          SpreadsheetSheet(
            name: 'Sheet1',
            columns: columns,
            rows: spreadsheetRows,
          ),
        ],
        dateCreated: DateTime.now(),
        dateModified: DateTime.now(),
      );

      await saveSheet(newSpreadsheet);
      return newSpreadsheet;
    } catch (e) {
      debugPrint("Error importing spreadsheet: $e");
      return null;
    }
  }
}
