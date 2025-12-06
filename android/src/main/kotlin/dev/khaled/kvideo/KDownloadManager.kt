package dev.khaled.kvideo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadManager
import androidx.media3.exoplayer.offline.DownloadNotificationHelper
import androidx.media3.exoplayer.offline.DownloadRequest
import androidx.media3.exoplayer.offline.DownloadService
import androidx.media3.exoplayer.scheduler.PlatformScheduler
import androidx.media3.exoplayer.scheduler.Scheduler
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

@OptIn(UnstableApi::class)
class KDownloadManager(
    val context: Context, binaryMessenger: BinaryMessenger
) : DownloadManagerApi, DownloadManager.Listener {
    private val listener = DownloadEventListener(binaryMessenger)

    init {
        DownloadManagerUtil.getDownloadManager(context).addListener(this)
    }

    /// Event Listener
    override fun onDownloadChanged(
        downloadManager: DownloadManager, download: Download, finalException: Exception?
    ) {
        super.onDownloadChanged(downloadManager, download, finalException)
        when (download.state) {
            Download.STATE_DOWNLOADING -> {
                CoroutineScope(Dispatchers.IO).launch {
                    trackDownloadProgress(download).collect {
                        if (it == null) return@collect
                        withContext(Dispatchers.Main) {
                            listener.onProgress(
                                download.request.id, it.toLong()
                            ) {}
                        }
                    }
                }
            }

            Download.STATE_COMPLETED -> {
                listener.onCompletion(download.request.id, download.request.uri.toString()) {}
            }

            Download.STATE_FAILED -> {
                listener.onError(
                    download.request.id, finalException?.localizedMessage ?: "Unknown error"
                ) {}
            }

            Download.STATE_REMOVING -> {
                listener.onRemoved(download.request.id) {}
            }

            Download.STATE_QUEUED, Download.STATE_RESTARTING -> {
                listener.onProgress(download.request.id, 0) {}
            }

            Download.STATE_STOPPED -> {
                listener.onProgress(download.request.id, -1) {}
            }
        }
    }

    @kotlin.OptIn(DelicateCoroutinesApi::class)
    fun trackDownloadProgress(download: Download): Flow<Float?> {
        var percent: Float? = download.percentDownloaded
        return callbackFlow {
            while (percent != null && !isClosedForSend) {
                val downloads = DownloadManagerUtil.getDownloadManager(context).currentDownloads
                if (!downloads.contains(download)) close()
                percent = download.percentDownloaded
                if (trySend(percent).isSuccess) withContext(Dispatchers.IO) { delay(2000) }
            }
        }
    }

    override fun setAndroidDataSourceHeaders(headers: Map<String, String>) {
        DownloadManagerUtil.dataSourceHeaders.putAll(headers)
    }

    override fun download(media: Media, customId: String?): String {
        val id =  customId ?: UUID.randomUUID().toString()
        val request = DownloadRequest.Builder(id, media.url.toUri())
            .build()

        // TODO DRM
        DownloadService.sendAddDownload(
            context, KDownloadService::class.java, request, false
        )

        return id
    }

    override fun remove(id: String, callback: (Result<Unit>) -> Unit) {
        DownloadService.sendRemoveDownload(
            context, KDownloadService::class.java, id, false
        )
        callback(Result.success(Unit))
    }

    override fun removeAll(callback: (Result<Unit>) -> Unit) {
        DownloadService.sendRemoveAllDownloads(context, KDownloadService::class.java, false)
        callback(Result.success(Unit))
    }

    override fun getStatusFor(id: String, callback: (Result<DownloadData?>) -> Unit) {
        val download = DownloadManagerUtil.getDownloadManager(context).downloadIndex.getDownload(id)
            ?: return callback(Result.success(null))

        if (download.state == Download.STATE_REMOVING) return callback(Result.success(null))

        val status: DownloadStatus = when (download.state) {
            Download.STATE_DOWNLOADING -> DownloadStatus.DOWNLOADING
            Download.STATE_COMPLETED -> DownloadStatus.FINISHED
            Download.STATE_FAILED -> DownloadStatus.ERROR
            Download.STATE_STOPPED -> DownloadStatus.ERROR
            else -> DownloadStatus.WAITING
        }


        return callback(
            Result.success(
                DownloadData(
                    id = download.request.id,
                    progress = download.percentDownloaded.toLong(),
                    originUri = download.request.uri.toString(),
                    localUri = download.request.uri.toString(),
                    error = if (status == DownloadStatus.ERROR) download.failureReason.toString() else null,
                    status = status
                )
            )
        )
    }

    override fun getAllDownloads(callback: (Result<List<String>>) -> Unit) {
        val cursor = DownloadManagerUtil.getDownloadManager(context).downloadIndex.getDownloads()
        val downloadIds = mutableListOf<String>()

        while (cursor.moveToNext()) {
            if (cursor.download.state == Download.STATE_REMOVING) continue
            downloadIds.add(cursor.download.request.id)
        }

        cursor.close()
        return callback(Result.success(downloadIds))
    }

    companion object {
        fun cache(context: Context): SimpleCache {
            if (DownloadManagerUtil.cache == null) DownloadManagerUtil.getDownloadManager(context)
            return DownloadManagerUtil.cache!!
        }
    }
}


