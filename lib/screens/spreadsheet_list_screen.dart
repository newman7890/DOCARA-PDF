import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/spreadsheet_model.dart';
import '../services/spreadsheet_service.dart';
import '../services/spreadsheet_template_factory.dart';
import 'spreadsheet_editor_screen.dart';

class SpreadsheetListScreen extends StatefulWidget {
  const SpreadsheetListScreen({super.key});

  @override
  State<SpreadsheetListScreen> createState() => _SpreadsheetListScreenState();
}

class _SpreadsheetListScreenState extends State<SpreadsheetListScreen> {
  late Future<List<Spreadsheet>> _sheetsFuture;

  @override
  void initState() {
    super.initState();
    _refreshSheets();
  }

  void _refreshSheets() {
    setState(() {
      _sheetsFuture = context.read<SpreadsheetService>().loadAllSheets();
    });
  }

  Future<void> _importSpreadsheet() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final sheetService = context.read<SpreadsheetService>();

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);

      final newSheet = await sheetService.importFile(file);

      if (newSheet != null) {
        _refreshSheets();
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Spreadsheet imported successfully')),
          );
          navigator.push(
            MaterialPageRoute(
              builder: (_) => SpreadsheetEditorScreen(sheet: newSheet),
            ),
          ).then((_) => _refreshSheets());
        }
      } else {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Failed to import spreadsheet')),
          );
        }
      }
    }
  }

  Future<void> _createNewSheet() async {
    final navigator = Navigator.of(context);
    final sheetService = context.read<SpreadsheetService>();
    final controller = TextEditingController();
    
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Spreadsheet'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Title'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Create')),
        ],
      ),
    );

    if (title != null && title.trim().isNotEmpty) {
      final sheet = Spreadsheet.createEmpty(title.trim());
      await sheetService.saveSheet(sheet);
      _refreshSheets();
      
      if (mounted) {
        navigator.push(
          MaterialPageRoute(
            builder: (_) => SpreadsheetEditorScreen(sheet: sheet),
          ),
        ).then((_) => _refreshSheets());
      }
    }
  }

  void _showTemplateGallery() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Start from Template',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildTemplateOption(
                ctx,
                Icons.account_balance_wallet,
                'Monthly Budget',
                'Track income and expenses',
                () => SpreadsheetTemplateFactory.createMonthlyBudget(),
              ),
              _buildTemplateOption(
                ctx,
                Icons.inventory,
                'Inventory List',
                'Manage stock and reorders',
                () => SpreadsheetTemplateFactory.createInventory(),
              ),
              _buildTemplateOption(
                ctx,
                Icons.description,
                'Invoice Template',
                'Professional billing and rates',
                () => SpreadsheetTemplateFactory.createInvoice(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateOption(BuildContext context, IconData icon, String title, String subtitle, Spreadsheet Function() creator) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.green.shade50,
        child: Icon(icon, color: Colors.green),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      onTap: () async {
        final navigator = Navigator.of(context);
        Navigator.pop(context);
        final sheet = creator();
        await context.read<SpreadsheetService>().saveSheet(sheet);
        _refreshSheets();
        if (context.mounted) {
          navigator.push(
            MaterialPageRoute(
              builder: (_) => SpreadsheetEditorScreen(sheet: sheet),
            ),
          ).then((_) => _refreshSheets());
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Spreadsheets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dashboard_customize),
            onPressed: _showTemplateGallery,
            tooltip: 'Templates',
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _importSpreadsheet,
            tooltip: 'Import Spreadsheet',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewSheet,
            tooltip: 'New Spreadsheet',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshSheets,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: FutureBuilder<List<Spreadsheet>>(
        future: _sheetsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.table_chart_outlined, size: 64, color: Colors.grey),
                   const SizedBox(height: 16),
                   const Text('No spreadsheets found'),
                   const SizedBox(height: 24),
                   ElevatedButton.icon(
                     onPressed: _createNewSheet,
                     icon: const Icon(Icons.add),
                     label: const Text('Create New Spreadsheet'),
                   ),
                   const SizedBox(height: 12),
                   OutlinedButton.icon(
                     onPressed: _showTemplateGallery,
                     icon: const Icon(Icons.dashboard_customize),
                     label: const Text('New from Template'),
                   ),
                   const SizedBox(height: 12),
                   TextButton.icon(
                     onPressed: _importSpreadsheet,
                     icon: const Icon(Icons.file_upload),
                     label: const Text('Import from Phone (.xlsx, .csv)'),
                   ),
                ],
              ),
            );
          }

          final sheets = snapshot.data!;
          return ListView.builder(
            itemCount: sheets.length,
            itemBuilder: (context, index) {
              final sheet = sheets[index];
              return ListTile(
                leading: const Icon(Icons.table_chart, color: Colors.green),
                title: Text(sheet.title),
                subtitle: Text('Last modified: ${sheet.dateModified.toString().split('.')[0]}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final sheetService = context.read<SpreadsheetService>();
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Spreadsheet'),
                        content: const Text('Are you sure you want to delete this sheet permanently?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );

                    if (confirm == true && mounted) {
                      await sheetService.deleteSheet(sheet.id);
                      _refreshSheets();
                    }
                  },
                ),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await navigator.push(
                    MaterialPageRoute(builder: (context) => SpreadsheetEditorScreen(sheet: sheet)),
                  );
                  if (mounted) _refreshSheets();
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
           final navigator = Navigator.of(context);
           await navigator.push(
             MaterialPageRoute(builder: (context) => const SpreadsheetEditorScreen()),
           );
           if (mounted) _refreshSheets();
        },
        backgroundColor: Colors.indigo,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
