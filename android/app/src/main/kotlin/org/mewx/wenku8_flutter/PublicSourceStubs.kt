package org.mewx.wenku8_flutter

import android.app.Activity
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.io.File

/** TXT and EPUB pass through. Other containers are reported unavailable. */
internal class BookArchiveImport(private val root: File) {
    var documents: BookMarkupImport? = null

    fun prepare(name: String, source: File): List<Map<String, Any?>> =
        prepare(name, BookDocumentInput(source))

    fun prepare(name: String, source: BookDocumentInput): List<Map<String, Any?>> {
        val lower = name.lowercase()
        val file = source.file
        if ((lower.endsWith(".txt") || lower.endsWith(".epub")) && file != null) {
            return listOf(mapOf("name" to name, "path" to file.path))
        }
        return listOf(mapOf("name" to name, "error" to "此版本只能导入 TXT 和 EPUB"))
    }

    companion object {
        const val MAX_ARCHIVE = 512L * 1024 * 1024
        private val extensions = setOf(
            "txt", "epub", "zip", "html", "htm", "xhtml", "md", "markdown",
            "fb2", "docx", "rtf", "mobi", "azw", "azw3", "prc", "pdf",
        )
        fun supported(name: String): Boolean {
            val dot = name.lastIndexOf('.')
            return dot >= 0 && extensions.contains(name.substring(dot + 1).lowercase())
        }
        fun limit(name: String): Long = MAX_ARCHIVE
    }
}

internal class BookPdfImport(
    @Suppress("unused") private val activity: Activity,
    @Suppress("unused") private val root: File,
) {
    fun read(input: BookDocumentInput): List<Map<String, Any?>> =
        listOf(mapOf("name" to "document", "error" to "此版本不能转换 PDF"))
}

internal class BookMarkupImport(
    @Suppress("unused") private val root: File,
    @Suppress("unused") private val readPdf: (BookDocumentInput) -> List<Map<String, Any?>>,
)

/** Folder scanning stays out of this build. File-picker import still works. */
internal class BookFolderScanner(private val activity: Activity) {
    fun canReadAll(): Boolean = false
    fun selectAll(): Map<String, Any?> = mapOf("available" to false)
    fun select(uri: Uri, flags: Int): Map<String, Any?> =
        mapOf("available" to false, "message" to "此版本不能扫描文件夹")
    fun info(): Map<String, Any?> = mapOf("connected" to false, "available" to false)
    fun setAutomatic(value: Boolean) {}
    fun disconnect() {}
    fun scan(): Map<String, Any?> = mapOf(
        "books" to emptyList<Any>(),
        "total" to 0,
        "unchanged" to 0,
        "warnings" to listOf("此版本不能扫描文件夹"),
    )
    fun formats(): Set<String> = emptySet()
    fun setFormats(extensions: List<String>) {}
    fun stage(
        token: String,
        root: File,
        copy: (Uri, File, Long) -> Unit,
    ): Map<String, Any?> = mapOf("name" to token, "error" to "此版本不能扫描文件夹")
    fun link(
        token: String,
        links: BookTextLinks,
        root: File,
        copy: (Uri, File, Long) -> Unit,
    ): Map<String, Any?> = mapOf("name" to token, "error" to "此版本不能扫描文件夹")
    fun markImported(token: String) {}
    fun finish() {}
}

private class UnavailablePlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}

class ListeningEnhancementPlugin : FlutterPlugin by UnavailablePlugin()
class LanReadingConfigPlugin : FlutterPlugin by UnavailablePlugin()
class LanDiscoveryPlugin : FlutterPlugin by UnavailablePlugin()
class CustomSpeechConfigPlugin : FlutterPlugin by UnavailablePlugin()
