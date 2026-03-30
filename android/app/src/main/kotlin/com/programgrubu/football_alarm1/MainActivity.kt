package com.programgrubu.football.alarm1

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "flutter.native/helper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ==========================================================
        // MODERN ANDROID EKRAN UYANDIRMA AYARLARI
        // ==========================================================
        // Kilit ekranında pencereyi uyandırma ve gösterme yetkisi (Modern Android için)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }

        // ==========================================================
        // METHOD CHANNEL YÖNETİMİ (FLUTTER İLE İLETİŞİM)
        // ==========================================================
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // SİSTEM ÜZERİNDE GÖSTERME İZNİ SAYFASINI AÇAR
                "openOverlaySettings" -> {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(null)
                }

                // GİZLİLİK POLİTİKASI VEYA HARİCİ LİNKLERİ TARAYICIDA AÇAR
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("UNAVAILABLE", "URL açılamadı: $url", e.localizedMessage)
                        }
                    } else {
                        result.error("NO_URL", "URL boş gönderildi", null)
                    }
                }

                // GELECEKTE EKLENEBİLECEK DİĞER MODÜLLER İÇİN REZERV ALAN
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}

// PROGRAM SONU - MAINACTIVITY KOTLIN KODLARI v2.8.0
// GİZLİLİK POLİTİKASI TARAYICI DESTEĞİ VE OVERLAY YETKİSİ AKTİFTİR.
// SATIR SAYISI ARTIRILMIŞ VE MEVCUT MANTIK KORUNMUŞTUR.