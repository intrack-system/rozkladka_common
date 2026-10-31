import Flutter
import Security
import UIKit

/// Ключ телефона ECDSA P-256 у Secure Enclave: закрита частина не
/// експортується. Відбиток чи PIN на підписання застосунок питає сам, лише
/// коли людина це ввімкнула.
public class RozkladkaCommonPlugin: NSObject, FlutterPlugin {
  private static let tag = "rozkladka_device_key".data(using: .utf8)!

  /// Префікс SubjectPublicKeyInfo DER для P-256; Secure Enclave віддає лише 04‖X‖Y.
  private static let spkiPrefix = Data([
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02,
    0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
    0x42, 0x00,
  ])

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "rozkladka_common/device_key", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(RozkladkaCommonPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "publicKey":
        result(FlutterStandardTypedData(bytes: try publicKey()))
      case "sign":
        let message = (call.arguments as! FlutterStandardTypedData).data
        result(FlutterStandardTypedData(bytes: try sign(message)))
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "device_key", message: "\(error)", details: nil))
    }
  }

  private func privateKey() throws -> SecKey {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: Self.tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess {
      return item as! SecKey
    }
    return try createKey()
  }

  /// Secure Enclave; на симуляторі його немає — звичайний ключ у Keychain.
  private func createKey() throws -> SecKey {
    var error: Unmanaged<CFError>?
    let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &error)!
    var attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: Self.tag,
        kSecAttrAccessControl as String: access,
      ],
    ]
    #if !targetEnvironment(simulator)
      attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
    #endif
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw error!.takeRetainedValue() as Error
    }
    return key
  }

  private func publicKey() throws -> Data {
    var error: Unmanaged<CFError>?
    guard let pub = SecKeyCopyPublicKey(try privateKey()),
      let point = SecKeyCopyExternalRepresentation(pub, &error) as Data?
    else {
      throw error?.takeRetainedValue() as Error? ?? NSError(domain: "device_key", code: 1)
    }
    return Self.spkiPrefix + point
  }

  /// Підпис SHA-256/ECDSA у DER (X9.62).
  private func sign(_ message: Data) throws -> Data {
    var error: Unmanaged<CFError>?
    guard
      let signature = SecKeyCreateSignature(
        try privateKey(), .ecdsaSignatureMessageX962SHA256, message as CFData, &error)
    else {
      throw error!.takeRetainedValue() as Error
    }
    return signature as Data
  }
}
