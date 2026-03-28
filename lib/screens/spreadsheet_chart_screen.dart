import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/spreadsheet_model.dart';

class SpreadsheetChartScreen extends StatefulWidget {
  final SpreadsheetSheet sheet;

  const SpreadsheetChartScreen({Key? key, required this.sheet}) : super(key: key);

  @override
  _SpreadsheetChartScreenState createState() => _SpreadsheetChartScreenState();
}

class _SpreadsheetChartScreenState extends State<SpreadsheetChartScreen> {
  final GlobalKey _chartKey = GlobalKey();
  String? _selectedLabelCol;
  String? _selectedValueCol;
  bool _isPieChart = true;

  Future<void> _captureAndShare() async {
    try {
      RenderRepaintBoundary boundary = _chartKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/chart_export.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Check out this chart from DOCARA PDF!');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to export chart: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.sheet.columns.isNotEmpty) {
      _selectedLabelCol = widget.sheet.columns.first.id;
      if (widget.sheet.columns.length > 1) {
        // Try to find a numeric column for values
        final numCol = widget.sheet.columns.where((c) => c.type == SpreadsheetColumnType.number || c.type == SpreadsheetColumnType.currency).firstOrNull;
        _selectedValueCol = numCol?.id ?? widget.sheet.columns.last.id;
      } else {
        _selectedValueCol = widget.sheet.columns.first.id;
      }
    }
  }

  Map<String, double> _processData() {
    if (_selectedLabelCol == null || _selectedValueCol == null) return {};

    final Map<String, double> aggregatedData = {};

    for (var row in widget.sheet.rows) {
      final labelCell = row[_selectedLabelCol!];
      final valueCell = row[_selectedValueCol!];

      final String labelStr = (labelCell?.value?.toString() ?? 'Empty').trim();
      final String label = labelStr.isEmpty ? 'Empty' : labelStr;

      final String valueStr = (valueCell?.value?.toString() ?? '0').replaceAll(',', '').trim();
      final double value = double.tryParse(valueStr) ?? 0.0;

      if (aggregatedData.containsKey(label)) {
        aggregatedData[label] = aggregatedData[label]! + value;
      } else {
        aggregatedData[label] = value;
      }
    }

    return aggregatedData;
  }

  // Generate deterministic colors based on label hash
  Color _getColorForLabel(String label, int index) {
    const defaultColors = [
      Color(0xFF2196F3), Color(0xFFF44336), Color(0xFF4CAF50),
      Color(0xFFFF9800), Color(0xFF9C27B0), Color(0xFF00BCD4),
      Color(0xFFE91E63), Color(0xFFFFC107), Color(0xFF3F51B5),
      Color(0xFF8BC34A), Color(0xFF795548), Color(0xFF607D8B),
    ];
    return defaultColors[index % defaultColors.length];
  }

  Widget _buildChart() {
    final data = _processData();
    if (data.isEmpty) {
      return const Center(child: Text("No data to display"));
    }

    if (_isPieChart) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 50,
            sections: data.entries.toList().asMap().entries.map((entry) {
              final index = entry.key;
              final mapEntry = entry.value;
              final value = mapEntry.value;
              // Avoid rendering negative pie segments, which breaks PieChart
              final safeValue = value < 0 ? 0.0 : value;

              return PieChartSectionData(
                color: _getColorForLabel(mapEntry.key, index),
                value: safeValue,
                title: '\$${safeValue.toStringAsFixed(0)}', // Basic formatting
                radius: 100,
                titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
              );
            }).toList(),
          ),
        ),
      );
    } else {
      // Bar Chart
      double maxY = 0;
      for (var val in data.values) {
        if (val > maxY) maxY = val;
      }
      
      return Padding(
        padding: const EdgeInsets.only(top: 24.0, right: 16.0, bottom: 24.0, left: 16.0),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY * 1.2,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => Colors.blueGrey,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  return BarTooltipItem(
                    rod.toY.round().toString(),
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) {
                     final index = value.toInt();
                     final entries = data.entries.toList();
                     if (index < 0 || index >= entries.length) return const SizedBox.shrink();
                     return Padding(
                       padding: const EdgeInsets.only(top: 8.0),
                       child: Text(
                         entries[index].key,
                         style: const TextStyle(fontSize: 10),
                         overflow: TextOverflow.ellipsis,
                       ),
                     );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 40),
              ),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            barGroups: data.entries.toList().asMap().entries.map((entry) {
               final index = entry.key;
               final mapEntry = entry.value;
               return BarChartGroupData(
                 x: index,
                 barRods: [
                   BarChartRodData(
                     toY: mapEntry.value > 0 ? mapEntry.value : 0,
                     color: _getColorForLabel(mapEntry.key, index),
                     width: 20,
                     borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                   ),
                 ],
               );
            }).toList(),
          ),
        ),
      );
    }
  }

  Widget _buildLegend() {
    final data = _processData();
    if (data.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: data.entries.toList().asMap().entries.map((entry) {
        final index = entry.key;
        final mapEntry = entry.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              color: _getColorForLabel(mapEntry.key, index),
            ),
            const SizedBox(width: 4),
            Text(mapEntry.key, style: const TextStyle(fontSize: 12)),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sheet.columns.isEmpty) {
      return Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFF217346), title: const Text('Chart Data', style: TextStyle(color: Colors.white))),
        body: const Center(child: Text("Spreadsheet is empty.")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('${widget.sheet.name} - Chart', style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF217346),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: 'Share Chart',
            onPressed: _captureAndShare,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.grey.shade50,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Labels (X-Axis/Slices)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedLabelCol,
                        items: widget.sheet.columns.map((c) {
                          return DropdownMenuItem(value: c.id, child: Text(c.title, overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (val) {
                          setState(() { _selectedLabelCol = val; });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Values (Y-Axis/Sizes)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: _selectedValueCol,
                        items: widget.sheet.columns.map((c) {
                          return DropdownMenuItem(value: c.id, child: Text(c.title, overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (val) {
                          setState(() { _selectedValueCol = val; });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
             color: Colors.white,
             padding: const EdgeInsets.symmetric(vertical: 8.0),
             child: Row(
               mainAxisAlignment: MainAxisAlignment.center,
               children: [
                 ChoiceChip(
                   label: const Text('Pie Chart'),
                   selected: _isPieChart,
                   onSelected: (val) => setState(() => _isPieChart = true),
                   selectedColor: Colors.green.shade100,
                 ),
                 const SizedBox(width: 16),
                 ChoiceChip(
                   label: const Text('Bar Chart'),
                   selected: !_isPieChart,
                   onSelected: (val) => setState(() => _isPieChart = false),
                   selectedColor: Colors.green.shade100,
                 ),
               ],
             ),
          ),
          Expanded(
            child: RepaintBoundary(
              key: _chartKey,
              child: Container(
                color: Colors.white,
                child: Column(
                  children: [
                    if (_isPieChart)
                      Padding(
                         padding: const EdgeInsets.all(8.0),
                         child: _buildLegend(),
                      ),
                    Expanded(
                      child: _buildChart(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
