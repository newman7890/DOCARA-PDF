import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:csv/csv.dart';
import '../models/spreadsheet_model.dart';
import '../services/spreadsheet_service.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../services/ocr_table_service.dart';
import '../models/scanned_document.dart';
import 'viewer_screen.dart';
import 'spreadsheet_chart_screen.dart';

class SpreadsheetEditorScreen extends StatefulWidget {
  final Spreadsheet? sheet;

  const SpreadsheetEditorScreen({super.key, this.sheet});

  @override
  State<SpreadsheetEditorScreen> createState() => _SpreadsheetEditorScreenState();
}

class _SpreadsheetEditorScreenState extends State<SpreadsheetEditorScreen>
    with SingleTickerProviderStateMixin {
  late Spreadsheet _currentSheet;
  PlutoGridStateManager? stateManager;
  Timer? _saveTimer;
  double _zoomLevel = 1.0;
  bool _isExiting = false;

  late TabController _ribbonTabController;

  @override
  void initState() {
    super.initState();
    _currentSheet =
        widget.sheet ?? Spreadsheet.createEmpty('Untitled Spreadsheet');
    _ribbonTabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: 1,
    );
    _ribbonTabController.addListener(() {
      if (mounted) setState(() {});
    });
    _initializeGrid();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _ribbonTabController.dispose();
    super.dispose();
  }

  void _initializeGrid() {
    final activeSheet = _currentSheet.activeSheet;

    final List<PlutoColumn> columns = activeSheet.columns.map((col) {
      return PlutoColumn(
        title: col.title,
        field: col.id,
        type:
            col.type == SpreadsheetColumnType.number ||
                col.type == SpreadsheetColumnType.currency
            ? PlutoColumnType.number(format: '#,###.##')
            : col.type == SpreadsheetColumnType.date
            ? PlutoColumnType.date()
            : col.type == SpreadsheetColumnType.boolean
            ? PlutoColumnType.text() // Fallback
            : col.type == SpreadsheetColumnType.select
            ? PlutoColumnType.select(col.options ?? [])
            : PlutoColumnType.text(),
        backgroundColor: Colors.grey.shade100,
      );
    }).toList();

    final List<PlutoRow> rows = activeSheet.rows.map((rowMap) {
      final cells = <String, PlutoCell>{};
      for (var col in activeSheet.columns) {
        cells[col.id] = PlutoCell(value: rowMap[col.id]?.value ?? '');
      }
      return PlutoRow(cells: cells);
    }).toList();

    if (stateManager != null) {
      if (stateManager!.columns.isNotEmpty) {
        stateManager!.removeColumns(stateManager!.columns);
      }
      stateManager!.insertColumns(0, columns);

      if (stateManager!.rows.isNotEmpty) {
        stateManager!.removeRows(stateManager!.rows);
      }
      stateManager!.insertRows(0, rows);
    }
  }

  void _zoomIn() {
    if (_zoomLevel >= 2.0) return;
    setState(() {
      _zoomLevel = (_zoomLevel + 0.1).clamp(0.5, 2.0);
    });
    _updateGridStyle();
  }

  void _zoomOut() {
    if (_zoomLevel <= 0.5) return;
    setState(() {
      _zoomLevel = (_zoomLevel - 0.1).clamp(0.5, 2.0);
    });
    _updateGridStyle();
  }

  void _updateGridStyle() {
    if (stateManager == null) return;

    stateManager!.setConfiguration(
      PlutoGridConfiguration(
        style: PlutoGridStyleConfig(
          gridBorderColor: Colors.grey.shade300,
          activatedColor: Colors.green.withValues(alpha: 0.1),
          gridBackgroundColor: Colors.white,
          rowColor: Colors.white,
          columnTextStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13 * _zoomLevel,
          ),
          cellTextStyle: TextStyle(fontSize: 13 * _zoomLevel),
          rowHeight: 45 * _zoomLevel,
          columnHeight: 35 * _zoomLevel,
        ),
      ),
    );
  }


  void _saveCurrentSheetToModel() {
    if (stateManager == null) return;
    final activeSheet = _currentSheet.activeSheet;

    // Get true underlying rows unaffected by sorting/filtering
    final originalRows = stateManager!.refRows;

    // Capture the in-progress text if we are currently editing
    final editingCell = stateManager!.isEditing ? stateManager!.currentCell : null;
    final liveText = stateManager!.isEditing ? stateManager!.textEditingController?.text : null;

    final updatedRows = originalRows.map((plutoRow) {
      final rowData = <String, SpreadsheetCell>{};
      for (var col in activeSheet.columns) {
        final cell = plutoRow.cells[col.id];
        
        // Use live editor text if this is the cell being edited
        String val;
        if (editingCell != null && cell != null && cell.key == editingCell.key) {
          val = liveText ?? cell.value?.toString() ?? '';
        } else {
          val = cell?.value?.toString() ?? '';
        }
        
        rowData[col.id] = SpreadsheetCell(value: val);
      }
      return rowData;
    }).toList();

    final updatedSheets = List<SpreadsheetSheet>.from(_currentSheet.sheets);
    updatedSheets[_currentSheet.activeSheetIndex] = activeSheet.copyWith(
      rows: updatedRows,
    );

    setState(() {
      _currentSheet = _currentSheet.copyWith(sheets: updatedSheets);
    });
  }

  Future<void> _handleSave() async {
    if (stateManager == null) return;

    _saveCurrentSheetToModel();
    await _persistToStorage();
    _showSuccessMessage('Spreadsheet saved locally');
  }

  /// Called on every cell change
  void _onCellChanged(PlutoGridOnChangedEvent event) {
    if (stateManager == null) return;
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        _saveCurrentSheetToModel();
        _persistToStorage();
      }
    });
  }

  void _addRow() {
    if (stateManager == null) return;

    // 1. Add to grid UI
    stateManager!.insertRows(stateManager!.refRows.length, [
      stateManager!.getNewRow(),
    ]);

    // 2. Schedule a sync
    _scheduleSave();
    _showSuccessMessage('Row Added');
  }

  void _removeRow() {
    if (stateManager == null || stateManager!.currentRow == null) {
      _showSuccessMessage('Please select a cell first');
      return;
    }

    // Don't allow removing the last row
    if (stateManager!.rows.length <= 1) {
      _showSuccessMessage('Cannot remove the only remaining row');
      return;
    }

    final currentRow = stateManager!.currentRow;

    // 1. Remove from grid UI
    stateManager!.removeRows([currentRow!]);

    // 2. Sync to model
    _scheduleSave();
    _showSuccessMessage('Row Deleted');
  }

  void _calculateFormula(String formulaType) {
    if (stateManager == null || stateManager!.currentCell == null) return;

    double sum = 0;
    int count = 0;
    double min = double.infinity;
    double max = double.negativeInfinity;

    for (var row in stateManager!.rows) {
      final valStr =
          row.cells[stateManager!.currentColumn!.field]?.value.toString() ?? '';
      final val = double.tryParse(valStr.replaceAll(',', ''));
      if (val != null) {
        sum += val;
        count++;
        if (val < min) min = val;
        if (val > max) max = val;
      }
    }

    if (count == 0) {
      _showSuccessMessage('No numeric data in column');
      return;
    }

    dynamic result;
    if (formulaType == 'SUM') {
      result = sum;
    } else if (formulaType == 'AVG') {
      result = sum / count;
    } else if (formulaType == 'MIN') {
      result = min;
    } else if (formulaType == 'MAX') {
      result = max;
    } else if (formulaType == 'COUNT') {
      result = count;
    }

    final finalVal = result is double
        ? result.toStringAsFixed(2)
        : result.toString();
    stateManager!.changeCellValue(stateManager!.currentCell!, finalVal);
    _showSuccessMessage('$formulaType Result: $finalVal');
  }

  Future<void> _exportToPdfAndNavigate() async {
    if (stateManager == null) return;
    final pdfService = context.read<PDFService>();
    final storage = context.read<StorageService>();

    _saveCurrentSheetToModel();

    final directory = await getApplicationDocumentsDirectory();
    final outputPath =
        "${directory.path}/${_currentSheet.title.replaceAll(' ', '_')}.pdf";

    final file = await pdfService.exportSpreadsheetToPdf(
      _currentSheet,
      outputPath,
    );

    final newDoc = ScannedDocument(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: _currentSheet.title.endsWith('.pdf')
          ? _currentSheet.title
          : "${_currentSheet.title}.pdf",
      filePath: file.path,
      dateCreated: DateTime.now(),
    );
    await storage.saveDocument(newDoc);

    if (mounted) {
      _showSuccessMessage('Exported to PDF Successfully');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfViewerScreen(document: newDoc),
        ),
      );
    }
  }

  Future<void> _handleShare() async {
    if (stateManager == null) return;
    _saveCurrentSheetToModel();

    final pdfService = context.read<PDFService>();
    final directory = await getTemporaryDirectory();
    final outputPath =
        "${directory.path}/${_currentSheet.title.replaceAll(' ', '_')}.pdf";
    final file = await pdfService.exportSpreadsheetToPdf(
      _currentSheet,
      outputPath,
    );

    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'Check out this spreadsheet: ${_currentSheet.title}');
  }

  Future<void> _handleExportCSV() async {
    if (stateManager == null) return;
    final activeSheet = _currentSheet.activeSheet;

    final List<List<dynamic>> csvData = [];
    csvData.add(activeSheet.columns.map((c) => c.title).toList());

    for (var row in stateManager!.rows) {
      csvData.add(
        activeSheet.columns
            .map((col) => row.cells[col.id]?.value ?? '')
            .toList(),
      );
    }

    String csv = const ListToCsvConverter().convert(csvData);
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/${_currentSheet.title.replaceAll(' ', '_')}.csv',
    );
    await file.writeAsString(csv);

    _showSuccessMessage('Exported to CSV');
    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'CSV Export: ${_currentSheet.title}');
  }

  Future<void> _handleExportExcel() async {
    if (stateManager == null) return;
    var excel = excel_pkg.Excel.createExcel();

    for (var sheetModel in _currentSheet.sheets) {
      var sheet = excel[sheetModel.name];
      for (var i = 0; i < sheetModel.columns.length; i++) {
        var cell = sheet.cell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
        );
        cell.value = excel_pkg.TextCellValue(sheetModel.columns[i].title);
      }
      for (var r = 0; r < sheetModel.rows.length; r++) {
        var rowMap = sheetModel.rows[r];
        for (var c = 0; c < sheetModel.columns.length; c++) {
          var cell = sheet.cell(
            excel_pkg.CellIndex.indexByColumnRow(
              columnIndex: c,
              rowIndex: r + 1,
            ),
          );
          cell.value = excel_pkg.TextCellValue(
            rowMap[sheetModel.columns[c].id]?.value ?? '',
          );
        }
      }
    }

    if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

    final directory = await getApplicationDocumentsDirectory();
    final fileBytes = excel.encode();
    if (fileBytes != null) {
      final file = File(
        '${directory.path}/${_currentSheet.title.replaceAll(' ', '_')}.xlsx',
      );
      await file.writeAsBytes(fileBytes);
      _showSuccessMessage('Exported to Excel');
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Excel Export: ${_currentSheet.title}');
    }
  }

  void _addColumn() async {
    if (stateManager == null) return;

    final titleController = TextEditingController();
    SpreadsheetColumnType selectedType = SpreadsheetColumnType.text;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Column'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Column Title'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SpreadsheetColumnType>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Column Type'),
                items: SpreadsheetColumnType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.name.toUpperCase()),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedType = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && titleController.text.trim().isNotEmpty) {
      final title = titleController.text.trim();
      final newColId = 'col_${DateTime.now().millisecondsSinceEpoch}';

      final newModelCol = SpreadsheetColumn(
        id: newColId,
        title: title,
        type: selectedType,
      );

      // Add to model
      setState(() {
        final activeSheet = _currentSheet.activeSheet;
        final updatedSheets = List<SpreadsheetSheet>.from(_currentSheet.sheets);

        final updatedSheet = activeSheet.copyWith(
          columns: [...activeSheet.columns, newModelCol],
          rows: activeSheet.rows
              .map((row) => {...row, newColId: SpreadsheetCell(value: '')})
              .toList(),
        );

        updatedSheets[_currentSheet.activeSheetIndex] = updatedSheet;
        _currentSheet = _currentSheet.copyWith(sheets: updatedSheets);
      });

      // Add to grid
      final plutoCol = PlutoColumn(
        title: title,
        field: newColId,
        type:
            selectedType == SpreadsheetColumnType.number ||
                selectedType == SpreadsheetColumnType.currency
            ? PlutoColumnType.number(format: '#,###.##')
            : selectedType == SpreadsheetColumnType.date
            ? PlutoColumnType.date()
            : selectedType == SpreadsheetColumnType.boolean
            ? PlutoColumnType.text() // Fallback to text until correct boolean property is found
            : selectedType == SpreadsheetColumnType.select
            ? PlutoColumnType.select([])
            : PlutoColumnType.text(),
        backgroundColor: Colors.grey.shade100,
      );

      stateManager!.insertColumns(stateManager!.columns.length, [plutoCol]);

      // Add empty cells to all rows in stateManager
      for (var row in stateManager!.rows) {
        row.cells[newColId] = PlutoCell(value: '');
      }
      stateManager!.notifyListeners();
      _scheduleSave();
    }
  }

  Future<void> _scanTable() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      final ocrService = OCRTableService();
      final data = await ocrService.scanTable(image.path);
      ocrService.dispose();

      if (data.isNotEmpty) {
        // Create new columns based on max row length
        int maxCols = 0;
        for (var row in data) {
          if (row.length > maxCols) maxCols = row.length;
        }

        final List<SpreadsheetColumn> newColumns = [];
        for (int i = 0; i < maxCols; i++) {
          newColumns.add(
            SpreadsheetColumn(
              id: 'scan_col_$i',
              title: i < data[0].length
                  ? data[0][i].replaceAll('\n', ' ')
                  : 'Column $i',
            ),
          );
        }

        final List<Map<String, SpreadsheetCell>> newRows = [];
        // Skip first row if it was used as header, or keep all
        for (int i = 0; i < data.length; i++) {
          final Map<String, SpreadsheetCell> rowData = {};
          for (int j = 0; j < newColumns.length; j++) {
            final value = j < data[i].length
                ? data[i][j].replaceAll('\n', ' ')
                : '';
            rowData[newColumns[j].id] = SpreadsheetCell(value: value);
          }
          newRows.add(rowData);
        }

        setState(() {
          final updatedSheets = List<SpreadsheetSheet>.from(
            _currentSheet.sheets,
          );
          updatedSheets[_currentSheet.activeSheetIndex] = _currentSheet
              .activeSheet
              .copyWith(columns: newColumns, rows: newRows);
          _currentSheet = _currentSheet.copyWith(sheets: updatedSheets);
          _initializeGrid();
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Table scanned and imported!')),
          );
        }
      }
    }
  }

  void _showChartScreen() {
    _commitCurrentEdit();
    _saveCurrentSheetToModel();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SpreadsheetChartScreen(sheet: _currentSheet.activeSheet),
      ),
    );
  }

  void _switchSheet(int index) async {
    if (index == _currentSheet.activeSheetIndex) return;

    _commitCurrentEdit();
    _saveCurrentSheetToModel();
    await _persistToStorage();

    setState(() {
      _currentSheet = _currentSheet.copyWith(activeSheetIndex: index);
      _initializeGrid();
    });
  }

  void _addNewSheet() {
    _commitCurrentEdit();
    _saveCurrentSheetToModel();
    final newName = "Sheet${_currentSheet.sheets.length + 1}";
    final newSheet = SpreadsheetSheet(
      name: newName,
      columns: [
        SpreadsheetColumn(id: 'col1', title: 'Column 1'),
        SpreadsheetColumn(id: 'col2', title: 'Column 2'),
        SpreadsheetColumn(id: 'col3', title: 'Column 3'),
      ],
      rows: List.generate(10, (_) => {}),
    );

    setState(() {
      _currentSheet = _currentSheet.copyWith(
        sheets: [..._currentSheet.sheets, newSheet],
        activeSheetIndex: _currentSheet.sheets.length,
      );
      _initializeGrid();
    });
  }

  void _removeSheet(int index) async {
    if (_currentSheet.sheets.length <= 1) {
      _showSuccessMessage('Cannot delete the only remaining sheet');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sheet'),
        content: Text('Are you sure you want to delete "${_currentSheet.sheets[index].name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _commitCurrentEdit();
      setState(() {
        final updatedSheets = List<SpreadsheetSheet>.from(_currentSheet.sheets);
        updatedSheets.removeAt(index);

        int newActiveIndex = _currentSheet.activeSheetIndex;
        if (index == _currentSheet.activeSheetIndex) {
          newActiveIndex = 0; // Fallback to first sheet
        } else if (index < _currentSheet.activeSheetIndex) {
          newActiveIndex--; // Shift active index back
        }

        _currentSheet = _currentSheet.copyWith(
          sheets: updatedSheets,
          activeSheetIndex: newActiveIndex,
        );
        _initializeGrid();
      });
      _scheduleSave();
      _showSuccessMessage('Sheet Deleted');
    }
  }

  void _removeColumn() {
    if (stateManager == null) return;

    // Use current cell to find the column reliably
    final currentCell = stateManager!.currentCell;
    if (currentCell == null) {
      _showSuccessMessage('Please select a cell in the column to remove');
      return;
    }

    final columnId = currentCell.column.field;
    final columnToRemove = stateManager!.columns.firstWhere(
      (c) => c.field == columnId,
    );

    // Don't allow removing the last column to prevent empty state issues
    if (stateManager!.columns.length <= 1) {
      _showSuccessMessage('Cannot remove the only remaining column');
      return;
    }

    stateManager!.removeColumns([columnToRemove]);

    // Update local model
    setState(() {
      final activeSheetIndex = _currentSheet.activeSheetIndex;
      final activeSheet = _currentSheet.activeSheet;

      // Filter out the column from the model
      final updatedColumns = activeSheet.columns
          .where((c) => c.id != columnId)
          .toList();

      // Filter out the field from all rows in the model
      final updatedRows = activeSheet.rows.map((rowMap) {
        final newMap = Map<String, SpreadsheetCell>.from(rowMap);
        newMap.remove(columnId);
        return newMap;
      }).toList();

      final updatedSheet = activeSheet.copyWith(
        columns: updatedColumns,
        rows: updatedRows,
      );

      final updatedSheets = List<SpreadsheetSheet>.from(_currentSheet.sheets);
      updatedSheets[activeSheetIndex] = updatedSheet;
      _currentSheet = _currentSheet.copyWith(sheets: updatedSheets);
    });

    _scheduleSave();
    _showSuccessMessage('Column Removed');
  }

  /// Explicitly captures the unfinished text in the active cell and forces it
  /// into the data model before we exit or perform a final save scan.
  void _commitCurrentEdit() {
    if (stateManager == null) return;
    if (stateManager!.isEditing) {
      final cell = stateManager!.currentCell;
      final textController = stateManager!.textEditingController;
      
      if (cell != null && textController != null) {
        stateManager!.changeCellValue(cell, textController.text, force: true);
      }
    }
    stateManager!.setKeepFocus(false);
    stateManager!.setCurrentCell(null, null, notify: false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isExiting) return;
        _isExiting = true;

        // Capture Navigator before async gap
        final navigator = Navigator.of(context);

        // Cancel any pending background saves to prevent race condition
        _saveTimer?.cancel();

        // Force-commit any active cell edit
        _commitCurrentEdit();
        await Future.delayed(Duration.zero);

        _saveCurrentSheetToModel();
        await _persistToStorage();

        if (mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF217346), // Excel Green
          title: Text(
            _currentSheet.title,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (_isExiting) return;
                _isExiting = true;

                // Capture Navigator before async gap
                final navigator = Navigator.of(context);

                // Cancel any pending background saves to prevent race condition
                _saveTimer?.cancel();

                // Force-commit any active cell edit
                _commitCurrentEdit();
                await Future.delayed(Duration.zero);

                _saveCurrentSheetToModel();
                final success = await _persistToStorage();

                if (mounted) {
                  navigator.pop();
                  if (success) {
                    _showSuccessMessage('Changes Saved');
                  } else {
                    _showErrorMessage('Error saving changes');
                  }
                }
              },
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              onPressed: _exportToPdfAndNavigate,
              tooltip: 'Export',
            ),
          ],
        ),
        body: Column(
          children: [
            // Excel Ribbon Tabs
            Container(
              color: Colors.grey.shade100,
              child: TabBar(
                controller: _ribbonTabController,
                isScrollable: true,
                labelColor: const Color(0xFF217346),
                unselectedLabelColor: Colors.black87,
                indicatorColor: const Color(0xFF217346),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(text: 'File'),
                  Tab(text: 'Home'),
                  Tab(text: 'Insert'),
                  Tab(text: 'Data'),
                ],
              ),
            ),
            // Ribbon Actions
            Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  if (_ribbonTabController.index == 0) // File
                    _buildRibbonGroup('Actions', [
                      _buildRibbonAction(Icons.save, 'Save', _handleSave),
                      _buildRibbonAction(
                        Icons.picture_as_pdf,
                        'PDF',
                        _exportToPdfAndNavigate,
                      ),
                      _buildRibbonAction(Icons.share, 'Share', _handleShare),
                    ]),
                  if (_ribbonTabController.index == 1) // Home
                  ...[
                    _buildRibbonGroup('Rows', [
                      _buildRibbonAction(Icons.add_box, 'Insert', _addRow),
                      _buildRibbonAction(
                        Icons.indeterminate_check_box,
                        'Delete',
                        _removeRow,
                      ),
                    ]),
                    const VerticalDivider(),
                    _buildRibbonGroup('Columns', [
                      _buildRibbonAction(Icons.view_column, 'Add', _addColumn),
                      _buildRibbonAction(
                        Icons.view_column_outlined,
                        'Remove',
                        _removeColumn,
                      ),
                    ]),
                    const VerticalDivider(),
                    _buildRibbonGroup('Format', [
                      _buildRibbonAction(
                        Icons.text_format,
                        'Format',
                        () => _showSuccessMessage('Formatting options coming soon'),
                      ),
                    ]),
                  ],
                  if (_ribbonTabController.index == 2) // Insert
                    _buildRibbonGroup('Data Export', [
                      _buildRibbonAction(
                        Icons.table_chart,
                        'Excel',
                        _handleExportExcel,
                      ),
                      _buildRibbonAction(
                        Icons.description,
                        'CSV',
                        _handleExportCSV,
                      ),
                      _buildRibbonAction(
                        Icons.camera_alt,
                        'Scan Table',
                        _scanTable,
                      ),
                      _buildRibbonAction(
                        Icons.pie_chart,
                        'Charts',
                        _showChartScreen,
                      ),
                    ]),
                  if (_ribbonTabController.index == 3) // Data
                    _buildRibbonGroup('Formulas', [
                      _buildRibbonAction(
                        Icons.functions,
                        'Sum',
                        () => _calculateFormula('SUM'),
                      ),
                      _buildRibbonAction(
                        Icons.analytics,
                        'Avg',
                        () => _calculateFormula('AVG'),
                      ),
                      _buildRibbonAction(
                        Icons.vertical_align_bottom,
                        'Min',
                        () => _calculateFormula('MIN'),
                      ),
                      _buildRibbonAction(
                        Icons.vertical_align_top,
                        'Max',
                        () => _calculateFormula('MAX'),
                      ),
                      _buildRibbonAction(
                        Icons.format_list_numbered,
                        'Count',
                        () => _calculateFormula('COUNT'),
                      ),
                    ]),
                ],
              ),
            ),
            // Grid
            Expanded(
              child: Stack(
                children: [
                  PlutoGrid(
                    columns: _currentSheet.activeSheet.columns.map((col) {
                      return PlutoColumn(
                        title: col.title,
                        field: col.id,
                        type: col.type == SpreadsheetColumnType.number || col.type == SpreadsheetColumnType.currency
                            ? PlutoColumnType.number(format: '#,###.##')
                            : col.type == SpreadsheetColumnType.date
                                ? PlutoColumnType.date()
                                : PlutoColumnType.text(),
                        backgroundColor: Colors.grey.shade100,
                      );
                    }).toList(),
                    rows: _currentSheet.activeSheet.rows.map((rowMap) {
                      final cells = <String, PlutoCell>{};
                      for (var col in _currentSheet.activeSheet.columns) {
                        cells[col.id] = PlutoCell(value: rowMap[col.id]?.value ?? '');
                      }
                      return PlutoRow(cells: cells);
                    }).toList(),
                    onChanged: (PlutoGridOnChangedEvent event) {
                      _onCellChanged(event);
                    },
                    onLoaded: (PlutoGridOnLoadedEvent event) {
                      stateManager = event.stateManager;
                      stateManager!.setShowColumnFilter(true);
                    },
                    configuration: PlutoGridConfiguration(
                      style: PlutoGridStyleConfig(
                        gridBorderColor: Colors.grey.shade300,
                        activatedColor: Colors.green.withValues(alpha: 0.1),
                        gridBackgroundColor: Colors.white,
                        rowColor: Colors.white,
                        columnTextStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13 * _zoomLevel,
                        ),
                        cellTextStyle: TextStyle(fontSize: 13 * _zoomLevel),
                        rowHeight: 45 * _zoomLevel,
                        columnHeight: 35 * _zoomLevel,
                      ),
                    ),
                  ),
                  // Hide the PlutoGrid free-tier watermark (Bottom Corner)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 140,
                      height: 20,
                      color: Colors.white,
                    ),
                  ),
                  // Hide the PlutoGrid free-tier watermark (Right Edge Text)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    child: Container(width: 20, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Sheet Tabs (Bottom)
            Container(
              height: 35,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Manage Sheets'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _currentSheet.sheets.asMap().entries.map((
                              entry,
                            ) {
                                return ListTile(
                                  title: Text(entry.value.name),
                                  leading: const Icon(Icons.table_chart),
                                  selected:
                                      entry.key == _currentSheet.activeSheetIndex,
                                  trailing: _currentSheet.sheets.length > 1
                                      ? IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 20, color: Colors.red),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _removeSheet(entry.key);
                                          },
                                        )
                                      : null,
                                onTap: () {
                                  _switchSheet(entry.key);
                                  Navigator.pop(ctx);
                                },
                              );
                            }).toList(),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                _addNewSheet();
                                Navigator.pop(ctx);
                              },
                              child: const Text('Add Sheet'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.menu, size: 18, color: Colors.grey),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...List.generate(_currentSheet.sheets.length, (
                            index,
                          ) {
                            return _buildSheetTab(
                              _currentSheet.sheets[index].name,
                              index == _currentSheet.activeSheetIndex,
                              () => _switchSheet(index),
                              () => _removeSheet(index),
                            );
                          }),
                          IconButton(
                            onPressed: _addNewSheet,
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 18,
                              color: Colors.grey,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _zoomOut,
                    icon: const Icon(
                      Icons.zoom_out,
                      size: 18,
                      color: Colors.grey,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Zoom Out',
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(_zoomLevel * 100).toInt()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _zoomIn,
                    icon: const Icon(
                      Icons.zoom_in,
                      size: 18,
                      color: Colors.grey,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Zoom In',
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _persistToStorage() async {
    try {
      final service = context.read<SpreadsheetService>();
      debugPrint("Persisting spreadsheet [${_currentSheet.id}] to storage...");
      await service.saveSheet(_currentSheet);
      debugPrint("Spreadsheet persisted successfully");
      return true;
    } catch (e) {
      debugPrint("Error persisting spreadsheet: $e");
      return false;
    }
  }

  void _showErrorMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red,
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _showSuccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        backgroundColor: const Color(0xFF217346), // Excel Green
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildRibbonGroup(String label, List<Widget> children) {
    return Column(
      children: [
        Row(children: children),
        const Spacer(),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildRibbonAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 22, color: Colors.black87),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetTab(
    String name,
    bool isActive,
    VoidCallback onTap,
    VoidCallback onLongPress,
  ) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          border: isActive
              ? const Border(
                  bottom: BorderSide(color: Color(0xFF217346), width: 2),
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? const Color(0xFF217346) : Colors.black87,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
