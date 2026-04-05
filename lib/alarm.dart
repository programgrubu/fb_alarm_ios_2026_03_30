import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

// VERİ DOSYALARI IMPORT
import 'languages.dart';

// ==========================================
// WORKMANAGER ARKA PLAN GÖREVİ
// ==========================================
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await dotenv.load(fileName: ".env");
      final String matchId = inputData?['matchId'] ?? '';
      final String lang = inputData?['lang'] ?? 'tr';
      final int attempt = inputData?['attempt'] ?? 1;

      if (matchId.isNotEmpty) {
        final String scoreResult = await MatchResultService.getMatchScore(matchId);

        if (scoreResult.isNotEmpty) {
          final NotificationService nos = NotificationService();
          await nos.init();
          await nos.showImmediateNotification(
            matchId.hashCode + 999,
            AppTranslations.getTranslation('main_title', lang),
            scoreResult,
            payload: matchId,
          );
        } else if (attempt < 6) {
          Workmanager().registerOneOffTask(
            "retry_check_${matchId}_${attempt + 1}",
            "fetch_match_result",
            initialDelay: const Duration(minutes: 15),
            inputData: {
              'matchId': matchId,
              'lang': lang,
              'attempt': attempt + 1,
            },
            constraints: Constraints(networkType: NetworkType.connected),
          );
        }
      }
    } catch (e) {
      debugPrint("Workmanager Background Task Error: $e");
    }
    return Future.value(true);
  });
}

// ==========================================
// ALARM MODELİ (DEĞİŞTİRİLMEDİ)
// ==========================================
class FootballAlarm {
  final String id;
  final String info;
  final String date;
  final String country;
  final String team;
  bool b3;
  bool b24;
  bool ms;
  bool mr;
  String? score;

  FootballAlarm({
    required this.id,
    required this.info,
    required this.date,
    required this.country,
    required this.team,
    this.b3 = true,
    this.b24 = true,
    this.ms = true,
    this.mr = true,
    this.score,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'info': info,
    'date': date,
    'country': country,
    'team': team,
    'b3': b3,
    'b24': b24,
    'ms': ms,
    'mr': mr,
    'score': score,
  };

  factory FootballAlarm.fromJson(Map<String, dynamic> json) => FootballAlarm(
    id: json['id'].toString(),
    info: json['info'],
    date: json['date'],
    country: json['country'],
    team: json['team'] ?? '',
    b3: json['b3'] ?? true,
    b24: json['b24'] ?? true,
    ms: json['ms'] ?? true,
    mr: json['mr'] ?? true,
    score: json['score'],
  );
}

// ==========================================
// BİLDİRİM SERVİSİ (IOS & ANDROID UYUMLU)
// ==========================================
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  final String _notificationIcon = 'ball';

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('ball');

    // iOS İÇİN GEREKLİ AYARLAR EKLENDİ
    const DarwinInitializationSettings initializationSettingsDarwin =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint("Notification Payload: ${details.payload}");
      },
    );
    tz.initializeTimeZones();
  }

  Future<bool> requestNotificationPermissions() async {
    if (Platform.isIOS) {
      return await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } else if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidImplementation?.requestNotificationsPermission() ?? false;
    }
    return false;
  }

  Future<void> scheduleNotification(
      int id, String title, String body, DateTime scheduledDate,
      {String? payload, bool playSound = true}) async {
    if (scheduledDate.isBefore(DateTime.now())) return;

    final String channelId =
    playSound ? 'football_alarm_channel' : 'football_silent_channel';
    final String channelName =
    playSound ? 'Football Alarms' : 'Silent Notifications';

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority: Priority.high,
          icon: _notificationIcon,
          playSound: playSound,
          sound: playSound
              ? const RawResourceAndroidNotificationSound('alarm_sound')
              : null,
          enableVibration: true,
          styleInformation: BigTextStyleInformation(body),
        ),
        // iOS Detayları Eklendi
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
          sound: playSound ? 'alarm_sound.wav' : null,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> showImmediateNotification(int id, String title, String body,
      {String? payload}) async {
    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'football_result_channel',
          'Match Results',
          importance: Importance.max,
          priority: Priority.high,
          icon: _notificationIcon,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}

// ==========================================
// MAÇ SONUCU VE API SERVİSİ (DEĞİŞTİRİLMEDİ)
// ==========================================
class MatchResultService {
  static String get _apiKey => dotenv.env['FOOTBALL_API_KEY'] ?? '';

  static Future<String> getMatchScore(String matchId, {String lang = 'tr'}) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.football-data.org/v4/matches/$matchId'),
        headers: {'X-Auth-Token': _apiKey},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final score = data['score']?['fullTime'];
        if (score != null) {
          final int? home = score['home'];
          final int? away = score['away'];
          final String homeTeam =
              data['homeTeam']?['shortName'] ?? data['homeTeam']?['name'] ?? '';
          final String awayTeam =
              data['awayTeam']?['shortName'] ?? data['awayTeam']?['name'] ?? '';

          if (home != null && away != null) {
            return "$home $homeTeam - $away $awayTeam";
          }
        }
      }
    } catch (e) {
      debugPrint("API Error (Score): $e");
    }
    return "";
  }

  static void scheduleResultCheck(
      String matchId, DateTime matchTime, String lang, String teamName) {
    final delay =
    matchTime.add(const Duration(minutes: 115)).difference(DateTime.now());

    Workmanager().registerOneOffTask(
      "check_score_$matchId",
      "fetch_match_result",
      initialDelay: delay.isNegative ? Duration.zero : delay,
      inputData: {
        'matchId': matchId,
        'lang': lang,
        'teamName': teamName,
        'attempt': 1,
      },
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}