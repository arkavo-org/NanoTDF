import CryptoKit
import Foundation

struct NanoTDF {
    let header: Header
    let payload: Payload
}

struct Header {
    let magicNumber: Data
    let version: Data
    let kas: ResourceLocator
    let eccMode: ECCAndBindingMode
    let payloadSigMode: SymmetricAndPayloadConfig
    let policy: Policy
    let ephemeralKey: Data
}

struct Payload {
    let length: UInt32
    let iv: Data
    let ciphertext: Data
    let payloadMAC: Data
}

struct ECCAndBindingMode {
    var useECDSABinding: Bool
    var ephemeralECCParamsEnum: ECDSAParams
}

struct SymmetricAndPayloadConfig {
    let hasSignature: Bool
    let signatureECCMode: ECDSAParams?
    let symmetricCipherEnum: SymmetricCiphers?
}

enum ProtocolEnum: UInt8, Codable {
    case http = 0x00
    case https = 0x01
    case unreserved = 0x02
    case sharedResourceDirectory = 0xFF
}

struct ResourceLocator: Codable {
    let protocolEnum: ProtocolEnum
    let body: String
    func toData() -> Data {
        var data = Data()
        data.append(protocolEnum.rawValue)
        if let bodyData = body.data(using: .utf8) {
            data.append(UInt8(bodyData.count))
            data.append(bodyData)
        }
        return data
    }
}

struct Policy {
    enum PolicyType {
        case remote
        case embedded
    }

    let type: PolicyType
    let body: Data?
    let remote: ResourceLocator?
    let binding: Data?
}

struct EmbeddedPolicyBody {
    let contentLength: UInt16
    let plaintextCiphertext: Data?
    let policyKeyAccess: Data?
}

enum ECDSAParams: UInt8 {
    case secp256r1 = 0x00
    case secp384r1 = 0x01
    case secp521r1 = 0x02
    case secp256k1 = 0x03
}

enum SymmetricCiphers: UInt8 {
    case GCM_64 = 0x00
    case GCM_96 = 0x01
    case GCM_104 = 0x02
    case GCM_112 = 0x03
    case GCM_120 = 0x04
    case GCM_128 = 0x05
}

class BinaryParser {
    var data: Data
    var cursor: Int = 0

    init(data: Data) {
        self.data = data
    }

    func read(length: Int) -> Data? {
        print("Length: \(length)")
        guard cursor + length <= data.count else { return nil }
        let range = cursor ..< (cursor + length)
        cursor += length
        return data.subdata(in: range)
    }

    private func readResourceLocator() -> ResourceLocator? {
        guard let protocolData = read(length: 1),
              let protocolEnum = protocolData.first,
              let protocolEnumValue = ProtocolEnum(rawValue: protocolEnum),
              let bodyLengthData = read(length: 1),
              let bodyLength = bodyLengthData.first,
              let body = read(length: Int(bodyLength)),
              let bodyString = String(data: body, encoding: .utf8)
        else {
            return nil
        }
        let protocolHex = String(format: "%02x", protocolEnum)
        print("Protocol Hex:", protocolHex)
        let bodyLengthlHex = String(format: "%02x", bodyLength)
        print("Body Length Hex:", bodyLengthlHex)
        let bodyHexString = body.map { String(format: "%02x", $0) }.joined(separator: " ")
        print("Body Hex:", bodyHexString)
        print("bodyString: \(bodyString)")
        return ResourceLocator(protocolEnum: protocolEnumValue, body: bodyString)
    }

    private func readPolicyField() -> Policy? {
        print("readPolicyField")
        guard let typeEnum = read(length: 1),
              let type = typeEnum.first
        else {
            print("Failed to read Type Enum")
            return nil
        }

        switch type {
        case 0x00:
            // Remote Policy
            print("Remote Policy")
            guard let resourceLocator = readResourceLocator() else {
                print("Failed to read Remote Policy resource locator")
                return nil
            }
            // Binding
            guard let binding = readPolicyBinding() else {
                print("Failed to read Remote Policy binding")
                return nil
            }
            return Policy(type: .remote, body: nil, remote: resourceLocator, binding: binding)

        case 0x01, 0x02, 0x03:
            // Embedded Policy (Plaintext or Encrypted)
            let policyData = readEmbeddedPolicyBody()
            // Binding
            guard let binding = readPolicyBinding() else {
                print("Failed to read Remote Policy binding")
                return nil
            }
            return Policy(type: .embedded, body: policyData?.plaintextCiphertext, remote: nil, binding: binding)
        default:
            print("Unknown Policy Type Enum value")
            return nil
        }
    }

    private func readEmbeddedPolicyBody() -> EmbeddedPolicyBody? {
        print("readEmbeddedPolicyBody")
        guard let contentLengthData = read(length: 2)
        else {
            print("Failed to read Embedded Policy content length")
            return nil
        }
        let plaintextCiphertextLengthData = contentLengthData.prefix(2) // contentLengthData.first

        let contentLength = plaintextCiphertextLengthData.withUnsafeBytes {
            $0.load(as: UInt16.self)
        }
        print("Policy Body Length: \(contentLength)")

        // if no policy added then no read
        // Note 3.4.2.3.2 Body for Embedded Policy states Minimum Length is 1
        if contentLength == 0 {
            return EmbeddedPolicyBody(contentLength: contentLength, plaintextCiphertext: nil, policyKeyAccess: nil)
        }

        guard let plaintextCiphertext = read(length: Int(contentLength)) else {
            print("Failed to read Embedded Policy plaintext / ciphertext")
            return nil
        }

        var policyKeyAccess: Data?
        if cursor < data.count {
            policyKeyAccess = read(length: data.count - cursor)
        }

        return EmbeddedPolicyBody(contentLength: contentLength, plaintextCiphertext: plaintextCiphertext, policyKeyAccess: policyKeyAccess)
    }

