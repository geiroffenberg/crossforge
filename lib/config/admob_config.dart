import 'package:flutter/foundation.dart';

class AdMobConfig {
  static const bool _useTestAds = !kReleaseMode;

  // Test IDs (used in debug/profile builds)
  static const String _androidTestInterstitial =
      'ca-app-pub-3940256099942544/1033173712';

  // Production IDs
  static const String _androidProdInterstitial =
      'ca-app-pub-9327215418607539/9975055371';

  static String get interstitialAdUnitId {
    if (kIsWeb) return '';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _useTestAds ? _androidTestInterstitial : _androidProdInterstitial;
      default:
        return '';
    }
  }
}
