import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/colors.dart';
import '../../../detection/domain/models/road_hazard.dart';
import '../../data/repositories/hazard_repository.dart';

class HazardLogScreen extends StatefulWidget {
  const HazardLogScreen({super.key});

  @override
  State<HazardLogScreen> createState() => _HazardLogScreenState();
}

class _HazardLogScreenState extends State<HazardLogScreen> {
  final HazardRepository _repository = HazardRepository();
  List<RoadHazard> _hazards = [];
  String _selectedFilter = 'ALL';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHazards();
  }

  Future<void> _loadHazards() async {
    setState(() => _isLoading = true);
    await _repository.initialize();
    final all = _repository.getAllHazards();
    setState(() {
      _hazards = all;
      _isLoading = false;
    });
  }

  List<RoadHazard> get _filteredHazards {
    if (_selectedFilter == 'ALL') return _hazards;
    return _hazards.where((h) => h.defectClass.toUpperCase().contains(_selectedFilter)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('INCIDENT TELEMETRY LOGS'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Export GIS Dataset',
            onSelected: (value) async {
              if (value == 'geojson') {
                final geojson = _repository.exportToGeoJson();
                await Share.share(geojson, subject: 'RoadGuard_Hazards_GeoJSON.json');
              } else if (value == 'csv') {
                final csv = _repository.exportToCsv();
                await Share.share(csv, subject: 'RoadGuard_Hazards_Log.csv');
              } else if (value == 'clear') {
                await _confirmClearAll();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'geojson',
                child: Row(
                  children: [
                    Icon(Icons.map_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Export as GeoJSON'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Export as CSV'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                    SizedBox(width: 8),
                    Text('Clear All Logs', style: TextStyle(color: AppColors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          _buildFilterBar(),

          // List of Hazard Cards
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredHazards.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filteredHazards.length,
                        itemBuilder: (context, index) {
                          return _buildHazardCard(_filteredHazards[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = ['ALL', 'POTHOLE', 'ALLIGATOR', 'LONGITUDINAL', 'TRANSVERSE'];
    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter;
          return ChoiceChip(
            label: Text(
              filter,
              style: TextStyle(
                color: isSelected ? Colors.black : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            selected: isSelected,
            selectedColor: AppColors.cyanAccent,
            backgroundColor: AppColors.surface,
            onSelected: (_) => setState(() => _selectedFilter = filter),
          );
        },
      ),
    );
  }

  Widget _buildHazardCard(RoadHazard hazard) {
    final Color defectColor = AppColors.getColorForDefect(hazard.classId);
    final String formattedDate = DateFormat('yyyy-MM-dd • HH:mm:ss').format(hazard.timestamp);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Defect Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: defectColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: defectColor, width: 1),
                  ),
                  child: Text(
                    hazard.defectClass.toUpperCase(),
                    style: TextStyle(
                      color: defectColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                // Confidence Score
                Text(
                  '${(hazard.confidence * 100).toStringAsFixed(0)}% Conf',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Road Address
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hazard.address,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Telemetry: Coordinates, Speed & Timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${hazard.latitude.toStringAsFixed(5)}, ${hazard.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '${hazard.speedKmh.toStringAsFixed(0)} KM/H',
                  style: const TextStyle(
                    color: AppColors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Text(
              formattedDate,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'NO ANOMALIES RECORDED',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Road defects identified in driving mode will be geotagged here',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear All Incident Logs?'),
        content: const Text('This will permanently delete all stored road hazards and telemetry data from your device.'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete All'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _repository.clearAll();
      _loadHazards();
    }
  }
}
