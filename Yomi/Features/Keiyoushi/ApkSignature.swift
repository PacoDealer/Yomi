import CryptoKit
import Foundation
import Security

/// Checks an Android package's v2/v3 signature the way Android does before installing it, and names who signed it
/// (S193, KNOWN_ISSUES #227). Keiyoushi APKs run in Yomi's JVM, so an APK swapped on a compromised repository or a
/// tampered download must not load. The result is the SHA-256 of the signer's certificate — the same fingerprint
/// Mihon repositories publish (`repo.json` → `signingKeyFingerprint`) — which `KeiyoushiRepository` pins per extension.
///
/// What is checked (APK Signature Scheme v2/v3, source.android.com/docs/security/features/apksigning/v2):
/// 1. the signer's signature over its signed data, with the public key of its certificate;
/// 2. the signed digest of the whole file (entries, central directory, end record) against the bytes we got.
/// A copied certificate alone is worth nothing without 1 and 2. Only v1 (JAR) signed APKs are refused — Keiyoushi's
/// are v2+. Foundation + Security only: scripts/apk-signature-tests compiles it on macOS.
nonisolated enum ApkSignature {
    enum Failure: Error, Equatable {
        case notAZip, unsigned, malformed, unsupportedAlgorithm, badSignature, digestMismatch
    }

    private static let v2BlockId: UInt32 = 0x7109_871a
    private static let v3BlockId: UInt32 = 0xf053_68c0
    private static let chunkSize = 1 << 20

    /// Verifies `apk` and returns the lowercase hex SHA-256 of its signing certificate.
    static func verify(_ apk: Data) throws -> String {
        let bytes = [UInt8](apk)
        let (zip, blocks) = try signingBlocks(bytes, directory: try zipLayout(bytes))
        // v3 when present (it is what Android 9+ checks), otherwise v2.
        guard let value = blocks[v3BlockId] ?? blocks[v2BlockId] else { throw Failure.unsigned }
        let isV3 = blocks[v3BlockId] != nil

        var block = Reader(value)
        var signers = try block.lengthPrefixed()
        var fingerprints: Set<String> = []
        while !signers.atEnd {
            fingerprints.insert(try verifySigner(try signers.lengthPrefixed(), isV3: isV3, bytes: bytes, zip: zip))
        }
        // Keiyoushi signs with one key. Several signers (rare, key rotation tooling) aren't handled: refuse.
        guard fingerprints.count == 1, let fingerprint = fingerprints.first else { throw Failure.malformed }
        return fingerprint
    }

    // MARK: Signer

    private struct Algorithm {
        let secKey: SecKeyAlgorithm
        let digestIsSHA512: Bool
        let strength: Int
    }

    private static func algorithm(_ id: UInt32) -> Algorithm? {
        switch id {
        case 0x0101: return Algorithm(secKey: .rsaSignatureMessagePSSSHA256, digestIsSHA512: false, strength: 2)
        case 0x0102: return Algorithm(secKey: .rsaSignatureMessagePSSSHA512, digestIsSHA512: true, strength: 4)
        case 0x0103: return Algorithm(secKey: .rsaSignatureMessagePKCS1v15SHA256, digestIsSHA512: false, strength: 1)
        case 0x0104: return Algorithm(secKey: .rsaSignatureMessagePKCS1v15SHA512, digestIsSHA512: true, strength: 3)
        case 0x0201: return Algorithm(secKey: .ecdsaSignatureMessageX962SHA256, digestIsSHA512: false, strength: 1)
        case 0x0202: return Algorithm(secKey: .ecdsaSignatureMessageX962SHA512, digestIsSHA512: true, strength: 3)
        default: return nil   // DSA and the verity variants
        }
    }

    private static func verifySigner(_ signer: Reader, isV3: Bool, bytes: [UInt8], zip: ZipLayout) throws -> String {
        var signer = signer
        let signedDataReader = try signer.lengthPrefixed()
        let signedData = Data(signedDataReader.remaining)
        if isV3 { _ = try signer.u32(); _ = try signer.u32() }   // minSdk, maxSdk
        var signatures = try signer.lengthPrefixed()
        let publicKeyInfo = try signer.lengthPrefixed().remaining

        // The strongest signature we can check.
        var best: (id: UInt32, algorithm: Algorithm, signature: [UInt8])?
        while !signatures.atEnd {
            var entry = try signatures.lengthPrefixed()
            let id = try entry.u32()
            let signature = try entry.lengthPrefixed().remaining
            if let algorithm = algorithm(id), algorithm.strength > (best?.algorithm.strength ?? 0) {
                best = (id, algorithm, Array(signature))
            }
        }
        guard let best else { throw Failure.unsupportedAlgorithm }

        var data = signedDataReader
        var digests = try data.lengthPrefixed()
        var certificates = try data.lengthPrefixed()
        guard !certificates.atEnd else { throw Failure.malformed }
        let certificate = Data(try certificates.lengthPrefixed().remaining)

        // 1. The signature, with the certificate's key — and that key must be the one the signer declares.
        guard let cert = SecCertificateCreateWithData(nil, certificate as CFData),
              let key = SecCertificateCopyKey(cert),
              let raw = SecKeyCopyExternalRepresentation(key, nil) as Data? else { throw Failure.malformed }
        guard publicKeyInfo.count >= raw.count, Data(publicKeyInfo.suffix(raw.count)) == raw else {
            throw Failure.badSignature
        }
        guard SecKeyVerifySignature(key, best.algorithm.secKey, signedData as CFData,
                                    Data(best.signature) as CFData, nil) else { throw Failure.badSignature }

        // 2. The signed digest of the file, for the same algorithm.
        var expected: [UInt8]?
        while !digests.atEnd {
            var entry = try digests.lengthPrefixed()
            let id = try entry.u32()
            let digest = try entry.lengthPrefixed().remaining
            if id == best.id { expected = Array(digest) }
        }
        guard let expected else { throw Failure.malformed }
        guard contentDigest(bytes, zip: zip, sha512: best.algorithm.digestIsSHA512) == expected else {
            throw Failure.digestMismatch
        }
        return SHA256.hash(data: certificate).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Content digest

    /// Android's chunked digest over the entries, the central directory and the end record (with its directory
    /// offset pointed at the signing block, as when the file was signed).
    static func contentDigest(_ bytes: [UInt8], zip: ZipLayout, sha512: Bool) -> [UInt8] {
        var end = Array(bytes[zip.eocdOffset...])
        let blockStart = UInt32(zip.signingBlockOffset)
        for i in 0..<4 { end[16 + i] = UInt8((blockStart >> (8 * UInt32(i))) & 0xff) }
        let sections: [ArraySlice<UInt8>] = [bytes[0..<zip.signingBlockOffset],
                                             bytes[zip.centralDirectoryOffset..<zip.eocdOffset], end[...]]
        func hash(_ parts: [ArraySlice<UInt8>]) -> [UInt8] {
            if sha512 {
                var h = SHA512(); parts.forEach { h.update(data: Data($0)) }; return Array(h.finalize())
            }
            var h = SHA256(); parts.forEach { h.update(data: Data($0)) }; return Array(h.finalize())
        }
        func le32(_ v: Int) -> ArraySlice<UInt8> { ArraySlice((0..<4).map { UInt8((v >> (8 * $0)) & 0xff) }) }
        var chunkDigests: [UInt8] = []
        var count = 0
        for section in sections {
            var start = section.startIndex
            while start < section.endIndex {
                let stop = min(start + chunkSize, section.endIndex)
                chunkDigests += hash([[0xa5], le32(stop - start), section[start..<stop]])
                count += 1
                start = stop
            }
        }
        return hash([[0x5a], le32(count), chunkDigests[...]])
    }

    // MARK: Zip + signing block

    struct ZipLayout {
        let signingBlockOffset: Int
        let centralDirectoryOffset: Int
        let eocdOffset: Int
    }

    /// Where the central directory and the end record are (the signing block isn't located yet).
    private static func zipLayout(_ b: [UInt8]) throws -> (centralDirectory: Int, eocd: Int) {
        guard b.count >= 22, b[0] == 0x50, b[1] == 0x4b else { throw Failure.notAZip }
        // The end record is the last 22 bytes plus a comment of up to 64 KB.
        var eocd: Int?
        var i = b.count - 22
        while i >= max(0, b.count - 22 - 0xffff) {
            if le(b, i, 4) == 0x0605_4b50, le(b, i + 20, 2) == b.count - i - 22 { eocd = i; break }
            i -= 1
        }
        guard let eocd else { throw Failure.notAZip }
        let cdSize = le(b, eocd + 12, 4), cdOffset = le(b, eocd + 16, 4)
        guard cdOffset + cdSize == eocd, cdOffset >= 32 else { throw Failure.unsigned }   // also zip64: not an APK
        return (cdOffset, eocd)
    }

    /// The APK Signing Block that sits right before the central directory: id → value.
    private static func signingBlocks(_ b: [UInt8], directory: (centralDirectory: Int, eocd: Int)) throws
        -> (ZipLayout, [UInt32: ArraySlice<UInt8>]) {
        let cd = directory.centralDirectory
        guard Array(b[(cd - 16)..<cd]) == Array("APK Sig Block 42".utf8) else { throw Failure.unsigned }
        let sizeInFooter = le(b, cd - 24, 8)
        let start = cd - sizeInFooter - 8
        guard sizeInFooter >= 24, start >= 0, le(b, start, 8) == sizeInFooter else { throw Failure.malformed }
        var blocks: [UInt32: ArraySlice<UInt8>] = [:]
        var p = start + 8
        let pairsEnd = cd - 24
        while p < pairsEnd {
            guard p + 12 <= pairsEnd else { throw Failure.malformed }
            let length = le(b, p, 8)
            guard length >= 4, p + 8 + length <= pairsEnd else { throw Failure.malformed }
            blocks[UInt32(le(b, p + 8, 4))] = b[(p + 12)..<(p + 8 + length)]
            p += 8 + length
        }
        return (ZipLayout(signingBlockOffset: start, centralDirectoryOffset: cd, eocdOffset: directory.eocd), blocks)
    }

    /// Little-endian unsigned integer of `width` bytes; Int is enough for any file this app downloads.
    private static func le(_ b: [UInt8], _ at: Int, _ width: Int) -> Int {
        guard at >= 0, at + width <= b.count else { return -1 }
        var v = 0
        for k in 0..<width { v |= Int(b[at + k]) << (8 * k) }
        return width == 8 && v < 0 ? -1 : v
    }

    /// Reads the u32-length-prefixed structures the signing block is made of, with bounds checks everywhere.
    struct Reader {
        private(set) var remaining: ArraySlice<UInt8>
        init(_ data: ArraySlice<UInt8>) { remaining = data }
        var atEnd: Bool { remaining.isEmpty }

        mutating func u32() throws -> UInt32 {
            guard remaining.count >= 4 else { throw Failure.malformed }
            let s = remaining.startIndex
            let v = (0..<4).reduce(UInt32(0)) { $0 | UInt32(remaining[s + $1]) << (8 * UInt32($1)) }
            remaining = remaining.dropFirst(4)
            return v
        }

        mutating func lengthPrefixed() throws -> Reader {
            let length = Int(try u32())
            guard length <= remaining.count else { throw Failure.malformed }
            let inner = remaining.prefix(length)
            remaining = remaining.dropFirst(length)
            return Reader(inner)
        }
    }
}
