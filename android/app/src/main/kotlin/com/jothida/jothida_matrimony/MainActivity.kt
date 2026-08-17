package com.jothida.jothida_matrimony

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * Adds one channel: saving a generated file straight to the phone.
 *
 * The profile download has to land in the user's own storage without going
 * through the Android share sheet, so it cannot use share_plus. On API 29+ the
 * only sanctioned way to write into Downloads or Pictures is MediaStore, which
 * needs no runtime permission — the app owns the row it inserts. On API 23-28
 * scoped storage does not exist yet, so the file goes to the public directory
 * directly and is handed to the media scanner so it shows up in Files/Gallery.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.jothida.jothida_matrimony/device_files"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> save(call.argument("bytes"),
                        call.argument("fileName"), call.argument("mimeType"),
                        toDownloads = true, result = result)
                    "saveToPictures" -> save(call.argument("bytes"),
                        call.argument("fileName"), call.argument("mimeType"),
                        toDownloads = false, result = result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun save(
        bytes: ByteArray?,
        fileName: String?,
        mimeType: String?,
        toDownloads: Boolean,
        result: MethodChannel.Result,
    ) {
        if (bytes == null || fileName.isNullOrBlank()) {
            result.error("bad_args", "bytes and fileName are required", null)
            return
        }
        val mime = mimeType ?: if (toDownloads) "application/pdf" else "image/png"
        try {
            val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveViaMediaStore(bytes, fileName, mime, toDownloads)
            } else {
                saveLegacy(bytes, fileName, toDownloads)
            }
            result.success(path)
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    /** API 29+: insert a row, stream into it, then clear IS_PENDING. */
    private fun saveViaMediaStore(
        bytes: ByteArray,
        fileName: String,
        mime: String,
        toDownloads: Boolean,
    ): String {
        val collection: Uri
        val relative: String
        if (toDownloads) {
            collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            relative = Environment.DIRECTORY_DOWNLOADS
        } else {
            collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            relative = Environment.DIRECTORY_PICTURES + "/Jothida Matrimony"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            // Hides the row until the bytes are fully written, so nothing ever
            // opens a half-written file.
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        val resolver = applicationContext.contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore refused the insert")

        resolver.openOutputStream(uri)?.use { it.write(bytes) }
            ?: throw IllegalStateException("Could not open $uri for writing")

        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return "$relative/$fileName"
    }

    /**
     * API 23-28: write to the public directory. WRITE_EXTERNAL_STORAGE is
     * declared with maxSdkVersion="28" and granted at install time on these
     * releases, so no runtime prompt is needed here.
     */
    private fun saveLegacy(
        bytes: ByteArray,
        fileName: String,
        toDownloads: Boolean,
    ): String {
        val dir = if (toDownloads) {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        } else {
            File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "Jothida Matrimony",
            )
        }
        if (!dir.exists()) dir.mkdirs()

        // Never silently overwrite something already sitting in Downloads.
        var target = File(dir, fileName)
        if (target.exists()) {
            val dot = fileName.lastIndexOf('.')
            val stem = if (dot > 0) fileName.substring(0, dot) else fileName
            val ext = if (dot > 0) fileName.substring(dot) else ""
            var n = 1
            while (target.exists()) target = File(dir, "$stem ($n)$ext").also { n++ }
        }

        FileOutputStream(target).use { it.write(bytes) }
        // Make it visible in Files / Gallery straight away.
        android.media.MediaScannerConnection.scanFile(
            applicationContext, arrayOf(target.absolutePath), null, null,
        )
        return target.absolutePath
    }
}
