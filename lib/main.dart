import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'; // YENİ: Apple Giriş Desteği
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

// VERİ VE ALARM DOSYALARI IMPORT
import 'teams_data.dart';
import 'languages.dart';
import 'languages2.dart';
import 'alarm.dart';

// ==========================================
// REKLAM VE ABONELİK (PREMIUM) SERVİSİ
// ==========================================
class AdAndPaymentService {
  static final InAppPurchase _iap = InAppPurchase.instance;
  static bool isUserPremium = false;
  static bool _interstitialShown = false;
  static StreamSubscription<List<PurchaseDetails>>? _subscription;

  static const String monthlySubscriptionId = 'football_alarm_monthly_premium';
  static const String bannerAdUnitId = 'ca-app-pub-7536978517031948/7878458464';
  static const String interstitialAdUnitId = 'ca-app-pub-7536978517031948/9395446466';

  static Future<void> initAds() async {
    await MobileAds.instance.initialize();
  }

  static void listenToPurchaseUpdated(BuildContext context, Function(bool) onStatusChanged) {
    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _handlePurchaseUpdates(purchaseDetailsList, onStatusChanged);
    }, onDone: () {
      _subscription?.cancel();
    }, onError: (error) {
      debugPrint("IAP Stream Error: $error");
    });
  }

  static void stopListening() {
    _subscription?.cancel();
  }

  static Future<void> _handlePurchaseUpdates(
      List<PurchaseDetails> purchaseDetailsList, Function(bool) onStatusChanged) async {
    for (var purchase in purchaseDetailsList) {
      if (purchase.status == PurchaseStatus.pending) {
        debugPrint("Purchase Pending...");
      } else if (purchase.status == PurchaseStatus.error) {
        debugPrint("Purchase Error: ${purchase.error}");
      } else if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
        bool deliver = await _verifyPurchase(purchase);
        if (deliver) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          isUserPremium = true;
          onStatusChanged(true);
          debugPrint("Purchase Successful: User is now Premium");
        }
      } else if (purchase.status == PurchaseStatus.canceled) {
        debugPrint("Purchase Canceled by User");
      }
    }
  }

  static Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    return true;
  }

  static Future<void> buyUpgrade() async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      debugPrint("Store not available");
      return;
    }

    const Set<String> _kIds = <String>{monthlySubscriptionId};
    final ProductDetailsResponse response = await _iap.queryProductDetails(_kIds);

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint("Product ID not found: ${response.notFoundIDs}");
      return;
    }

    if (response.productDetails.isEmpty) {
      debugPrint("No product details returned from store");
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);

    try {
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint("Error starting purchase: $e");
    }
  }

  static Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e) {
      debugPrint("Restore Error: $e");
    }
  }
}

// ==========================================
// ANA UYGULAMA DÖNGÜSÜ
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
    await Firebase.initializeApp();
    Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await NotificationService().init();
    await AdAndPaymentService.initAds();
  } catch (e) {
    debugPrint("Initialization Error: $e");
  }
  runApp(const FootballAlarmApp());
}

class FootballAlarmApp extends StatelessWidget {
  const FootballAlarmApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const AppLocalization(),
    );
  }
}

class AppLocalization extends StatefulWidget {
  const AppLocalization({super.key});
  @override
  State<AppLocalization> createState() => _AppLocalizationState();
}

class _AppLocalizationState extends State<AppLocalization> {
  String _currentLanguageCode = 'tr';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedLang = prefs.getString('app_language');

    if (savedLang == null) {
      String systemLocale = Platform.localeName.split('_')[0];
      List<String> supportedLanguages = [
        'tr', 'en', 'zh', 'hi', 'es', 'fr', 'ar', 'bn', 'pt', 'ru', 'id', 'de', 'ja', 'ko', 'it', 'nl'
      ];

      if (supportedLanguages.contains(systemLocale)) {
        savedLang = systemLocale;
      } else {
        savedLang = 'en';
      }
      await prefs.setString('app_language', savedLang);
    }

    setState(() {
      _currentLanguageCode = savedLang!;
    });
  }

  void _changeLanguage(String newCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', newCode);
    setState(() => _currentLanguageCode = newCode);
  }

  @override
  Widget build(BuildContext context) {
    return MainShell(
        currentLanguageCode: _currentLanguageCode, onLanguageChange: _changeLanguage);
  }
}

// ==========================================
// TASARIM YARDIMCILARI
// ==========================================
class DeviceSize {
  static double getWidth(BuildContext context) => MediaQuery.of(context).size.width;
  static double getHeight(BuildContext context) => MediaQuery.of(context).size.height;
  static bool isTablet(BuildContext context) => getWidth(context) >= 600;
  static bool isLargeTablet(BuildContext context) => getWidth(context) >= 900;

  static double responsiveWidth(BuildContext context, double p, double t, double lt) {
    if (isLargeTablet(context)) return lt;
    if (isTablet(context)) return t;
    return p;
  }
}

// ==========================================
// MODERN ÇIKIŞ BUTONU
// ==========================================
class ModernExitButton extends StatelessWidget {
  final String Function(String) tr;
  final double? bottomPadding;
  const ModernExitButton({super.key, required this.tr, this.bottomPadding});

