package com.FAE.ScepTRONIC

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.reactivex.exceptions.UndeliverableException
import io.reactivex.plugins.RxJavaPlugins
import java.io.IOException

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        installRxBleErrorHandler()
        super.onCreate(savedInstanceState)
    }

    private fun installRxBleErrorHandler() {
        if (rxErrorHandlerInstalled) {
            return
        }
        rxErrorHandlerInstalled = true
        RxJavaPlugins.setErrorHandler { throwable ->
            val cause: Throwable = when (throwable) {
                is UndeliverableException -> throwable.cause ?: throwable
                else -> throwable
            }
            val causeClassName = cause.javaClass.name
            when (cause) {
                is IOException,
                is InterruptedException -> Unit
                else -> if (causeClassName == "com.polidea.rxandroidble2.exceptions.BleDisconnectedException") {
                    Unit
                } else {
                    Thread.currentThread().uncaughtExceptionHandler
                        ?.uncaughtException(Thread.currentThread(), cause)
                }
            }
        }
    }

    companion object {
        @Volatile
        private var rxErrorHandlerInstalled = false
    }
}