@UnstableApi
class KDownloadService : DownloadService(
    DownloadManagerUtil.FOREGROUND_NOTIFICATION_ID,
) {
    override fun getDownloadManager(): DownloadManager {
        return DownloadManagerUtil.getDownloadManager(this)
    }

    override fun getScheduler(): Scheduler = PlatformScheduler(
        this, DownloadManagerUtil.JOB_ID
    )

    override fun getForegroundNotification(
        downloads: MutableList<Download>, notMetRequirements: Int
    ): Notification {
        return DownloadManagerUtil.getDownloadNotificationHelper(this).buildProgressNotification(
            this@KDownloadService,
            android.R.drawable.stat_sys_download,
            null,
            null,
            downloads,
            notMetRequirements
        )
    }
}


@UnstableApi
private object DownloadManagerUtil {
    const val DOWNLOAD_NOTIFICATION_CHANNEL_ID: String = "download_channel"
    const val FOREGROUND_NOTIFICATION_ID = 69
    const val JOB_ID = 69

    private var downloadManager: DownloadManager? = null
    private var notificationHelper: DownloadNotificationHelper? = null
    private val httpDataSourceFactory = DefaultHttpDataSource.Factory()

    val dataSourceHeaders = mutableMapOf<String, String>()

    private val resolver = ResolvingDataSource.Resolver { dataSpec ->
        dataSpec.withAdditionalHeaders(dataSourceHeaders)
    }

    var cache: SimpleCache? = null

    fun getDownloadManager(context: Context): DownloadManager {
        if (downloadManager == null) {
            val db = StandaloneDatabaseProvider(context)
            cache = SimpleCache(File(context.filesDir, "kvideo_downloads"), NoOpCacheEvictor(), db)
            downloadManager = DownloadManager(
                context, db, cache!!, ResolvingDataSource.Factory(
                    httpDataSourceFactory, resolver
                ), Executors.newFixedThreadPool(6)
            )
        }

        return downloadManager!!
    }

    fun getDownloadNotificationHelper(
        context: Context
    ): DownloadNotificationHelper {
        if (notificationHelper == null) {
            // Create Notification Channel
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    DOWNLOAD_NOTIFICATION_CHANNEL_ID,
                    "Downloads",
                    NotificationManager.IMPORTANCE_LOW
                )
                val manager = context.getSystemService(NotificationManager::class.java)
                manager.createNotificationChannel(channel)
            }

            notificationHelper = DownloadNotificationHelper(
                context, DOWNLOAD_NOTIFICATION_CHANNEL_ID
            )
        }

        return notificationHelper!!
    }
}
