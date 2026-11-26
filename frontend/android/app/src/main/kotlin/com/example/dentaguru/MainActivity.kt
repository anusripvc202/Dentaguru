package com.example.dentaguru

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val RECORD_FILES_CHANNEL = "com.example.dentaguru/record_files"
        private const val REQ_PICK_RECORD_FILE = 4109
        private const val MAX_RECORD_FILE_BYTES = 20 * 1024 * 1024 // 20 MB
    }

    private var pendingPickResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORD_FILES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickRecordFile" -> handlePickRecordFile(result)
                    "saveAndOpenRecordFile" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        val fileName = call.argument<String>("fileName") ?: "medical_record.pdf"
                        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                        if (bytes == null || bytes.isEmpty()) {
                            result.success(false)
                        } else {
                            handleSaveAndOpenRecordFile(bytes, fileName, mimeType, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun handlePickRecordFile(result: MethodChannel.Result) {
        pendingPickResult?.success(null)
        pendingPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf("application/pdf", "image/jpeg", "image/png")
                )
            }
            startActivityForResult(intent, REQ_PICK_RECORD_FILE)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICK_ERROR", e.message ?: "Unable to launch document picker", null)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK_RECORD_FILE) {
            val callback = pendingPickResult
            pendingPickResult = null
            if (callback == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                callback.success(null)
                return
            }
            val uri: Uri = data.data!!
            try {
                val fileName = resolveDisplayName(uri)
                val mimeType = contentResolver.getType(uri) ?: guessMimeFromName(fileName)
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val dataBytes = input.readBytes()
                    if (dataBytes.size > MAX_RECORD_FILE_BYTES) {
                        throw IllegalArgumentException("Selected file exceeds 20 MB limit.")
                    }
                    dataBytes
                }
                if (bytes == null || bytes.isEmpty()) {
                    callback.success(null)
                    return
                }
                callback.success(
                    mapOf(
                        "name" to fileName,
                        "mimeType" to mimeType,
                        "bytes" to bytes,
                        "sizeBytes" to bytes.size
                    )
                )
            } catch (e: Exception) {
                callback.error("READ_ERROR", e.message ?: "Failed to read selected file", null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun resolveDisplayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) {
                    val value = cursor.getString(idx)
                    if (!value.isNullOrBlank()) return value
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/')?.takeIf { it.isNotBlank() }
            ?: "medical_record_${System.currentTimeMillis()}"
    }

    private fun guessMimeFromName(fileName: String): String {
        val lower = fileName.lowercase()
        return when {
            lower.endsWith(".pdf") -> "application/pdf"
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            else -> "application/octet-stream"
        }
    }

    private fun sanitizeFileName(raw: String): String {
        val trimmed = raw.trim().ifEmpty { "medical_record_${System.currentTimeMillis()}.pdf" }
        return trimmed.replace(Regex("[^a-zA-Z0-9._-]"), "_")
    }

    private fun handleSaveAndOpenRecordFile(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        result: MethodChannel.Result
    ) {
        try {
            val safeName = sanitizeFileName(fileName)
            val effectiveMime = mimeType.trim().ifEmpty { guessMimeFromName(safeName) }

            // 1. Save persistent copy to Downloads (MediaStore on Android 10+, app external Downloads on older APIs)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, safeName)
                    put(MediaStore.Downloads.MIME_TYPE, effectiveMime)
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }
                val resolver = contentResolver
                val downloadUri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (downloadUri != null) {
                    resolver.openOutputStream(downloadUri)?.use { out ->
                        out.write(bytes)
                        out.flush()
                    }
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    resolver.update(downloadUri, values, null, null)
                }
            } else {
                val downloadsDir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
                if (downloadsDir != null) {
                    if (!downloadsDir.exists()) downloadsDir.mkdirs()
                    File(downloadsDir, safeName).writeBytes(bytes)
                }
            }

            // 2. Write shareable copy to FileProvider cache dir and launch viewer Intent
            val recordsCacheDir = File(cacheDir, "records")
            if (!recordsCacheDir.exists()) recordsCacheDir.mkdirs()
            val cacheFile = File(recordsCacheDir, safeName)
            cacheFile.writeBytes(bytes)

            val contentUri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                cacheFile
            )
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, effectiveMime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                startActivity(viewIntent)
            } catch (_: ActivityNotFoundException) {
                // File was still saved to Downloads even if no viewer app is installed
            }

            result.success(true)
        } catch (e: Exception) {
            result.error("SAVE_ERROR", e.message ?: "Failed to save medical record", null)
        }
    }
}