  @override
  Widget build(BuildContext context) {
    final double bWidth = DeviceSize.responsiveWidth(context, 70, 100, 130);
    final double bHeight = DeviceSize.responsiveWidth(context, 27.5, 40, 50);

    return Positioned(
      bottom: bottomPadding ?? DeviceSize.responsiveWidth(context, 25, 40, 50),
      right: DeviceSize.responsiveWidth(context, 25, 40, 50),
      child: GestureDetector(
        onTap: () => SystemNavigator.pop(),
        child: SizedBox(
          width: bWidth,
          height: bHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/splash/btn_exit.png',
                width: bWidth,
                height: bHeight,
                fit: BoxFit.fill,
                errorBuilder: (c, e, s) => Container(
                  decoration: BoxDecoration(
                    color: Colors.red.shade900,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bWidth * 0.8),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        tr('exit').toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: DeviceSize.responsiveWidth(context, 11, 15, 18),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ÖZEL GÖRSEL BUTON (RESPONSIVE)
// ==========================================
class CustomImageButton extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  const CustomImageButton({super.key, required this.text, this.onTap, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final double maxWidth = DeviceSize.responsiveWidth(context, 180, 280, 350);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: GestureDetector(
          onTap: (isLoading || onTap == null) ? null : onTap,
          child: AspectRatio(
            aspectRatio: 3.73,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  'assets/splash/test_button.png',
                  width: double.infinity,
                  fit: BoxFit.fill,
                  errorBuilder: (c, e, s) => Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        text.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: DeviceSize.responsiveWidth(context, 22, 28, 34),
                          fontWeight: FontWeight.bold,
                        ),
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
}

// ==========================================
// ANA YÖNETİCİ KABUK (SHELL)
// ==========================================
class MainShell extends StatefulWidget {
  final String currentLanguageCode;
  final void Function(String) onLanguageChange;
  const MainShell({super.key, required this.currentLanguageCode, required this.onLanguageChange});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int currentIndex = 0;
  bool isRegisterPage = false;
  String country = '';
  String team = '';

  List<FootballAlarm> alarmList = [];
  List<FootballAlarm> historyList = [];
  FootballAlarm? currentPendingAlarm;

  User? currentUser;
  bool isSoundEnabled = true;

  Key resultKey = UniqueKey();
  Key upgradeKey = UniqueKey();
  Key tenMatchKey = UniqueKey();

  bool _showAdBanner = false;
  Timer? _adCycleTimer;
  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;

  // GÜNCELLEME: GoogleSignIn nesnesi sınıf düzeyine taşındı
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String tr(String key) => AppTranslations.getTranslation(key, widget.currentLanguageCode);
  String tr2(String key) => AppTranslations2.getTranslation(key, widget.currentLanguageCode);

  @override
  void initState() {
    super.initState();
    _checkInitialUser();

    AdAndPaymentService.listenToPurchaseUpdated(context, (isPremium) {
      _updatePremiumStatusLocally(isPremium);
    });

    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && !AdAndPaymentService._interstitialShown) {
        _loadInterstitialAdAndShow();
      }
    });

    _startAdCycle();
    _initAppSequence();
  }

  Future<void> _initAppSequence() async {
    await NotificationService().requestNotificationPermissions();
  }

  void _updatePremiumStatusLocally(bool isPremium) async {
    if (currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('premium_${currentUser!.uid}', isPremium);

    await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).set({
      'isPremium': isPremium,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (mounted) {
      setState(() {
        AdAndPaymentService.isUserPremium = isPremium;
        if (isPremium) _showAdBanner = false;
        upgradeKey = UniqueKey();
      });
    }
  }

  void _startAdCycle() {
    if (AdAndPaymentService.isUserPremium) return;

    _adCycleTimer = Timer.periodic(const Duration(seconds: 45), (timer) {
      if (!mounted) return;
      if (AdAndPaymentService.isUserPremium) {
        timer.cancel();
        return;
      }
      _loadBannerAd();
      setState(() => _showAdBanner = true);

      Future.delayed(const Duration(seconds: 15), () {
        if (!mounted) return;
        setState(() {
          _showAdBanner = false;
          _bannerAd?.dispose();
          _bannerAd = null;
        });
      });
    });
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdAndPaymentService.bannerAdUnitId,
      size: AdSize.largeBanner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  void _loadInterstitialAdAndShow() {
    if (AdAndPaymentService._interstitialShown || AdAndPaymentService.isUserPremium) return;

    InterstitialAd.load(
      adUnitId: AdAndPaymentService.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _showInterstitial();
        },
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  void _showInterstitial() {
    if (AdAndPaymentService.isUserPremium || AdAndPaymentService._interstitialShown) return;

    if (_interstitialAd != null) {
      _interstitialAd!.show();
      AdAndPaymentService._interstitialShown = true;
      _interstitialAd = null;
    }
  }

  @override
  void dispose() {
    AdAndPaymentService.stopListening();
    _adCycleTimer?.cancel();
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  Future<void> _checkInitialUser() async {
    final prefs = await SharedPreferences.getInstance();
    currentUser = FirebaseAuth.instance.currentUser;
    isSoundEnabled = prefs.getBool('notif_sound_enabled') ?? true;

    if (currentUser != null) {
      String uid = currentUser!.uid;

      String? alarmlarJson = prefs.getString('alarmlar_$uid');
      String? gecmisJson = prefs.getString('gecmis_alarmlar_$uid');

      if (alarmlarJson != null) {
        Iterable l = json.decode(alarmlarJson);
        alarmList = List<FootballAlarm>.from(l.map((model) => FootballAlarm.fromJson(model)));
      }
      if (gecmisJson != null) {
        Iterable g = json.decode(gecmisJson);
        historyList = List<FootballAlarm>.from(g.map((model) => FootballAlarm.fromJson(model)));
      }

      AdAndPaymentService.isUserPremium = prefs.getBool('premium_$uid') ?? false;

      await _syncWithCloud(uid);

      if (mounted) {
        setState(() {
          _filterPastAlarms();
          currentIndex = alarmList.isNotEmpty ? 5 : 6;
        });
      }
      _reScheduleAllNotifications();
    } else {
      if (mounted) setState(() => currentIndex = 0);
    }
  }

  Future<void> _syncWithCloud(String uid) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        setState(() {
          if (data.containsKey('isPremium')) {
            AdAndPaymentService.isUserPremium = data['isPremium'];
          }
          if (data.containsKey('alarms')) {
            List<dynamic> cloudAlarms = data['alarms'];
            alarmList = cloudAlarms.map((e) => FootballAlarm.fromJson(e)).toList();
          }
          if (data.containsKey('history')) {
            List<dynamic> cloudHistory = data['history'];
            historyList = cloudHistory.map((e) => FootballAlarm.fromJson(e)).toList();
          }
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('premium_$uid', AdAndPaymentService.isUserPremium);
        await _saveAlarmsToPrefs(onlyLocal: true);
        await _saveHistoryToPrefs(onlyLocal: true);
      }
    } catch (e) {
      debugPrint("Cloud Sync Error: $e");
    }
  }

  void _filterPastAlarms() async {
    DateTime now = DateTime.now();
    List<FootballAlarm> toRemove = [];

    for (var alarm in alarmList) {
      try {
        List<String> dateTimeParts = alarm.date.split(' ');
        List<String> dateParts = dateTimeParts[0].split('.');
        List<String> timeParts = dateTimeParts[1].split(':');
        DateTime matchTime = DateTime(
            int.parse(dateParts[2]),
            int.parse(dateParts[1]),
            int.parse(dateParts[0]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]));

        if (matchTime.add(const Duration(hours: 4)).isBefore(now)) {
          String scoreResult = await MatchResultService.getMatchScore(alarm.id);
          if (scoreResult.isNotEmpty) alarm.score = scoreResult;
          toRemove.add(alarm);
        }
      } catch (e) {
        debugPrint("Parse error in filtering: $e");
      }
    }

    if (toRemove.isNotEmpty) {
      setState(() {
        for (var item in toRemove) {
          alarmList.removeWhere((e) => e.id == item.id);
          historyList.insert(0, item);
        }
      });
      _saveAlarmsToPrefs();
      _saveHistoryToPrefs();
    }
  }

  Future<void> _saveAlarmsToPrefs({bool onlyLocal = false}) async {
    if (currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> alarmMaps = alarmList.map((e) => e.toJson()).toList();
    String encoded = json.encode(alarmMaps);
    await prefs.setString('alarmlar_${currentUser!.uid}', encoded);

    if (!onlyLocal) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).set({
        'alarms': alarmMaps,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _saveHistoryToPrefs({bool onlyLocal = false}) async {
    if (currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> historyMaps = historyList.map((e) => e.toJson()).toList();
    String encoded = json.encode(historyMaps);
    await prefs.setString('gecmis_alarmlar_${currentUser!.uid}', encoded);

    if (!onlyLocal) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).set({
        'history': historyMaps,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _reScheduleAllNotifications() async {
    await NotificationService().cancelAllNotifications();
    String currentLang = widget.currentLanguageCode;
    String title = AppTranslations.getTranslation('main_title', currentLang);
    String willStart = AppTranslations.getTranslation('will_start', currentLang);
    String msg3d = AppTranslations.getTranslation('notif_3days', currentLang);
    String msg24h = AppTranslations.getTranslation('notif_24hours', currentLang);
    String msgStart = AppTranslations.getTranslation('notif_starts', currentLang);
    String msgFinished = AppTranslations.getTranslation('match_finished_msg', currentLang);

    for (var alarm in alarmList) {
      try {
        List<String> dateTimeParts = alarm.date.split(' ');
        List<String> dateParts = dateTimeParts[0].split('.');
        List<String> timeParts = dateTimeParts[1].split(':');
        DateTime matchTime = DateTime(
            int.parse(dateParts[2]),
            int.parse(dateParts[1]),
            int.parse(dateParts[0]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]));

        int baseId = alarm.id.hashCode;
        String matchInfo = alarm.info.replaceAll('\n', ' ');

        if (alarm.b3) {
          DateTime sche = matchTime.subtract(const Duration(days: 3));
          if(sche.isAfter(DateTime.now())) {
            String body3d = "$matchInfo ${alarm.date} $willStart $msg3d";
            await NotificationService()
                .scheduleNotification(id: baseId + 1, title: title, body: body3d, scheduledDate: sche, playSound: isSoundEnabled);
          }
        }
        if (alarm.b24) {
          DateTime sche = matchTime.subtract(const Duration(hours: 24));
          if(sche.isAfter(DateTime.now())) {
            String body24h = "$matchInfo ${alarm.date} $willStart $msg24h";
            await NotificationService()
                .scheduleNotification(id: baseId + 2, title: title, body: body24h, scheduledDate: sche, playSound: isSoundEnabled);
          }
        }
        if (alarm.ms) {
          if(matchTime.isAfter(DateTime.now())) {
            await NotificationService().scheduleNotification(id: baseId + 3, title: title, body: "$matchInfo $msgStart",
                scheduledDate: matchTime, payload: "${alarm.id}|${alarm.info}|${alarm.date}", playSound: isSoundEnabled);
          }
        }

        if (alarm.mr) {
          Duration delay = AdAndPaymentService.isUserPremium
              ? const Duration(minutes: 1)
              : const Duration(hours: 2);

          DateTime sche = matchTime.add(delay);
          if(sche.isAfter(DateTime.now())) {
            String scoreMsg = await MatchResultService.getMatchScore(alarm.id, lang: currentLang);
            if (scoreMsg.isNotEmpty) {
              String finalMsg = "$msgFinished, $scoreMsg";
              await NotificationService()
                  .scheduleNotification(id: baseId + 4, title: title, body: finalMsg, scheduledDate: sche, playSound: isSoundEnabled);
            }
          }
        }
      } catch (e) {
        debugPrint("Alarm Planlama Hatası: $e");
      }
    }
  }

  void goHome() {
    _showInterstitial();
    setState(() {
      resultKey = UniqueKey();
      isRegisterPage = false;
      if (currentUser == null) {
        currentIndex = 0;
      } else {
        currentIndex = alarmList.isNotEmpty ? 5 : 6;
      }
    });
  }

  Future<void> logOff() async {
    await NotificationService().cancelAllNotifications();
    await FirebaseAuth.instance.signOut();
    // GÜNCELLEME: Global instance üzerinden çıkış yapıldı
    await _googleSignIn.signOut();
    setState(() {
      currentUser = null;
      currentIndex = 0;
      isRegisterPage = false;
      alarmList = [];
      historyList = [];
    });
  }

  Future<void> deleteUserAccount() async {
    if (currentUser == null) return;
    try {
      String uid = currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarmlar_$uid');
      await prefs.remove('gecmis_alarmlar_$uid');
      await prefs.remove('premium_$uid');
      await NotificationService().cancelAllNotifications();
      await currentUser!.delete();
      // GÜNCELLEME: Global instance üzerinden çıkış yapıldı
      await _googleSignIn.signOut();
      setState(() {
        currentUser = null;
        currentIndex = 0;
        isRegisterPage = false;
        alarmList = [];
        historyList = [];
      });
    } catch (e) {
      debugPrint("Kullanıcı Silme Hatası: $e");
      logOff();
    }
  }

  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 80),
                const SizedBox(height: 15),
                Text(
                  tr2('delete_confirm_title').toUpperCase(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
                ),
                const SizedBox(height: 15),
                Text(
                  tr2('delete_confirm_body'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr2('no').toUpperCase(), style: const TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        deleteUserAccount();
                      },
                      child: Text(tr2('yes').toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void goToTenMatches(String c, String t) {
    _showInterstitial();
    setState(() {
      country = c;
      team = t;
      tenMatchKey = UniqueKey();
      currentIndex = 7;
    });
  }

  void goToResult(String mId, String mInfo, String dStr) async {
    _showInterstitial();
    currentPendingAlarm = FootballAlarm(
      id: mId,
      info: mInfo,
      date: dStr,
      country: country,
      team: team,
    );
    setState(() {
      resultKey = UniqueKey();
      currentIndex = 2;
    });
  }

  // GOOGLE AUTH MANTIĞI
  Future<void> handleAuth() async {
    try {
      // GÜNCELLEME: GoogleSignIn kullanımı düzeltildi
      await _googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      _postLoginSequence(userCredential.user);
    } catch (e) {
      debugPrint("GOOGLE AUTH ERROR: $e");
    }
  }

  // APPLE AUTH MANTIĞI (YENİ)
  Future<void> handleAppleAuth() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
      final AuthCredential authCredential = oAuthProvider.credential(
        idToken: credential.identityToken,
        accessToken: credential.authorizationCode,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(authCredential);
      _postLoginSequence(userCredential.user);
    } catch (e) {
      debugPrint("APPLE AUTH ERROR: $e");
    }
  }

  void _postLoginSequence(User? user) async {
    if (user != null && mounted) {
      currentUser = user;
      await _syncWithCloud(currentUser!.uid);
      setState(() {
        _filterPastAlarms();
        currentIndex = alarmList.isNotEmpty ? 5 : 6;
      });
      _reScheduleAllNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    String userInitial = (currentUser?.email != null && currentUser!.email!.isNotEmpty)
        ? currentUser!.email![0].toUpperCase()
        : "?";

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(userInitial),
                Expanded(
                  child: IndexedStack(
                    index: currentIndex,
                    children: [
                      isRegisterPage
                          ? RegisterScreen(
                          tr: tr,
                          onGoToLogin: () => setState(() => isRegisterPage = false),
                          onRegisterComplete: handleAuth,
                          onAppleRegister: handleAppleAuth) // Apple eklendi
                          : LoginScreen(
                          tr: tr,
                          onLogin: handleAuth,
                          onAppleLogin: handleAppleAuth, // Apple eklendi
                          onGoToRegister: () => setState(() => isRegisterPage = true)),
                      CountryTeamScreen(tr: tr, onContinue: goToTenMatches),
                      ResultScreen(
                          key: resultKey,
                          tr: tr,
                          country: country,
                          team: team,
                          alarmInfo: currentPendingAlarm?.info ?? "",
                          matchDate: currentPendingAlarm?.date ?? "",
                          onFinished: () {
                            if (currentPendingAlarm != null) {
                              setState(() {
                                alarmList.add(currentPendingAlarm!);
                                if (currentPendingAlarm!.mr) {
                                  try {
                                    List<String> dateTimeParts = currentPendingAlarm!.date.split(' ');
                                    List<String> dateParts = dateTimeParts[0].split('.');
                                    List<String> timeParts = dateTimeParts[1].split(':');
                                    DateTime matchTime = DateTime(
                                        int.parse(dateParts[2]),
                                        int.parse(dateParts[1]),
                                        int.parse(dateParts[0]),
                                        int.parse(timeParts[0]),
                                        int.parse(timeParts[1]));

                                    MatchResultService.scheduleResultCheck(
                                        currentPendingAlarm!.id,
                                        matchTime,
                                        widget.currentLanguageCode,
                                        currentPendingAlarm!.team
                                    );
                                  } catch (e) {
                                    debugPrint("Workmanager schedule error: $e");
                                  }
                                }
                                currentPendingAlarm = null;
                                currentIndex = 5;
                              });
                              _saveAlarmsToPrefs();
                              _reScheduleAllNotifications();
                            }
                          },
                          onSettingsChanged: (b3, b24, ms, mr) {
                            if (currentPendingAlarm != null) {
                              currentPendingAlarm!.b3 = b3;
                              currentPendingAlarm!.b24 = b24;
                              currentPendingAlarm!.ms = ms;
                              currentPendingAlarm!.mr = mr;
                            }
                          }),
                      SettingsScreen(
                          tr: tr,
                          currentUserEmail: currentUser?.email,
                          currentLanguageCode: widget.currentLanguageCode,
                          isSoundEnabled: isSoundEnabled,
                          isPremium: AdAndPaymentService.isUserPremium,
                          onLanguageChange: (newLang) {
                            widget.onLanguageChange(newLang);
                            Future.delayed(const Duration(milliseconds: 300), () {
                              _reScheduleAllNotifications();
                            });
                          },
                          onSoundChange: (val) async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('notif_sound_enabled', val);
                            setState(() => isSoundEnabled = val);
                            _reScheduleAllNotifications();
                          },
                          onLogOff: logOff),
                      UpgradeScreen(
                          key: upgradeKey,
                          tr: tr,
                          onPremiumUpdate: (val) async {
                            _updatePremiumStatusLocally(val);
                          }),
                      SelectedAlarmScreen(
                          tr: tr,
                          alarms: alarmList,
                          onAdd: () {
                            _showInterstitial();
                            setState(() => currentIndex = 1);
                          },
                          onUpgradeRedirect: () => setState(() => currentIndex = 4),
                          onDelete: (alarm) async {
                            setState(() {
                              alarmList.removeWhere((element) => element.id == alarm.id);
                              if (alarmList.isEmpty) currentIndex = 6;
                            });
                            await _saveAlarmsToPrefs();
                            await _reScheduleAllNotifications();
                          }),
                      NoAlarmScreen(
                          tr: tr,
                          onAdd: () {
                            _showInterstitial();
                            setState(() => currentIndex = 1);
                          }),
                      TenMatchesScreen(
                          key: tenMatchKey,
                          tr: tr,
                          country: country,
                          team: team,
                          onMatchSelected: goToResult),
                      AlarmHistoryScreen(
                        tr: tr,
                        historyList: historyList,
                        onClearSelection: (ids) async {
                          setState(() {
                            historyList.removeWhere((e) => ids.contains(e.id));
                          });
                          await _saveHistoryToPrefs();
                        },
                      ),
                    ],
                  ),
                ),
                _buildNavigationArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String userInitial) {
    final double headerHeight = DeviceSize.responsiveWidth(context, 55, 80, 100);

    return Stack(
      alignment: Alignment.center,
      children: [
        Image.asset('assets/splash/title_football_alarm.png',
            width: double.infinity,
            height: headerHeight,
            fit: BoxFit.fill,
            errorBuilder: (c, e, s) => SizedBox(height: headerHeight)),
        Positioned(
          right: 12,
          top: 0,
          bottom: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (AdAndPaymentService.isUserPremium)
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: Text(
                    "PRO",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: DeviceSize.responsiveWidth(context, 18, 22, 26),
                    ),
                  ),
                ),
              currentUser == null
                  ? Image.asset('assets/splash/isim_butonu.png',
                  height: DeviceSize.responsiveWidth(context, 42, 60, 75), fit: BoxFit.contain)
                  : GestureDetector(
                onTapDown: (TapDownDetails details) {
                  showMenu(
                    context: context,
                    color: Colors.white,
                    position: RelativeRect.fromLTRB(
                        details.globalPosition.dx, details.globalPosition.dy, 0, 0),
                    items: [
                      PopupMenuItem(value: 'info', child: Text(tr('menu_settings'))),
                      PopupMenuItem(value: 'history', child: Text(tr('menu_history').toUpperCase())),
                      PopupMenuItem(value: 'logoff', child: Text(tr('menu_logoff'))),
                      PopupMenuItem(value: 'delete', child: Text(tr2('menu_delete_user').toUpperCase(), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                      PopupMenuItem(value: 'exit', child: Text(tr('menu_exit'))),
                    ],
                  ).then((val) {
                    if (val == 'info')
                      setState(() => currentIndex = 3);
                    else if (val == 'history')
                      setState(() => currentIndex = 8);
                    else if (val == 'logoff')
                      logOff();
                    else if (val == 'delete')
                      _showDeleteConfirmDialog();
                    else if (val == 'exit')
                      SystemNavigator.pop();
                  });
                },
                child: Stack(alignment: Alignment.center, children: [
                  Image.asset('assets/splash/isim_butonu.png',
                      height: DeviceSize.responsiveWidth(context, 42, 60, 75), fit: BoxFit.contain),
                  Text(userInitial,
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: DeviceSize.responsiveWidth(context, 18, 24, 28)))
                ]),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationArea() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            height: (_showAdBanner && !AdAndPaymentService.isUserPremium)
                ? DeviceSize.responsiveWidth(context, 150, 180, 200)
                : 0,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              border: (_showAdBanner && !AdAndPaymentService.isUserPremium)
                  ? const Border(top: BorderSide(color: Colors.white12))
                  : null,
            ),
            alignment: Alignment.center,
            child: (_showAdBanner && !AdAndPaymentService.isUserPremium)
                ? (_bannerAd != null
                ? AdWidget(ad: _bannerAd!)
                : Text(tr('ad_loading'), style: const TextStyle(color: Colors.white)))
                : const SizedBox(),
          ),
          Container(
            padding: EdgeInsets.only(
                bottom: DeviceSize.responsiveWidth(context, 25, 35, 45), top: 10),
            height: DeviceSize.responsiveWidth(context, 110, 140, 160),
            decoration: const BoxDecoration(
                color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BottomItem(label: tr('nav_main'), icon: 'assets/splash/btn_home.png', onTap: goHome),
                _BottomItem(
                    label: tr('nav_alarms'),
                    icon: 'assets/splash/btn_alarms.png',
                    onTap: () {
                      _showInterstitial();
                      setState(() => currentIndex = alarmList.isEmpty ? 6 : 5);
                    }),
                _BottomItem(
                    label: tr('nav_settings'),
                    icon: 'assets/splash/btn_settings.png',
                    onTap: () {
                      _showInterstitial();
                      setState(() => currentIndex = 3);
                    }),
                _BottomItem(
                    label: tr('nav_upgrade'),
                    icon: 'assets/splash/btn_upgrade.png',
                    onTap: () {
                      _showInterstitial();
                      setState(() {
                        currentIndex = 4;
                        upgradeKey = UniqueKey();
                      });
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  const _BottomItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: DeviceSize.responsiveWidth(context, 11, 14, 16),
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Image.asset(icon, height: DeviceSize.responsiveWidth(context, 44, 60, 75))
        ]));
  }
}

// ==========================================
// ALARM GEÇMİŞİ EKRANI
// ==========================================
class AlarmHistoryScreen extends StatefulWidget {
  final String Function(String) tr;
  final List<FootballAlarm> historyList;
  final Function(Set<String>) onClearSelection;
  const AlarmHistoryScreen({super.key, required this.tr, required this.historyList, required this.onClearSelection});

  @override
  State<AlarmHistoryScreen> createState() => _AlarmHistoryScreenState();
}

class _AlarmHistoryScreenState extends State<AlarmHistoryScreen> {
  Set<String> selectedHistoryIds = {};

  @override
  Widget build(BuildContext context) {
    final double actionBtnWidth = DeviceSize.responsiveWidth(context, 140, 200, 260);
    final double actionBtnHeight = DeviceSize.responsiveWidth(context, 55, 80, 100);

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        image: DecorationImage(image: AssetImage('assets/splash/cim.png'), fit: BoxFit.fill),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: Column(
              children: [
                Center(
                  child: Text(
                    widget.tr('history_title').toUpperCase(),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: DeviceSize.responsiveWidth(context, 24, 32, 40),
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: widget.historyList.isEmpty
                      ? Center(
                      child: Text(widget.tr('no_history_found'),
                          style: const TextStyle(
                              color: Colors.white70, fontWeight: FontWeight.bold)))
                      : ListView.builder(
                    itemCount: widget.historyList.length,
                    itemBuilder: (context, index) {
                      var alarm = widget.historyList[index];
                      bool isChecked = selectedHistoryIds.contains(alarm.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("${alarm.country} - ${alarm.team}".toUpperCase(),
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: DeviceSize.responsiveWidth(context, 12, 14, 16))),
                                  Text(alarm.info.toUpperCase(),
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: DeviceSize.responsiveWidth(context, 14, 18, 22),
                                          fontWeight: FontWeight.bold)),
                                  if (alarm.score != null && alarm.score!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        "${widget.tr('match_result_prefix')}: ${alarm.score}".toUpperCase(),
                                        style: TextStyle(
                                            color: Colors.greenAccent,
                                            fontWeight: FontWeight.w900,
                                            fontSize:
                                            DeviceSize.responsiveWidth(context, 16, 20, 24)),
                                      ),
                                    ),
                                  Text(alarm.date,
                                      style: TextStyle(
                                          color: Colors.yellow,
                                          fontSize: DeviceSize.responsiveWidth(context, 12, 15, 18),
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            GestureDetector(
                                onTap: () => setState(() {
                                  if (isChecked)
                                    selectedHistoryIds.remove(alarm.id);
                                  else
                                    selectedHistoryIds.add(alarm.id);
                                }),
                                child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                        color: Colors.white, borderRadius: BorderRadius.circular(4)),
                                    child: isChecked
                                        ? const Icon(Icons.check, color: Colors.green, size: 22)
                                        : null))
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
          Positioned(
            bottom: DeviceSize.responsiveWidth(context, 25, 40, 50),
            left: DeviceSize.responsiveWidth(context, 25, 40, 50),
            child: Opacity(
              opacity: selectedHistoryIds.isNotEmpty ? 1.0 : 0.5,
              child: GestureDetector(
                onTap: selectedHistoryIds.isNotEmpty ? () {
                  widget.onClearSelection(selectedHistoryIds);
                  setState(() => selectedHistoryIds.clear());
                } : null,
                child: SizedBox(
                  width: actionBtnWidth,
                  height: actionBtnHeight,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/splash/btn_exit_action.png',
                        width: actionBtnWidth,
                        height: actionBtnHeight,
                        fit: BoxFit.fill,
                      ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.tr('history_clear').toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: DeviceSize.responsiveWidth(context, 18, 24, 30),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ModernExitButton(tr: widget.tr),
        ],
      ),
    );
  }
}

class TenMatchesScreen extends StatefulWidget {
  final String country;
  final String team;
  final String Function(String) tr;
  final void Function(String, String, String) onMatchSelected;
  const TenMatchesScreen(
      {super.key,
        required this.country,
        required this.team,
        required this.tr,
        required this.onMatchSelected});
  @override
  State<TenMatchesScreen> createState() => _TenMatchesScreenState();
}

class _TenMatchesScreenState extends State<TenMatchesScreen> {
  List<dynamic> matches = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchMatches();
  }

  Future<void> _fetchMatches() async {
    final teamId = teamsByCountry[widget.country]?[widget.team];
    final String apiKey = dotenv.env['FOOTBALL_API_KEY'] ?? '';

    try {
      final response = await http.get(
          Uri.parse('https://api.football-data.org/v4/teams/$teamId/matches?status=SCHEDULED'),
          headers: {'X-Auth-Token': apiKey});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List<dynamic> allMatches = data['matches'] ?? [];
        DateTime now = DateTime.now();

        List<dynamic> filteredMatches = allMatches.where((m) {
          DateTime matchDate = DateTime.parse(m['utcDate']).toLocal();
          return matchDate.isAfter(now);
        }).toList();

        if (filteredMatches.length > 40) filteredMatches = filteredMatches.sublist(0, 40);

        if (mounted) {
          setState(() {
            matches = filteredMatches;
            isLoading = false;
            if (matches.isEmpty) errorMessage = widget.tr('api_empty_list');
          });
        }
      } else {
        if (mounted)
          setState(() {
            isLoading = false;
            errorMessage = "${widget.tr('api_error')}: ${response.statusCode}";
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          isLoading = false;
          errorMessage = "${widget.tr('connection_error')}: $e";
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
            image: DecorationImage(image: AssetImage('assets/splash/cim.png'), fit: BoxFit.fill)),
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(children: [
          const SizedBox(height: 20),
          Text(widget.team.toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontSize: DeviceSize.responsiveWidth(context, 24, 32, 40),
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
              child: errorMessage != null
                  ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.yellow,
                        fontSize: DeviceSize.responsiveWidth(context, 18, 22, 26),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ))
                  : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final m = matches[index];
                    final utcDate = DateTime.parse(m['utcDate']).toLocal();
                    final info =
                        "${m['homeTeam']['shortName'] ?? m['homeTeam']['name']} vs ${m['awayTeam']['shortName'] ?? m['awayTeam']['name']}";
                    final dateStr =
                        "${utcDate.day.toString().padLeft(2, '0')}.${utcDate.month.toString().padLeft(2, '0')}.${utcDate.year} ${utcDate.hour.toString().padLeft(2, '0')}:${utcDate.minute.toString().padLeft(2, '0')}";
                    return Container(
                        margin: const EdgeInsets.only(bottom: 15),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(info.toUpperCase(),
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: DeviceSize.responsiveWidth(
                                                context, 14, 18, 20))),
                                    Text(dateStr,
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: DeviceSize.responsiveWidth(
                                                context, 12, 14, 16)))
                                  ])),
                          GestureDetector(
                              onTap: () =>
                                  widget.onMatchSelected(m['id'].toString(), info, dateStr),
                              child: Stack(alignment: Alignment.center, children: [
                                Image.asset('assets/splash/upgrade_button.png',
                                    width: DeviceSize.responsiveWidth(
                                        context, 100, 130, 160),
                                    height:
                                    DeviceSize.responsiveWidth(context, 40, 50, 60),
                                    fit: BoxFit.fill),
                                Text(widget.tr('add_alarm').toUpperCase(),
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: DeviceSize.responsiveWidth(
                                            context, 10, 13, 16),
                                        fontWeight: FontWeight.bold))
                              ]))
                        ]));
                  }))
        ]));
  }
}

class ResultScreen extends StatefulWidget {
  final String country;
  final String team;
  final String alarmInfo;
  final String matchDate;
  final VoidCallback onFinished;
  final String Function(String) tr;
  final Function(bool, bool, bool, bool) onSettingsChanged;
  const ResultScreen(
      {super.key,
        required this.country,
        required this.team,
        required this.alarmInfo,
        required this.matchDate,
        required this.onFinished,
        required this.tr,
        required this.onSettingsChanged});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  bool b3 = true;
  bool b24 = true;
  bool ms = true;
  bool mr = true;
  bool locked = false;
  bool showFinalContinue = false;
  late AnimationController _controller;
  late Animation<double> _fade;
  int blinkCount = 0;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _fade = Tween(begin: 1.0, end: 0.0).animate(_controller)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed)
          _controller.reverse();
        else if (status == AnimationStatus.dismissed) {
          blinkCount++;
          if (blinkCount < 2)
            _controller.forward();
          else
            setState(() {
              showFinalContinue = true;
              locked = true;
              widget.onSettingsChanged(b3, b24, ms, mr);
            });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResultInnerView(
      b3: b3,
      b24: b24,
      ms: ms,
      mr: mr,
      locked: locked,
      showFinalContinue: showFinalContinue,
      fade: _fade,
      alarmInfo: widget.alarmInfo,
      matchDate: widget.matchDate,
      country: widget.country,
      team: widget.team,
      tr: widget.tr,
      onB3Changed: (v) => setState(() => b3 = v),
      onB24Changed: (v) => setState(() => b24 = v),
      onMSChanged: (v) => setState(() => ms = v),
      onMRChanged: (v) => setState(() => mr = v),
      onFinished: widget.onFinished,
      onAnimate: () => _controller.forward(),
    );
  }
}

// ResultView için alt bileşen (Temizleme amacıyla ayrıldı)
class ResultInnerView extends StatelessWidget {
  final bool b3, b24, ms, mr, locked, showFinalContinue;
  final Animation<double> fade;
  final String alarmInfo, matchDate, country, team;
  final String Function(String) tr;
  final Function(bool) onB3Changed, onB24Changed, onMSChanged, onMRChanged;
  final VoidCallback onFinished, onAnimate;

  const ResultInnerView({
    super.key, required this.b3, required this.b24, required this.ms, required this.mr,
    required this.locked, required this.showFinalContinue, required this.fade,
    required this.alarmInfo, required this.matchDate, required this.country, required this.team,
    required this.tr, required this.onB3Changed, required this.onB24Changed,
    required this.onMSChanged, required this.onMRChanged, required this.onFinished, required this.onAnimate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3))),
              child: Text("$alarmInfo\n$matchDate".toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: DeviceSize.responsiveWidth(context, 16, 20, 24),
                      fontWeight: FontWeight.w900,
                      color: Colors.red))),
          const SizedBox(height: 16),
          Text('$country - $team'.toUpperCase(),
              style: TextStyle(
                  fontSize: DeviceSize.responsiveWidth(context, 20, 26, 32),
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          FadeTransition(
              opacity: fade,
              child: Text(tr('alarm_set'),
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: DeviceSize.responsiveWidth(context, 20, 26, 32),
                      fontWeight: FontWeight.bold))),
          const SizedBox(height: 20),
          _alarmRow(context, tr('alarm_3_days'), b3, onB3Changed),
          _alarmRow(context, tr('alarm_24_hours'), b24, onB24Changed),
          _alarmRow(context, tr('alarm_match_start'), ms, onMSChanged),
          _alarmRow(context, tr('alarm_match_result'), mr, onMRChanged),
          const SizedBox(height: 30),
          CustomImageButton(
              text: tr('continue'),
              onTap: showFinalContinue ? onFinished : onAnimate),
        ]));
  }

  Widget _alarmRow(BuildContext context, String text, bool val, Function(bool) onChanged) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(text,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: DeviceSize.responsiveWidth(context, 14, 18, 22))),
          CustomSwitch(
              value: val,
              onChanged: locked ? null : onChanged,
              onLabel: tr('on'),
              offLabel: tr('off'))
        ]));
  }
}

