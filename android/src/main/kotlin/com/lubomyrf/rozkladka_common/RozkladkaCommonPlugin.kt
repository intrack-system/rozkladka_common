package com.lubomyrf.rozkladka_common

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Ключ телефона ECDSA P-256 в Android Keystore: закрита частина не
 * експортується. Відбиток чи PIN на підписання застосунок питає сам, лише
 * коли людина це ввімкнула.
 */
class RozkladkaCommonPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "rozkladka_common/device_key")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        try {
            when (call.method) {
                "publicKey" -> result.success(keyStore().getCertificate(ALIAS)?.publicKey?.encoded ?: createKey())
                "sign" -> {
                    ensureKey()
                    val key = keyStore().getKey(ALIAS, null) as PrivateKey
                    val signature = Signature.getInstance("SHA256withECDSA")
                    signature.initSign(key)
                    signature.update(call.arguments as ByteArray)
                    result.success(signature.sign())
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("device_key", e.message, null)
        }
    }

    private fun keyStore() = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun ensureKey() {
        if (!keyStore().containsAlias(ALIAS)) createKey()
    }

    /** Створює ключ; StrongBox — де є, інакше звичайний апаратний Keystore. */
    private fun createKey(): ByteArray {
        fun generate(strongBox: Boolean): ByteArray {
            val spec =
                KeyGenParameterSpec
                    .Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setIsStrongBoxBacked(strongBox)
                    .build()
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE)
            generator.initialize(spec)
            return generator.generateKeyPair().public.encoded
        }
        return try {
            generate(strongBox = true)
        } catch (e: StrongBoxUnavailableException) {
            generate(strongBox = false)
        }
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "rozkladka_device_key"
    }
}
