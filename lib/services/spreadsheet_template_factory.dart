import 'package:uuid/uuid.dart';
import '../models/spreadsheet_model.dart';

class SpreadsheetTemplateFactory {
  static Spreadsheet createMonthlyBudget() {
    final now = DateTime.now();
    final columns = [
      SpreadsheetColumn(id: 'date', title: 'Date', type: SpreadsheetColumnType.date),
      SpreadsheetColumn(id: 'category', title: 'Category', type: SpreadsheetColumnType.select, options: ['Rent', 'Food', 'Transport', 'Utilities', 'Other']),
      SpreadsheetColumn(id: 'amount', title: 'Amount', type: SpreadsheetColumnType.currency, format: 'GHS'),
      SpreadsheetColumn(id: 'paid', title: 'Paid?', type: SpreadsheetColumnType.boolean),
      SpreadsheetColumn(id: 'notes', title: 'Notes', type: SpreadsheetColumnType.text),
    ];

    final rows = List.generate(10, (_) => {
      'date': SpreadsheetCell(value: now.toIso8601String().split('T')[0]),
      'category': SpreadsheetCell(value: 'Food'),
      'amount': SpreadsheetCell(value: '0'),
      'paid': SpreadsheetCell(value: 'false'),
      'notes': SpreadsheetCell(value: ''),
    });

    return Spreadsheet(
      id: const Uuid().v4(),
      title: 'Monthly Budget',
      sheets: [
        SpreadsheetSheet(
          name: 'Budget',
          columns: columns,
          rows: rows,
        ),
      ],
      dateCreated: now,
      dateModified: now,
    );
  }

  static Spreadsheet createInventory() {
    final now = DateTime.now();
    final columns = [
      SpreadsheetColumn(id: 'item', title: 'Item Name', type: SpreadsheetColumnType.text),
      SpreadsheetColumn(id: 'sku', title: 'SKU/Code', type: SpreadsheetColumnType.text),
      SpreadsheetColumn(id: 'qty', title: 'Quantity', type: SpreadsheetColumnType.number),
      SpreadsheetColumn(id: 'price', title: 'Unit Price', type: SpreadsheetColumnType.currency, format: 'GHS'),
      SpreadsheetColumn(id: 'reorder', title: 'Reorder?', type: SpreadsheetColumnType.boolean),
    ];

    final rows = List.generate(10, (_) => {
      'item': SpreadsheetCell(value: ''),
      'sku': SpreadsheetCell(value: ''),
      'qty': SpreadsheetCell(value: '0'),
      'price': SpreadsheetCell(value: '0'),
      'reorder': SpreadsheetCell(value: 'false'),
    });

    return Spreadsheet(
      id: const Uuid().v4(),
      title: 'Inventory List',
      sheets: [
        SpreadsheetSheet(
          name: 'Inventory',
          columns: columns,
          rows: rows,
        ),
      ],
      dateCreated: now,
      dateModified: now,
    );
  }

  static Spreadsheet createInvoice() {
    final now = DateTime.now();
    final columns = [
      SpreadsheetColumn(id: 'desc', title: 'Description', type: SpreadsheetColumnType.text),
      SpreadsheetColumn(id: 'qty', title: 'Qty', type: SpreadsheetColumnType.number),
      SpreadsheetColumn(id: 'rate', title: 'Rate', type: SpreadsheetColumnType.currency, format: 'GHS'),
      SpreadsheetColumn(id: 'total', title: 'Total', type: SpreadsheetColumnType.currency, format: 'GHS'),
    ];

    final rows = List.generate(5, (_) => {
      'desc': SpreadsheetCell(value: ''),
      'qty': SpreadsheetCell(value: '1'),
      'rate': SpreadsheetCell(value: '0'),
      'total': SpreadsheetCell(value: '0'),
    });

    return Spreadsheet(
      id: const Uuid().v4(),
      title: 'Invoice Template',
      sheets: [
        SpreadsheetSheet(
          name: 'Items',
          columns: columns,
          rows: rows,
        ),
        SpreadsheetSheet(
          name: 'Client Details',
          columns: [
            SpreadsheetColumn(id: 'field', title: 'Field'),
            SpreadsheetColumn(id: 'value', title: 'Value'),
          ],
          rows: [
            {'field': SpreadsheetCell(value: 'Client Name'), 'value': SpreadsheetCell(value: '')},
            {'field': SpreadsheetCell(value: 'Address'), 'value': SpreadsheetCell(value: '')},
          ],
        ),
      ],
      dateCreated: now,
      dateModified: now,
    );
  }
}