class CountryTeamScreen extends StatefulWidget {
  final void Function(String, String) onContinue;
  final String Function(String) tr;
  const CountryTeamScreen({super.key, required this.onContinue, required this.tr});
  @override
  State<CountryTeamScreen> createState() => _CountryTeamScreenState();
}

class _CountryTeamScreenState extends State<CountryTeamScreen> {
  String? country;
  String? team;
  @override
  Widget build(BuildContext context) {
    final teams = (country != null && teamsByCountry[country!] != null)
        ? teamsByCountry[country!]!.keys.toList()
        : <String>[];
    return Stack(children: [
      Image.asset('assets/splash/alarm_bg.png',
          fit: BoxFit.cover, width: double.infinity, height: double.infinity),
      Container(color: Colors.white.withOpacity(0.2)),
      Padding(
          padding: EdgeInsets.symmetric(
              horizontal: DeviceSize.responsiveWidth(context, 16, 80, 150)),
          child: SingleChildScrollView(
              child: Column(children: [
                const SizedBox(height: 40),
                Text(widget.tr('no_alarm').toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: DeviceSize.responsiveWidth(context, 22, 30, 38),
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
                const SizedBox(height: 20),
                const Divider(color: Colors.black, thickness: 1.5),
                const SizedBox(height: 30),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButton<String>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: Text(widget.tr('choose_country'), style: const TextStyle(color: Colors.black)),
                        value: country,
                        items: teamsByCountry.keys
                            .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e, style: const TextStyle(color: Colors.black))))
                            .toList(),
                        onChanged: (v) => setState(() {
                          country = v;
                          team = null;
                        }))),
                const SizedBox(height: 24),
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(8)),
                    child: DropdownButton<String>(
                        isExpanded: true,
                        underline: const SizedBox(),
                        hint: Text(widget.tr('choose_team'), style: const TextStyle(color: Colors.black)),
                        value: team,
                        items: teams
                            .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e, style: const TextStyle(color: Colors.black))))
                            .toList(),
                        onChanged: country == null ? null : (v) => setState(() => team = v))),
                const SizedBox(height: 60),
                CustomImageButton(
                    text: widget.tr('continue'),
                    onTap: (country != null && team != null)
                        ? () => widget.onContinue(country!, team!)
                        : null),
                const SizedBox(height: 20)
              ])))
    ]);
  }
}

