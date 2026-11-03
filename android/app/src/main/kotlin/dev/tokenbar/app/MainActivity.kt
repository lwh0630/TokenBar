package dev.tokenbar.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tokenbar/installer")
            .setMethodCallHandler { call, result ->
                if (call.method != "installApk") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.arguments as? String
                if (path == null) {
                    result.error("bad_args", "path expected", null)
                } else {
                    result.success(installApk(path))
                }
            }
    }

    /**
     * Hands a downloaded update to the system package installer. Returns "started",
     * "needs_permission" (the user has to allow installs from this app first; the settings
     * page is opened) or "failed". Android itself refuses an APK that is not signed with the
     * key of the installed app.
     */
    private fun installApk(path: String): String {
        val file = File(path)
        if (!file.isFile) return "failed"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            return "needs_permission"
        }
        return try {
            val uri = UpdateFileProvider.uriFor(this, file)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            "started"
        } catch (e: Exception) {
            "failed"
        }
    }
}