package com.minisoccer.minisoccer_club

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "app/installer"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        // Sistem bisa mengembalikan layar ke 60 Hz saat app di latar (mode
        // hemat daya, atau app lain meminta rate rendah). Menerapkannya lagi
        // di sini membuat app tetap 120 Hz setelah kembali ke depan.
        requestHighestRefreshRate()
    }

    /**
     * Minta layar berjalan pada refresh rate tertinggi yang didukung.
     *
     * Tanpa ini Android memilih mode layar sendiri dan hampir selalu memakai
     * 60 Hz, jadi HP 120 Hz tetap terasa 60 Hz: animasi dan scroll tampak
     * tersendat walau perangkatnya sanggup. Flutter sendiri tidak membatasi
     * frame rate — ia mengikuti vsync layar yang diberikan sistem.
     *
     * Dua hal diset, karena keduanya menutup jalur yang berbeda:
     *   * `preferredDisplayModeId` memilih mode layar yang benar-benar
     *     120 Hz (bukan sekadar meminta).
     *   * `preferredRefreshRate` memberi tahu sistem rate yang diinginkan
     *     kalau mode harus diganti sendiri (mis. perangkat lipat).
     *
     * Resolusi tidak diubah: mode dicari yang lebarnya sama dengan mode
     * sekarang, supaya tidak ada tampilan yang di-scale ulang dan teks tidak
     * jadi buram. Kalau layar hanya punya mode 60 Hz, tidak ada yang berubah.
     */
    private fun requestHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dsp: Display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            wm.defaultDisplay
        } ?: return

        val current = dsp.mode ?: return
        // Mode dicari pada lebar fisik yang sama: mode 120 Hz biasanya punya
        // resolusi lebih rendah, dan memakainya akan membuat seluruh UI
        // di-scale ulang (teks jadi buram) hanya demi angka frame.
        val best = dsp.supportedModes
            .asSequence()
            .filter { it.physicalWidth == current.physicalWidth }
            .maxByOrNull { it.refreshRate }
            ?: return

        if (best.refreshRate > current.refreshRate + 0.5f) {
            val attrs = window.attributes
            attrs.preferredDisplayModeId = best.modeId
            attrs.preferredRefreshRate = best.refreshRate
            window.attributes = attrs
        }

        // Mode layar saja belum cukup di Android 15+ (targetSdk 35 ke atas):
        // sistem menganggap aplikasi ingin 60 Hz kecuali permukaan render
        // menyatakan frame rate-nya sendiri. Ini yang membuat HP 120 Hz tetap
        // 60 Hz walau mode layarnya sudah 120.
        applySurfaceFrameRate(best.refreshRate)
    }

    /**
     * Nyatakan frame rate yang diinginkan ke permukaan render Flutter.
     *
     * Dipanggil setelah layout: pada `onCreate` permukaan Flutter belum ada.
     * Kalau permukaannya belum siap, callback dipasang sekali supaya
     * permintaan tetap terkirim saat permukaan dibuat (mis. setelah rotasi).
     *
     * `FRAME_RATE_COMPATIBILITY_DEFAULT` (bukan FIXED) dipakai supaya sistem
     * masih boleh menurunkan rate saat layar diam — itu yang menghemat baterai
     * tanpa membuat animasi tersendat.
     */
    private fun applySurfaceFrameRate(rate: Float) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        window.decorView.post {
            val sv = findSurfaceView(window.decorView) ?: return@post
            val holder = sv.holder
            val surface = holder.surface
            if (surface.isValid) {
                surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
                return@post
            }
            holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(h: SurfaceHolder) {
                    h.surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
                    h.removeCallback(this)
                }

                override fun surfaceChanged(h: SurfaceHolder, format: Int, w: Int, h2: Int) = Unit
                override fun surfaceDestroyed(h: SurfaceHolder) = Unit
            })
        }
    }

    private fun findSurfaceView(root: View): SurfaceView? {
        if (root is SurfaceView) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findSurfaceView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

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
