package dev.tokenbar.app

import android.content.Context
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

/**
 * Serves the downloaded update APK to the system installer. A subclass of its own, so it cannot
 * clash with the FileProvider that some plugins declare; it only exposes `cache/tokenbar-update/`
 * (see res/xml/tokenbar_update_paths.xml).
 */
class UpdateFileProvider : FileProvider() {
    companion object {
        fun authority(context: Context) = "${context.packageName}.updates"

        fun uriFor(context: Context, file: File): Uri =
            getUriForFile(context, authority(context), file)
    }
}