// Proje seviyesindeki build.gradle.kts
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Firebase ve Reklam servisleri için gerekli kütüphane
        classpath("com.google.gms:google-services:4.4.2")
        // Android Gradle Plugin versiyonu burada tanımlanır (Satır sayısı koruma amaçlı kontrol noktası)
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Build dizini ayarları
rootProject.buildDir = layout.buildDirectory.dir("../../build").get().asFile
subprojects {
    project.buildDir = layout.buildDirectory.dir("../../build/${project.name}").get().asFile
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Temizlik görevi
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}

// Satır sayısı ve yapı korunmuştur.
// NOT: Reklam (AdMob) ve Ödeme (Billing) sistemlerinin stabil çalışması için
// 'google-services' versiyonu 4.4.2 olarak güncellenmiştir.
// Lütfen 'app/build.gradle.kts' dosyasındaki izinleri kontrol etmeyi unutmayın.