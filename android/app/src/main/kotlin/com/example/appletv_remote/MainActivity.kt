package com.example.appletv_remote

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bridges the Flutter UI to the embedded Python `pyatv` backend (atv_bridge.py)
 * via Chaquopy. All Python calls are blocking, so they run on [Dispatchers.IO].
 *
 * A WifiManager.MulticastLock is held for the duration of mDNS scans so that
 * pyatv's Zeroconf discovery receives multicast replies on Android.
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "com.example.appletv_remote/pyatv"
        const val SCAN_TIMEOUT_S = 5
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var wifiManager: WifiManager
    private var pyModule: PyObject? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
        val py = Python.getInstance()
        pyModule = py.getModule("atv_bridge")
        // Point the Python bridge at the app-private files dir (FileStorage lives there).
        pyModule?.callAttr("set_files_dir", filesDir.absolutePath)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result -> handleCall(call, result) }
        // Python -> Java -> Dart event forwarding (connection lost / reconnecting / connected).
        pyModule?.callAttr("set_event_callback", EventForwarder(channel))
    }

    // ------------------------------------------------------------------ calls

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scan" -> scope.launch(Dispatchers.IO) {
                val lock = acquireMulticastLock()
                try {
                    val response = pyCall("scan_devices", call.argument<Int>("timeout") ?: SCAN_TIMEOUT_S)
                    deliver(result, parseJson(response))
                } catch (e: Exception) {
                    deliver(result, errorMap(e))
                } finally {
                    releaseMulticastLock(lock)
                }
            }

            "startPairing" -> runPython(result) {
                pyCall("start_pairing", call.argument<String>("identifier"))
            }

            "finishPairing" -> runPython(result) {
                pyCall("finish_pairing", call.argument<String>("pin"))
            }

            "cancelPairing" -> runPython(result) {
                pyCall("cancel_pairing")
            }

            "connect" -> runPython(result) {
                pyCall("connect_device", call.argument<String>("identifier"))
            }

            "disconnect" -> runPython(result) {
                pyCall("disconnect")
            }

            "sendCommand" -> runPython(result) {
                pyCall("send_command", call.argument<String>("cmd"))
            }

            "sendText" -> runPython(result) {
                pyCall("send_text", call.argument<String>("text"))
            }

            "hasCredentials" -> runPython(result) {
                pyCall("has_credentials", call.argument<String>("identifier"))
            }

            "unpair" -> runPython(result) {
                pyCall("remove_credentials", call.argument<String>("identifier"))
            }

            "getState" -> runPython(result) {
                pyCall("get_state")
            }

            else -> result.notImplemented()
        }
    }

    /** Runs a blocking Python call on [Dispatchers.IO] and replies on the main thread. */
    private fun runPython(result: MethodChannel.Result, block: () -> String) {
        scope.launch(Dispatchers.IO) {
            val payload = try {
                parseJson(block())
            } catch (e: Exception) {
                errorMap(e)
            }
            withContext(Dispatchers.Main) { result.success(payload) }
        }
    }

    private fun pyCall(function: String, vararg args: Any?): String {
        val module = pyModule ?: throw IllegalStateException("Python module not initialized")
        val pyArgs = args.filterNotNull().toTypedArray()
        return module.callAttr(function, *pyArgs).toString()
    }

    // ------------------------------------------------------------- multicast

    private fun acquireMulticastLock(): WifiManager.MulticastLock {
        synchronized(this) {
            if (multicastLock == null) {
                multicastLock = wifiManager.createMulticastLock("pyatv_mdns").apply {
                    setReferenceCounted(true)
                }
            }
            multicastLock!!.acquire()
            return multicastLock!!
        }
    }

    private fun releaseMulticastLock(lock: WifiManager.MulticastLock) {
        synchronized(this) {
            if (lock.isHeld) lock.release()
        }
    }

    // ----------------------------------------------------------------- json

    private fun parseJson(response: String): Map<String, Any?> =
        try {
            @Suppress("UNCHECKED_CAST")
            jsonToJava(JSONObject(response)) as Map<String, Any?>
        } catch (e: Exception) {
            mapOf("ok" to false, "error" to "Invalid bridge response: ${e.message}")
        }

    private fun errorMap(e: Exception): Map<String, Any?> =
        mapOf("ok" to false, "error" to (e.message ?: e.toString()))

    /** [MethodChannel.Result] may only be used on the main thread. */
    private fun deliver(result: MethodChannel.Result, payload: Map<String, Any?>) {
        scope.launch(Dispatchers.Main) { result.success(payload) }
    }

    private fun jsonToJava(value: Any?): Any? = when (value) {
        null -> null
        is JSONObject -> value.keys().asSequence().associateWith { key -> jsonToJava(value.get(key)) }
        is JSONArray -> (0 until value.length()).map { jsonToJava(value.get(it)) }
        is String, is Boolean, is Int, is Long, is Double -> value
        else -> value.toString()
    }

    override fun onDestroy() {
        scope.launch(Dispatchers.IO) {
            runCatching { pyModule?.callAttr("shutdown") }
        }
        synchronized(this) {
            multicastLock?.let { if (it.isHeld) it.release() }
            multicastLock = null
        }
        super.onDestroy()
    }
}

/** Called from Python (Chaquopy) on a Python thread; hops to the main thread for Flutter. */
class EventForwarder(private val channel: MethodChannel) {
    private val handler = Handler(Looper.getMainLooper())

    fun onEvent(json: String) {
        handler.post { channel.invokeMethod("onEvent", json) }
    }
}