class SelectedAlarmScreen extends StatefulWidget {
  final List<FootballAlarm> alarms;
  final VoidCallback onAdd;
  final Function(FootballAlarm) onDelete;
  final String Function(String) tr;
  final VoidCallback onUpgradeRedirect;
  const SelectedAlarmScreen(
      {super.key,
        required this.alarms,
        required this.onAdd,
        required this.onDelete,
        required this.tr,
        required this.onUpgradeRedirect});
  @override
  State<SelectedAlarmScreen> createState() => _SelectedAlarmScreenState();
}

class _SelectedAlarmScreenState extends State<SelectedAlarmScreen> {
  Set<String> selectedIds = {};
  bool showPremiumWarning = false;
  Timer? redirectTimer;

  void handleAddClick() {
    if (widget.alarms.length >= 1 && !AdAndPaymentService.isUserPremium) {
      setState(() => showPremiumWarning = true);
      redirectTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) widget.onUpgradeRedirect();
      });
    } else if (widget.alarms.length >= 30 && AdAndPaymentService.isUserPremium) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(widget.tr('max_alarm_limit'))));
    } else {
      widget.onAdd();
    }
  }

  @override
  void dispose() {
    redirectTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
            image: DecorationImage(image: AssetImage('assets/splash/cim.png'), fit: BoxFit.fill)),
        child: Stack(children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(
                    child: Text(widget.tr('set_alarms').toUpperCase(),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: DeviceSize.responsiveWidth(context, 24, 32, 40),
                            fontWeight: FontWeight.bold))),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView.builder(
                      itemCount: widget.alarms.length,
                      itemBuilder: (context, index) {
                        var alarm = widget.alarms[index];
                        bool isChecked = selectedIds.contains(alarm.id);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: Colors.black38, borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text("${alarm.country} - ${alarm.team}".toUpperCase(),
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: DeviceSize.responsiveWidth(context, 12, 14, 16))),
                                      Text(alarm.info.toUpperCase(),
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: DeviceSize.responsiveWidth(context, 14, 18, 22),
                                              fontWeight: FontWeight.bold)),
                                      Text(alarm.date,
                                          style: const TextStyle(color: Colors.white, fontSize: 13))
                                    ])),
                            GestureDetector(
                                onTap: () => setState(() {
                                  if (isChecked)
                                    selectedIds.remove(alarm.id);
                                  else
                                    selectedIds.add(alarm.id);
                                }),
                                child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                        color: Colors.white, borderRadius: BorderRadius.circular(4)),
                                    child: isChecked
                                        ? const Icon(Icons.check, color: Colors.green, size: 22)
                                        : null))
                          ]),
                        );
                      }),
                ),
                if (showPremiumWarning && !AdAndPaymentService.isUserPremium)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20, top: 10),
                    child: Text(
                      widget.tr('premium_warning'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: DeviceSize.responsiveWidth(context, 24, 32, 40),
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        height: 1.3,
                      ),
                    ),
                  ),
                Row(children: [
                  Expanded(
                      child: Opacity(
                          opacity: selectedIds.isNotEmpty ? 1.0 : 0.5,
                          child: GestureDetector(
                              onTap: selectedIds.isNotEmpty
                                  ? () {
                                for (var id in selectedIds) {
                                  var al = widget.alarms.firstWhere((e) => e.id == id);
                                  widget.onDelete(al);
                                }
                                setState(() => selectedIds.clear());
                              }
                                  : null,
                              child: Stack(alignment: Alignment.center, children: [
                                Image.asset('assets/splash/btn_exit_action.png',
                                    height: DeviceSize.responsiveWidth(context, 60, 75, 90),
                                    fit: BoxFit.fill),
                                Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                    child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(widget.tr('delete_alarm'),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold))))
                              ])))),
                  const SizedBox(width: 15),
                  Expanded(
                      child: GestureDetector(
                          onTap: handleAddClick,
                          child: Stack(alignment: Alignment.center, children: [
                            Image.asset('assets/splash/upgrade_button.png',
                                height: DeviceSize.responsiveWidth(context, 60, 75, 90),
                                fit: BoxFit.fill),
                            Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(widget.tr('add_alarm'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold))))
                          ])))
                ]),
                const SizedBox(height: 80),
              ])),
          ModernExitButton(tr: widget.tr),
        ]));
  }
}