    func readEccAndBindingMode() -> ECCAndBindingMode? {
        print("readEccAndBindingMode")
        guard let eccAndBindingModeData = read(length: 1),
              let eccAndBindingMode = eccAndBindingModeData.first
        else {
            print("Failed to read BindingMode")
            return nil
        }
        let eccModeHex = String(format: "%02x", eccAndBindingMode)
        print("ECC Mode Hex:", eccModeHex)
        let useECDSABinding = (eccAndBindingMode & (1 << 7)) != 0
        let ephemeralECCParamsEnumValue = ECDSAParams(rawValue: eccAndBindingMode & 0x7)

        guard let ephemeralECCParamsEnum = ephemeralECCParamsEnumValue else {
            print("Unsupported Ephemeral ECC Params Enum value")
            return nil
        }

        print("useECDSABinding: \(useECDSABinding)")
        print("ephemeralECCParamsEnum: \(ephemeralECCParamsEnum)")

        return ECCAndBindingMode(useECDSABinding: useECDSABinding, ephemeralECCParamsEnum: ephemeralECCParamsEnum)
    }

    func readSymmetricAndPayloadConfig() -> SymmetricAndPayloadConfig? {
        print("readSymmetricAndPayloadConfig")
        guard let symmetricAndPayloadConfigData = read(length: 1),
              let symmetricAndPayloadConfig = symmetricAndPayloadConfigData.first
        else {
            print("Failed to read Symmetric and Payload Config")
            return nil
        }
        let symmetricAndPayloadConfigHex = String(format: "%02x", symmetricAndPayloadConfig)
        print("Symmetric And Payload Config Hex:", symmetricAndPayloadConfigHex)
        let hasSignature = (symmetricAndPayloadConfig & 0x80) >> 7 != 0
        let signatureECCModeEnum = ECDSAParams(rawValue: (symmetricAndPayloadConfig & 0x70) >> 4)
        let symmetricCipherEnum = SymmetricCiphers(rawValue: symmetricAndPayloadConfig & 0x0F)

        print("hasSignature: \(hasSignature)")
        print("signatureECCModeEnum: \(String(describing: signatureECCModeEnum))")
        print("symmetricCipherEnum: \(String(describing: symmetricCipherEnum))")

        return SymmetricAndPayloadConfig(hasSignature: hasSignature,
                                         signatureECCMode: signatureECCModeEnum,
                                         symmetricCipherEnum: symmetricCipherEnum)
    }

    func readPolicyBinding() -> Data? {
        // The length should be determined based on the ECC and Binding Mode described
        let bindingLength = determinePolicyBindingLength() // This function needs to be implemented based on ECC and Binding Mode
        return read(length: bindingLength)
    }

    private func determinePolicyBindingLength() -> Int {
        // This should return the correct length based on ECC and Binding Mode
        // Placeholder: returning a typical length for an ECDSA signature
        return 64 // Example length, adjust based on actual application requirements
    }

    func parseHeader() throws -> Header {
        guard let magicNumber = read(length: FieldSize.magicNumberSize),
              let version = read(length: FieldSize.versionSize),
              let kas = readResourceLocator(),
//              let eccMode = read(length: HeaderField.eccModeSize),
              let eccMode = readEccAndBindingMode(),
              let payloadSigMode = readSymmetricAndPayloadConfig(), // read(length: HeaderField.payloadSigModeSize),
              let policy = readPolicyField(),
              // Read length based on key type, FIXME reading min for now
              let ephemeralKey = read(length: FieldSize.minEphemeralKeySize)
        else {
            throw ParsingError.invalidFormat
        }

        return Header(magicNumber: magicNumber, version: version, kas: kas, eccMode: eccMode, payloadSigMode: payloadSigMode, policy: policy, ephemeralKey: ephemeralKey)
    }

    func parsePayload(data: Data) throws -> Payload {
        guard let lengthData = read(length: FieldSize.payloadCipherTextSize)
        else {
            throw ParsingError.invalidFormat
        }
        var length: UInt32 = 0
        let count = lengthData.count
        for i in 0..<count {
            length += UInt32(lengthData[i]) << (8 * (count - 1 - i))
        }
        guard let iv = read(length: FieldSize.payloadIvSize)
        else {
            throw ParsingError.invalidFormat
        }
        // FIXME calculate MAC size
        let cipherTextLength = Int(length) - FieldSize.minPayloadMacSize
        guard let ciphertext = read(length: cipherTextLength),
            let payloadMAC = read(length: FieldSize.minPayloadMacSize)
        else {
            throw ParsingError.invalidFormat
        }
        let payload = Payload(length: length, iv: iv, ciphertext: ciphertext, payloadMAC: payloadMAC)
        return payload
    }
}

// see https://github.com/opentdf/spec/tree/main/schema/nanotdf
enum FieldSize {
    static let magicNumberSize = 2
    static let versionSize = 1
    static let minKASSize = 3
    static let maxKASSize = 257
    static let eccModeSize = 1
    static let payloadSigModeSize = 1
    static let minPolicySize = 3
    static let maxPolicySize = 257
    static let minEphemeralKeySize = 33
    static let maxEphemeralKeySize = 133
    static let payloadCipherTextSize = 3
    static let payloadIvSize = 3
    static let minPayloadMacSize = 8
    static let maxPayloadMacSize = 32
}

enum ParsingError: Error {
    case invalidFormat
    case invalidMagicNumber
    case invalidVersion
    case invalidKAS
    case invalidECCMode
    case invalidPayloadSigMode
    case invalidPolicy
    case invalidEphemeralKey
    case invalidPayload
}
