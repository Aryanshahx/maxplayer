import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Flutter does not provide Pashto Material/Cupertino strings. App UI uses
// ps.json; framework-owned date pickers/dialog labels fall back to English.
class PashtoMaterialFallback
    extends LocalizationsDelegate<MaterialLocalizations> {
  const PashtoMaterialFallback();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ps';
  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(PashtoMaterialFallback old) => false;
}

class PashtoCupertinoFallback
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const PashtoCupertinoFallback();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ps';
  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));
  @override
  bool shouldReload(PashtoCupertinoFallback old) => false;
}

class PashtoWidgetsLocalization extends DefaultWidgetsLocalizations {
  const PashtoWidgetsLocalization();
  @override
  TextDirection get textDirection => TextDirection.rtl;
}

class PashtoWidgetsLocalizationDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const PashtoWidgetsLocalizationDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ps';
  @override
  Future<WidgetsLocalizations> load(Locale locale) async =>
      const PashtoWidgetsLocalization();
  @override
  bool shouldReload(PashtoWidgetsLocalizationDelegate old) => false;
}