class NoAlarmScreen extends StatelessWidget {
  final VoidCallback onAdd;
  final String Function(String) tr;
  const NoAlarmScreen({super.key, required this.onAdd, required this.tr});
  @override
  Widget build(BuildContext context) {
    return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
            image: DecorationImage(image: AssetImage('assets/splash/cim.png'), fit: BoxFit.fill)),
        child: Stack(children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Center(
                child: Text(tr('no_alarm').toUpperCase(),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: DeviceSize.responsiveWidth(context, 24, 32, 40),
                        fontWeight: FontWeight.bold))),
            const SizedBox(height: 50),
            GestureDetector(
                onTap: onAdd,
                child: Stack(alignment: Alignment.center, children: [
                  Image.asset('assets/splash/upgrade_button.png',
                      width: DeviceSize.responsiveWidth(context, 220, 300, 380), fit: BoxFit.contain),
                  Text(tr('add_alarm'),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: DeviceSize.responsiveWidth(context, 18, 24, 30),
                          fontWeight: FontWeight.bold))
                ]))
          ]),
          ModernExitButton(tr: tr),
        ]));
  }
}

class LoginScreen extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onAppleLogin; // YENİ
  final VoidCallback onGoToRegister;
  final String Function(String) tr;
  const LoginScreen({super.key, required this.onLogin, required this.onAppleLogin, required this.onGoToRegister, required this.tr});

  @override
  Widget build(BuildContext context) {
    final double bWidth = DeviceSize.responsiveWidth(context, 280, 400, 500);

    return Stack(children: [
      Image.asset('assets/splash/bg_stadium.png',
          fit: BoxFit.cover, width: double.infinity, height: double.infinity),
      Center(
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('login_title'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: DeviceSize.responsiveWidth(context, 22, 28, 34),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                _authButton(context, bWidth, 'assets/splash/google_logo.png', "Google", Colors.black,
                    Colors.white, onLogin),
                const SizedBox(height: 16),
                _authButton(context, bWidth, 'assets/splash/apple_logo.png', "Apple", Colors.white,
                    Colors.black, onAppleLogin), // APPLE LOGIN
                const SizedBox(height: 35),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(tr('no_account'),
                      style: TextStyle(color: Colors.white, fontSize: DeviceSize.responsiveWidth(context, 14, 18, 22))),
                  const SizedBox(width: 10),
                  GestureDetector(
                      onTap: onGoToRegister,
                      child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.white24)),
                          child: Text(tr('register'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))))
                ])
              ])))
    ]);
  }

  Widget _authButton(
      BuildContext ctx, double w, String asset, String label, Color bg, Color txt, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        width: w,
        height: DeviceSize.responsiveWidth(ctx, 56, 75, 90),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white24)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
              height: DeviceSize.responsiveWidth(ctx, 28, 40, 50),
              width: DeviceSize.responsiveWidth(ctx, 28, 40, 50),
              child: Image.asset(asset, fit: BoxFit.contain)),
          const SizedBox(width: 15),
          Text(label,
              style: TextStyle(
                  color: txt,
                  fontSize: DeviceSize.responsiveWidth(ctx, 18, 22, 26),
                  fontWeight: FontWeight.bold))
        ]),
      ),
    );
  }
}

