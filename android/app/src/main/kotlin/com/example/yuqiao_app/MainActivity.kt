package com.example.yuqiao_app

import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.yuqiao_app/gallery"
    private val pickGalleryRequest = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            if (call.method != "openGallery") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (pendingResult != null) {
                result.error("ALREADY_ACTIVE", "图库已经打开", null)
                return@setMethodCallHandler
            }

            pendingResult = result
            val intent = Intent(
                Intent.ACTION_PICK,
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            ).apply {
                type = "image/*"
            }
            try {
                startActivityForResult(intent, pickGalleryRequest)
            } catch (_: Exception) {
                pendingResult = null
                result.error("NO_GALLERY", "未找到可用的手机图库", null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickGalleryRequest) return

        val result = pendingResult
        pendingResult = null
        if (resultCode != RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }

        val path = copyImageToCache(data.data!!)
        if (path == null) {
            result?.error("IMAGE_READ_FAILED", "无法读取所选图片", null)
        } else {
            result?.success(path)
        }
    }

    private fun copyImageToCache(uri: Uri): String? {
        return try {
            val source = contentResolver.openInputStream(uri) ?: return null
            val cacheFile = File(cacheDir, "profile_image_${System.currentTimeMillis()}.jpg")
            source.use { input ->
                FileOutputStream(cacheFile).use { output ->
                    input.copyTo(output)
                }
            }
            cacheFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }
}
