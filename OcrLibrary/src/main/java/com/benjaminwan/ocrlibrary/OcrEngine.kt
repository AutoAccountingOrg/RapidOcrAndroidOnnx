package com.benjaminwan.ocrlibrary

import android.content.Context
import android.content.res.AssetManager
import android.graphics.Bitmap
import java.util.concurrent.atomic.AtomicBoolean

class OcrEngine(context: Context) : AutoCloseable {
    companion object {
        const val numThread: Int = 4
    }

    private val closed = AtomicBoolean(false)

    init {
        System.loadLibrary("RapidOcr")
        val ret = init(
            context.assets, numThread,
            "det.onnx",
            "cls.onnx",
            "rec.onnx",
            "ppocrv5_dict.txt"
        )
        if (!ret) throw IllegalArgumentException()
    }

    var padding: Int = 50
    var boxScoreThresh: Float = 0.5f
    var boxThresh: Float = 0.3f
    var unClipRatio: Float = 1.6f
    var doAngle: Boolean = true
    var mostAngle: Boolean = true

    fun detect(input: Bitmap, output: Bitmap, maxSideLen: Int) =
        detect(
            input, output, padding, maxSideLen,
            boxScoreThresh, boxThresh,
            unClipRatio, doAngle, mostAngle
        )

    external fun init(
        assetManager: AssetManager,
        numThread: Int, detName: String,
        clsName: String, recName: String, keysName: String
    ): Boolean

    external fun release(): Int

    external fun detect(
        input: Bitmap, output: Bitmap, padding: Int, maxSideLen: Int,
        boxScoreThresh: Float, boxThresh: Float,
        unClipRatio: Float, doAngle: Boolean, mostAngle: Boolean
    ): OcrResult

    external fun benchmark(input: Bitmap, loop: Int): Double

    override fun close() {
        if (closed.compareAndSet(false, true)) {
            release()
        }
    }

    fun closeAndRelease(): Int {
        close()
        return 0
    }

}