class RegisterScreen extends StatelessWidget {
  final VoidCallback onGoToLogin;
  final VoidCallback onRegisterComplete;
  final VoidCallback onAppleRegister; // YENİ
  final String Function(String) tr;
  const RegisterScreen(
      {super.key, required this.onGoToLogin, required this.onRegisterComplete, required this.onAppleRegister, required this.tr});

  @override
  Widget build(BuildContext context) {
    final double bWidth = DeviceSize.responsiveWidth(context, 280, 400, 500);

    return Stack(children: [
      Image.asset('assets/splash/bg_stadium.png',
          fit: BoxFit.cover, width: double.infinity, height: double.infinity),
      Center(
          child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('register').toUpperCase(),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: DeviceSize.responsiveWidth(context, 22, 28, 34),
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                _authButton(context, bWidth, 'assets/splash/google_logo.png', "Google", Colors.black,
                    Colors.white, onRegisterComplete),
                const SizedBox(height: 16),
                _authButton(context, bWidth, 'assets/splash/apple_logo.png', "Apple", Colors.white,
                    Colors.black, onAppleRegister), // APPLE REGISTER
                const SizedBox(height: 35),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(tr('has_account'),
                      style: TextStyle(color: Colors.white, fontSize: DeviceSize.responsiveWidth(context, 14, 18, 22))),
                  const SizedBox(width: 10),
                  GestureDetector(
                      onTap: onGoToLogin,
                      child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(color: Colors.white24)),
                          child: Text(tr('login'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))))
                ])
              ])))
    ]);
  }

  Widget _authButton(
      BuildContext ctx, double w, String asset, String label, Color bg, Color txt, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        width: w,
        height: DeviceSize.responsiveWidth(ctx, 56, 75, 90),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white24)),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
              height: DeviceSize.responsiveWidth(ctx, 28, 40, 50),
              width: DeviceSize.responsiveWidth(ctx, 28, 40, 50),
              child: Image.asset(asset, fit: BoxFit.contain)),
          const SizedBox(width: 15),
          Text(label,
              style: TextStyle(
                  color: txt,
                  fontSize: DeviceSize.responsiveWidth(ctx, 18, 22, 26),
                  fontWeight: FontWeight.bold))
        ]),
      ),
    );
  }
}

