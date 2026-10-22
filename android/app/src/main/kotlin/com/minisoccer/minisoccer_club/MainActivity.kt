package com.minisoccer.minisoccer_club

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "app/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success("failed")
                            return@setMethodCallHandler
                        }
                        result.success(installApk(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Buka installer paket untuk APK di cache. Return:
     *   "started"    -> layar "Pasang" terbuka
     *   "permission" -> izin "pasang aplikasi tak dikenal" belum ada; layar
     *                   pengaturannya dibuka supaya user bisa mengaktifkan
     *   "failed"     -> intent tidak bisa dibuka
     */
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.exists()) return "failed"

        // Android 8+: pemasangan dari luar Play Store butuh izin per-aplikasi.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return "permission"
        }

        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileProvider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            "started"
        } catch (e: Exception) {
            "failed"
        }
    }
}
