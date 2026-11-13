import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiLanguage {
  final String code, nativeName;
  const UiLanguage(this.code, this.nativeName);
}

const uiLanguages = <UiLanguage>[
  UiLanguage('en', 'English'),
  UiLanguage('hi', 'हिन्दी'),
  UiLanguage('bn', 'বাংলা'),
  UiLanguage('te', 'తెలుగు'),
  UiLanguage('mr', 'मराठी'),
  UiLanguage('ta', 'தமிழ்'),
  UiLanguage('ur', 'اردو'),
  UiLanguage('gu', 'ગુજરાતી'),
  UiLanguage('kn', 'ಕನ್ನಡ'),
  UiLanguage('ml', 'മലയാളം'),
  UiLanguage('pa', 'ਪੰਜਾਬੀ'),
  UiLanguage('or', 'ଓଡ଼ିଆ'),
  UiLanguage('as', 'অসমীয়া'),
  UiLanguage('ne', 'नेपाली'),
  UiLanguage('si', 'සිංහල'),
  UiLanguage('ar', 'العربية'),
  UiLanguage('fa', 'فارسی'),
  UiLanguage('he', 'עברית'),
  UiLanguage('tr', 'Türkçe'),
  UiLanguage('ru', 'Русский'),
  UiLanguage('uk', 'Українська'),
  UiLanguage('de', 'Deutsch'),
  UiLanguage('fr', 'Français'),
  UiLanguage('es', 'Español'),
  UiLanguage('pt', 'Português'),
  UiLanguage('it', 'Italiano'),
  UiLanguage('nl', 'Nederlands'),
  UiLanguage('pl', 'Polski'),
  UiLanguage('ro', 'Română'),
  UiLanguage('el', 'Ελληνικά'),
  UiLanguage('id', 'Bahasa Indonesia'),
  UiLanguage('ms', 'Bahasa Melayu'),
  UiLanguage('vi', 'Tiếng Việt'),
  UiLanguage('th', 'ไทย'),
  UiLanguage('ko', '한국어'),
  UiLanguage('ja', '日本語'),
  UiLanguage('zh', '简体中文'),
  UiLanguage('sw', 'Kiswahili'),
  UiLanguage('cs', 'Čeština'),
  UiLanguage('hu', 'Magyar'),
];

class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final instance = AppLanguage._();
  static const preferenceKey = 'ui.language.v1';
  final Map<String, Map<String, String>> _catalogs = {};
  String code = 'system';
  static bool supports(String code) => uiLanguages.any((l) => l.code == code);
  String get effectiveCode {
    if (supports(code)) return code;
    for (final locale in PlatformDispatcher.instance.locales) {
      if (supports(locale.languageCode)) return locale.languageCode;
    }
    return 'en';
  }

  // Resolve system ourselves so platform changes can refresh the bundled catalog.
  Locale get locale => Locale(effectiveCode);
  Future<void> _loadCatalog(String language) async {
    if (_catalogs.containsKey(language)) return;
    final raw =
        jsonDecode(await rootBundle.loadString('assets/i18n/$language.json'))
            as Map;
    _catalogs[language] = Map<String, String>.from(raw);
  }

  Future<void> load() async {
    final saved = (await SharedPreferences.getInstance()).getString(
      preferenceKey,
    );
    code = saved == 'system' || (saved != null && supports(saved))
        ? saved!
        : 'system';
    try {
      await _loadCatalog(effectiveCode);
    } catch (_) {
      /* English fallback */
    }
    notifyListeners();
  }

  Future<void> refreshSystem() async {
    if (code != 'system') return;
    try {
      await _loadCatalog(effectiveCode);
    } catch (_) {
      /* English fallback */
    }
    notifyListeners();
  }

  Future<void> setLanguage(String next) async {
    if (next != 'system' && !supports(next)) {
      throw ArgumentError('Unsupported UI language');
    }
    final previous = code;
    code = next;
    try {
      await _loadCatalog(effectiveCode);
      await (await SharedPreferences.getInstance()).setString(
        preferenceKey,
        next,
      );
    } catch (_) {
      code = previous;
      rethrow;
    }
    notifyListeners();
  }

  String text(String value, [String? language]) =>
      _catalogs[language ?? effectiveCode]?[value] ?? value;
}

/// Only fixed UI text is wrapped. Media/user/server strings retain normal Text.
class LText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;
  const LText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  });
  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return Text(
      AppLanguage.instance.text(data, language),
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}

/// Immutable decoration retains const call sites; TextField rebuilds on locale.
class LInputDecoration extends InputDecoration {
  const LInputDecoration({
    super.hintText,
    super.labelText,
    super.helperText,
    super.errorText,
    super.hintStyle,
    super.labelStyle,
    super.helperStyle,
    super.errorStyle,
    super.border,
    super.enabledBorder,
    super.focusedBorder,
    super.errorBorder,
    super.disabledBorder,
    super.focusedErrorBorder,
    super.isDense,
    super.filled,
    super.fillColor,
    super.contentPadding,
    super.prefixIcon,
    super.suffixIcon,
    super.icon,
    super.counterText,
    super.enabled,
    super.suffixIconConstraints,
    super.prefixIconConstraints,
  });
  @override
  String? get hintText => super.hintText == null
      ? null
      : AppLanguage.instance.text(super.hintText!);
  @override
  String? get labelText => super.labelText == null
      ? null
      : AppLanguage.instance.text(super.labelText!);
  @override
  String? get helperText => super.helperText == null
      ? null
      : AppLanguage.instance.text(super.helperText!);
  @override
  String? get errorText => super.errorText == null
      ? null
      : AppLanguage.instance.text(super.errorText!);
}