class UpgradeScreen extends StatefulWidget {
  final String Function(String) tr;
  final Function(bool) onPremiumUpdate;
  const UpgradeScreen(
      {super.key,
        required this.tr,
        required this.onPremiumUpdate});
  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.3).animate(_blinkController);
  }

  void _showPremiumDialog() {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(widget.tr('premium_confirm_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          content: Text(widget.tr('premium_confirm_body'), textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(widget.tr('no'), style: const TextStyle(color: Colors.red))),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  AdAndPaymentService.buyUpgrade();
                  Navigator.pop(c);
                },
                child: Text(widget.tr('yes'), style: const TextStyle(color: Colors.white))),
          ],
        ));
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isPremium = AdAndPaymentService.isUserPremium;
    final String backgroundAsset =
    isPremium ? 'assets/splash/premium_page.png' : 'assets/splash/bg_upgrade.png';

    return Stack(children: [
      Image.asset(backgroundAsset,
          fit: BoxFit.cover, width: double.infinity, height: double.infinity),
      Center(
        child: SingleChildScrollView(
          child: isPremium
              ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 150),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.tr('premium_status'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: DeviceSize.responsiveWidth(context, 24, 32, 40),
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(blurRadius: 10, color: Colors.black, offset: Offset(2, 2))
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.tr('premium_limit_info'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: DeviceSize.responsiveWidth(context, 16, 20, 24),
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(blurRadius: 10, color: Colors.black, offset: Offset(1, 1))
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 60),
            ],
          )
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 38),
              Text(widget.tr('upgrade_title'),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: DeviceSize.responsiveWidth(context, 32, 40, 48),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
              const SizedBox(height: 40),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(widget.tr('upgrade_desc1'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: DeviceSize.responsiveWidth(context, 18, 24, 30),
                          fontWeight: FontWeight.bold))),
              const SizedBox(height: 15),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Text(widget.tr('upgrade_desc2'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: DeviceSize.responsiveWidth(context, 18, 24, 30),
                          fontWeight: FontWeight.bold))),
              const SizedBox(height: 50),
              Text(widget.tr('upgrade_subscription_msg'),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              FadeTransition(
                  opacity: _opacityAnimation,
                  child: GestureDetector(
                      onTap: _showPremiumDialog,
                      child: Stack(alignment: Alignment.center, children: [
                        Image.asset('assets/splash/upgrade_button.png',
                            width: DeviceSize.responsiveWidth(context, 260, 350, 450),
                            fit: BoxFit.contain),
                        Text(widget.tr('upgrade_button'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: DeviceSize.responsiveWidth(context, 22, 28, 34),
                                fontWeight: FontWeight.w900))
                      ]))),
            ],
          ),
        ),
      ),
    ]);
  }
}

