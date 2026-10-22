import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Penandatanganan rilis
// ---------------------------------------------------------------------------
// Sebelumnya build rilis memakai kunci DEBUG (`signingConfigs.getByName("debug")`).
// Android membuat kunci debug baru di setiap mesin/runner, jadi setiap APK yang
// diunduh dari GitHub punya sertifikat berbeda dari yang terpasang. Akibatnya
// update SELALU ditolak dengan "Aplikasi tidak terpasang", dan satu-satunya
// jalan keluar adalah uninstall — yang ikut menghapus antrean offline
// (outbox.json) beserta cache datanya.
//
// Sekarang rilis memakai kunci tetap dari `android/key.properties` (tidak ikut
// git). Kalau berkas itu tidak ada — mis. orang lain meng-clone repo ini —
// build rilis jatuh ke kunci debug dengan peringatan, supaya `flutter run
// --release` tetap bisa dipakai untuk mencoba.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { stream -> keystoreProperties.load(stream) }
}

android {
    namespace = "com.minisoccer.minisoccer_club"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.minisoccer.minisoccer_club"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // Kunci ini harus sama untuk setiap rilis; kalau berubah,
                // pengguna tidak bisa memperbarui aplikasi tanpa uninstall.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "PERINGATAN: android/key.properties tidak ada — APK rilis " +
                        "ditandatangani kunci debug dan TIDAK bisa dipakai untuk " +
                        "memperbarui aplikasi yang sudah terpasang."
                )
                signingConfigs.getByName("debug")
            }
            // R8/minify sengaja TIDAK diaktifkan: penyusutan kode bisa
            // mengubah perilaku plugin yang memakai refleksi, dan build rilis
            // ini tidak bisa diuji di perangkat oleh siapa pun yang menyiapkan
            // repo. APK yang benar lebih penting daripada APK yang kecil.
        }
    }

    // APK dibangun untuk tiga arsitektur; ukurannya wajar untuk aplikasi
    // Flutter dan tidak perlu dipecah (pengguna hanya mengunduh satu berkas).
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
