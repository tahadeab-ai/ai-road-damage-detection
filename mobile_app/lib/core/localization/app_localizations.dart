import 'package:flutter/material.dart';

enum AppLanguage {
  arabic,
  english,
}

/// Reactive language notifier for instantaneous app-wide translation updates.
class AppLanguageNotifier extends ValueNotifier<AppLanguage> {
  AppLanguageNotifier._() : super(AppLanguage.arabic);

  static final AppLanguageNotifier instance = AppLanguageNotifier._();

  void toggleLanguage() {
    value = (value == AppLanguage.arabic) ? AppLanguage.english : AppLanguage.arabic;
  }

  void setLanguage(AppLanguage language) {
    if (value != language) {
      value = language;
    }
  }
}

/// Centralized Arabic & English ADAS Localization.
class AppStrings {
  static AppLanguage get currentLanguage => AppLanguageNotifier.instance.value;
  static set currentLanguage(AppLanguage lang) => AppLanguageNotifier.instance.setLanguage(lang);

  static bool get isArabic => currentLanguage == AppLanguage.arabic;
  static TextDirection get direction => isArabic ? TextDirection.rtl : TextDirection.ltr;

  // Language Toggle Button Label
  static String get languageToggleLabel => isArabic ? 'EN' : 'عربي';

  // Defect Class Names
  static String getDefectName(int classId) {
    if (isArabic) {
      switch (classId) {
        case 0:
          return 'تشقق طولي';
        case 1:
          return 'تشقق عرضي';
        case 2:
          return 'تشقق شبكي';
        case 3:
          return 'حفرة';
        default:
          return 'ضرر طريق';
      }
    } else {
      switch (classId) {
        case 0:
          return 'Longitudinal Crack';
        case 1:
          return 'Transverse Crack';
        case 2:
          return 'Alligator Crack';
        case 3:
          return 'Pothole';
        default:
          return 'Road Hazard';
      }
    }
  }

  // Defect Badge with explicit confidence
  static String getDefectBadge(int classId, double confidence) {
    final name = getDefectName(classId);
    final percent = (confidence * 100).toStringAsFixed(0);
    return '$name $percent%';
  }

  // Top HUD Bar
  static String get standby => isArabic ? 'في وضع الاستعداد' : 'STANDBY';
  static String get standbyTooltip => isArabic ? 'السيارة متوقفة (< 8 كم/س)' : 'Vehicle stationary (< 8 km/h)';
  static String get speedUnit => isArabic ? 'كم/س' : 'KM/H';
  static String get msUnit => isArabic ? 'مللي ثانية' : 'ms';
  static String get fpsUnit => isArabic ? 'إطار/ث' : 'FPS';
  static String get gpsLocked => isArabic ? 'GPS متصل' : 'GPS LOCKED';
  static String get gpsSearching => isArabic ? 'بحث عن GPS...' : 'SEARCHING GPS...';
  static String get muted => isArabic ? 'كتم الصوت' : 'MUTED';

  // Bottom Console
  static String get pauseAi => isArabic ? 'إيقاف مؤقت' : 'PAUSE AI';
  static String get resumeAi => isArabic ? 'استئناف' : 'RESUME AI';
  static String get nightVision => isArabic ? 'الرؤية الليلية' : 'Night Vision';
  static String get incidentLogs => isArabic ? 'سجل أضرار الطريق' : 'Incident Logs';
  static String get diagnostics => isArabic ? 'تشخيص النظام' : 'Diagnostics';

  // Warning Banner
  static String get criticalHazardTitle => isArabic ? 'تحذير: ضرر طريق حرج أمـامـك' : 'CRITICAL ROAD HAZARD DETECTED';
  static String criticalHazardSubtitle(String className, int percent) =>
      isArabic ? '$className أمامك (نسبة التأكيد $percent%)' : '$className Ahead ($percent% Conf)';

  // Incident History Screen
  static String get historyTitle => isArabic ? 'سجل أضرار الطريق' : 'INCIDENT TELEMETRY LOGS';
  static String get filterAll => isArabic ? 'الكل' : 'ALL';
  static String get filterPothole => isArabic ? 'حفر' : 'POTHOLES';
  static String get filterAlligator => isArabic ? 'تشققات شبكية' : 'ALLIGATOR';
  static String get filterLongitudinal => isArabic ? 'تشققات طولية' : 'LONGITUDINAL';
  static String get filterTransverse => isArabic ? 'تشققات عرضية' : 'TRANSVERSE';
  static String get noHazardsTitle => isArabic ? 'لا توجد أضرار مسجلة بعد' : 'NO HAZARDS LOGGED YET';
  static String get noHazardsSubtitle => isArabic
      ? 'ستظهر هنا أضرار الطريق المكتشفة مع لقطات الإثبات تلقائياً'
      : 'Verified road damage incidents with snapshot evidence will appear here';

  // Export & Actions
  static String get exportGeoJson => isArabic ? 'تصدير بصيغة GeoJSON' : 'Export as GeoJSON';
  static String get exportCsv => isArabic ? 'تصدير بصيغة CSV' : 'Export as CSV';
  static String get clearAllLogs => isArabic ? 'مسح جميع السجلات' : 'Clear All Logs';
  static String get clearConfirmTitle => isArabic ? 'مسح جميع السجلات؟' : 'Clear All Logs?';
  static String get clearConfirmBody => isArabic
      ? 'سيؤدي هذا إلى حذف جميع سجلات أضرار الطريق وصور الإثبات المخزنة في جهازك بشكل دائم.'
      : 'This will permanently delete all logged road hazards and evidence snapshots from device storage.';
  static String get cancel => isArabic ? 'إلغاء' : 'CANCEL';
  static String get confirmClear => isArabic ? 'مسح الآن' : 'CLEAR ALL';

  // Evidence Viewer
  static String get evidenceViewerTitle => isArabic ? 'معاينة إثبات الضرر' : 'Hazard Evidence Preview';
  static String get coordinates => isArabic ? 'الإحداثيات' : 'Coordinates';
  static String get speed => isArabic ? 'السرعة' : 'Speed';
  static String get recordedAt => isArabic ? 'وقت التسجيل' : 'Recorded At';
  static String get confidence => isArabic ? 'نسبة التأكيد' : 'Confidence';
  static String get noSnapshot => isArabic ? 'لا توجد صورة إثبات' : 'No snapshot evidence';

  // Permission Guard Strings
  static String get permissionTitle => isArabic ? 'صلاحيات الكاميرا والموقع مطلوبة' : 'Camera & Location Required';
  static String get permissionSubtitle => isArabic
      ? 'يعتمد نظام RoadGuard AI على بث الكاميرا وتتبع GPS لرصد وتوثيق أضرار الطريق بدقة بالغة.'
      : 'RoadGuard AI requires direct camera feed and GPS telemetry to accurately detect and log road hazards.';
  static String get grantPermissions => isArabic ? 'منح الصلاحيات وبدء الرصد' : 'Grant Permissions & Start';
  static String get openSettings => isArabic ? 'فتح إعدادات الجهاز' : 'Open System Settings';
}
