import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
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
  int _selectedClassFilter = -1; // -1 for ALL
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
    if (_selectedClassFilter == -1) return _hazards;
    return _hazards.where((h) => h.classId == _selectedClassFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: AppLanguageNotifier.instance,
      builder: (context, lang, child) {
        return Directionality(
          textDirection: AppStrings.direction,
          child: Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: Text(AppStrings.historyTitle),
              actions: [
                // Quick Language Switcher
                IconButton(
                  tooltip: 'AR / EN',
                  icon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.cyanAccent, width: 1.0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      AppStrings.languageToggleLabel,
                      style: const TextStyle(
                        color: AppColors.cyanAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  onPressed: () => AppLanguageNotifier.instance.toggleLanguage(),
                ),
                PopupMenuButton<String>(
              icon: const Icon(Icons.ios_share_rounded),
              tooltip: 'Export Dataset',
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
                PopupMenuItem(
                  value: 'geojson',
                  child: Row(
                    children: [
                      const Icon(Icons.map_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(AppStrings.exportGeoJson),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'csv',
                  child: Row(
                    children: [
                      const Icon(Icons.table_chart_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(AppStrings.exportCsv),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                      const SizedBox(width: 8),
                      Text(AppStrings.clearAllLogs, style: const TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // Localized Filter Chips Bar
            _buildFilterBar(),

            // List of Incident Cards
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
      ),
    );
      },
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      {'id': -1, 'label': AppStrings.filterAll},
      {'id': 3, 'label': AppStrings.filterPothole},
      {'id': 2, 'label': AppStrings.filterAlligator},
      {'id': 0, 'label': AppStrings.filterLongitudinal},
      {'id': 1, 'label': AppStrings.filterTransverse},
    ];

    return Container(
      height: 48,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = filters[index];
          final filterId = item['id'] as int;
          final isSelected = _selectedClassFilter == filterId;

          return ChoiceChip(
            label: Text(
              item['label'] as String,
              style: TextStyle(
                color: isSelected ? Colors.black : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            selected: isSelected,
            selectedColor: AppColors.cyanAccent,
            backgroundColor: AppColors.surface,
            onSelected: (_) => setState(() => _selectedClassFilter = filterId),
          );
        },
      ),
    );
  }

  Widget _buildHazardCard(RoadHazard hazard) {
    final Color defectColor = AppColors.getColorForDefect(hazard.classId);
    final String formattedDate = DateFormat('yyyy-MM-dd • HH:mm:ss').format(hazard.timestamp);
    final String defectName = AppStrings.getDefectName(hazard.classId);
    final String percentText = '${(hazard.confidence * 100).toStringAsFixed(0)}%';

    final bool hasSnapshot = hazard.snapshotPath != null &&
        hazard.snapshotPath!.isNotEmpty &&
        File(hazard.snapshotPath!).existsSync();

    return InkWell(
      onTap: () => _openEvidenceViewer(hazard),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Categorical Color Strip
                Container(
                  width: 6,
                  color: defectColor,
                ),

                // 70x70 Snapshot Thumbnail Preview
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 70,
                      height: 70,
                      color: Colors.black26,
                      child: hasSnapshot
                          ? Image.file(
                              File(hazard.snapshotPath!),
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: AppColors.surfaceGlass,
                              child: Center(
                                child: Icon(
                                  Icons.camera_alt_outlined,
                                  size: 26,
                                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),

                // Incident Details
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Defect Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: defectColor.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: defectColor, width: 1),
                              ),
                              child: Text(
                                defectName,
                                style: TextStyle(
                                  color: defectColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            // Confidence Percentage
                            Text(
                              percentText,
                              style: const TextStyle(
                                color: AppColors.cyanAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Road Address
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 15, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                hazard.address,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // Telemetry: Coordinates & Speed
                        Row(
                          children: [
                            const Icon(Icons.navigation_outlined, size: 13, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              hazard.latitude != null && hazard.longitude != null
                                  ? '${hazard.latitude!.toStringAsFixed(4)}, ${hazard.longitude!.toStringAsFixed(4)}'
                                  : (hazard.roadYMeters != null
                                      ? 'Road Y: ${hazard.roadYMeters!.toStringAsFixed(1)}m (GPS Null)'
                                      : 'Offline (GPS Null)'),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontFamily: 'monospace'),
                            ),
                            const Spacer(),
                            const Icon(Icons.speed_rounded, size: 13, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              '${hazard.speedKmh.toStringAsFixed(0)} ${AppStrings.speedUnit}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedDate,
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEvidenceViewer(RoadHazard hazard) {
    final bool hasSnapshot = hazard.snapshotPath != null &&
        hazard.snapshotPath!.isNotEmpty &&
        File(hazard.snapshotPath!).existsSync();

    final Color defectColor = AppColors.getColorForDefect(hazard.classId);
    final String defectName = AppStrings.getDefectName(hazard.classId);
    final String percentText = '${(hazard.confidence * 100).toStringAsFixed(0)}%';
    final String formattedDate = DateFormat('yyyy-MM-dd • HH:mm:ss').format(hazard.timestamp);

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Directionality(
          textDirection: AppStrings.direction,
          child: Dialog(
            backgroundColor: AppColors.surface,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Modal Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: defectColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppStrings.evidenceViewerTitle,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Interactive Zoom/Pan Evidence Frame
                Container(
                  height: 340,
                  color: Colors.black,
                  child: hasSnapshot
                      ? ClipRect(
                          child: InteractiveViewer(
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.file(
                                File(hazard.snapshotPath!),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image_outlined, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                              const SizedBox(height: 12),
                              Text(
                                AppStrings.noSnapshot,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                ),

                // Telemetry Metadata Overlay Cards
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: defectColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: defectColor, width: 1.2),
                            ),
                            child: Text(
                              defectName,
                              style: TextStyle(color: defectColor, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ),
                          Text(
                            '${AppStrings.confidence}: $percentText',
                            style: const TextStyle(
                              color: AppColors.cyanAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildDetailRow(Icons.location_on_outlined, hazard.address),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        Icons.navigation_outlined,
                        hazard.latitude != null && hazard.longitude != null
                            ? '${AppStrings.coordinates}: ${hazard.latitude!.toStringAsFixed(5)}, ${hazard.longitude!.toStringAsFixed(5)}'
                            : (hazard.roadYMeters != null
                                ? '${AppStrings.coordinates}: Road-Plane (X: ${hazard.roadXMeters?.toStringAsFixed(1) ?? "0.0"}m, Y: ${hazard.roadYMeters!.toStringAsFixed(1)}m) [GPS Null]'
                                : '${AppStrings.coordinates}: Offline (GPS Null)'),
                      ),
                      const SizedBox(height: 8),
                      _buildDetailRow(
                        Icons.speed_rounded,
                        '${AppStrings.speed}: ${hazard.speedKmh.toStringAsFixed(0)} ${AppStrings.speedUnit}  •  $formattedDate',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            AppStrings.noHazardsTitle,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.0),
          ),
          const SizedBox(height: 6),
          Text(
            AppStrings.noHazardsSubtitle,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: AppStrings.direction,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(AppStrings.clearConfirmTitle),
          content: Text(AppStrings.clearConfirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppStrings.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppStrings.confirmClear),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _repository.clearAll();
      await _loadHazards();
    }
  }
}