class SettingsScreen extends StatelessWidget {
  final String Function(String) tr;
  final String? currentUserEmail;
  final String currentLanguageCode;
  final bool isSoundEnabled;
  final bool isPremium;
  final void Function(String) onLanguageChange;
  final void Function(bool) onSoundChange;
  final VoidCallback onLogOff;
  const SettingsScreen(
      {super.key,
        required this.tr,
        required this.currentUserEmail,
        required this.currentLanguageCode,
        required this.isSoundEnabled,
        required this.isPremium,
        required this.onLanguageChange,
        required this.onSoundChange,
        required this.onLogOff});

  Future<void> _launchURL() async {
    const platform = MethodChannel('flutter.native/helper');
    try {
      await platform.invokeMethod(
          'openUrl', {'url': 'https://sites.google.com/view/football-alarm-policy/ana-sayfa'});
    } on PlatformException catch (e) {
      debugPrint("Link açma hatası: ${e.message}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> languages = [
      {'code': 'tr', 'name': tr('lang_tr')},
      {'code': 'en', 'name': tr('lang_en')},
      {'code': 'zh', 'name': tr('lang_zh')},
      {'code': 'hi', 'name': tr('lang_hi')},
      {'code': 'es', 'name': tr('lang_es')},
      {'code': 'fr', 'name': tr('lang_fr')},
      {'code': 'ar', 'name': tr('lang_ar')},
      {'code': 'bn', 'name': tr('lang_bn')},
      {'code': 'pt', 'name': tr('lang_pt')},
      {'code': 'ru', 'name': tr('lang_ru')},
      {'code': 'id', 'name': tr('lang_id')},
      {'code': 'de', 'name': tr('lang_de')},
      {'code': 'ja', 'name': tr('lang_ja')},
      {'code': 'ko', 'name': tr('lang_ko')},
      {'code': 'it', 'name': tr('lang_it')},
      {'code': 'nl', 'name': tr('lang_nl')},
    ];

    final double sidePadding = DeviceSize.responsiveWidth(context, 16, 100, 200);

    return Stack(children: [
      Image.asset('assets/splash/bg_settings.png',
          fit: BoxFit.cover, width: double.infinity, height: double.infinity),
      Container(color: Colors.black.withOpacity(0.3)),
      SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: sidePadding, vertical: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildSettingLabel(tr('settings_user')),
            Text(currentUserEmail ?? 'guest@user.com', style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            _buildSettingLabel(tr('settings_plan')),
            Text(isPremium ? "PREMIUM (Monthly)" : tr('plan_standard'), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            _buildSettingLabel(tr('settings_support')),
            const Text('programgrubu@gmail.com', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            _buildSettingLabel(tr('settings_language')),
            Theme(
                data: Theme.of(context).copyWith(canvasColor: Colors.black),
                child: DropdownButton<String>(
                    isExpanded: true,
                    value: currentLanguageCode,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    dropdownColor: Colors.grey.shade900,
                    items: languages
                        .map((lang) => DropdownMenuItem(value: lang['code'], child: Text(lang['name']!)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) onLanguageChange(v);
                    })),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSettingLabel(tr('settings_sound')),
                CustomSwitch(
                  value: isSoundEnabled,
                  onChanged: onSoundChange,
                  onLabel: tr('on'),
                  offLabel: tr('off'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: _launchURL,
                child: Text(
                  tr('privacy_policy'),
                  style: TextStyle(
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                      fontSize: DeviceSize.responsiveWidth(context, 22, 28, 34),
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
                width: double.infinity,
                height: DeviceSize.responsiveWidth(context, 56, 75, 90),
                child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    onPressed: onLogOff,
                    child: Text(tr('settings_logoff').toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))),
            const SizedBox(height: 100),
          ])),
      ModernExitButton(
        tr: tr,
        bottomPadding: DeviceSize.responsiveWidth(context, 12, 20, 25),
      ),
    ]);
  }

  Widget _buildSettingLabel(String text) {
    return Text(text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18));
  }
}

class CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String onLabel;
  final String offLabel;
  const CustomSwitch(
      {super.key,
        required this.value,
        required this.onChanged,
        required this.onLabel,
        required this.offLabel});
  @override
  Widget build(BuildContext context) {
    final double sWidth = DeviceSize.responsiveWidth(context, 100, 140, 170);
    final double sHeight = DeviceSize.responsiveWidth(context, 34, 45, 55);

    return GestureDetector(
        onTap: onChanged != null ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: sWidth,
            height: sHeight,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: value ? Colors.green : Colors.grey.shade400),
            child: Stack(children: [
              AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: value ? Alignment.centerLeft : Alignment.centerRight,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(value ? onLabel : offLabel,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
              AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                      width: sHeight - 6,
                      height: sHeight - 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)))
            ])));
  }
}