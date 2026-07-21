//
//  CrashRecordReader.swift
//  PantrixCrash
//
//  Parses the fixed-layout binary crash record (see PantrixCrashRecord.h) that the C engine writes at
//  crash time into the public `PantrixCrashReport`, mapping each frame address to its owning binary
//  image. Runs on the NEXT launch, off the crash path — so it may allocate freely. This is the reader
//  half of the record-format contract with the C writer.
//

import Foundation
import PantrixCore
import PantrixCrashC

enum CrashRecordReader {

    /// The OS build string (e.g. `21F79`) from `kern.osversion` — the key Apple system-symbol stores are
    /// organized by, and the label the crash UI shows for an iOS crash. Read here, at drain time on the
    /// next launch (off the crash path, so a plain sysctl is fine); it matches the crash's build in every
    /// case except an OS update between the crash and the drain. A crash-time capture would need a record
    /// field — deferred to the v4 format bump (see Docs/CRASH_REPORT_PARITY_PLAN.md, G2/A0).
    static let osBuildNumber: String? = {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buf, &size, nil, 0) == 0 else { return nil }
        let build = String(cString: buf)
        return build.isEmpty ? nil : build
    }()

    /// Parses `data` into a report, or nil if it isn't a well-formed record of the expected version.
    static func read(_ data: Data) -> PantrixCrashReport? {
        var cursor = Cursor(data)
        // Accept any known version (currently 1 and 2). v1 records carry no attribution trailer; v2 appends
        // the crash-time session + screen after the images block.
        guard cursor.u32() == PANTRIX_CRASH_MAGIC,
              let version = cursor.u16(), version >= 1, version <= UInt16(PANTRIX_CRASH_FORMAT_VERSION) else {
            return nil
        }
        guard let flags = cursor.u16(),
              cursor.u32() != nil,              // crash_type (implicit in type/signal below)
              let signum = cursor.i32(),
              cursor.i32() != nil,              // sigcode
              cursor.u64() != nil,              // fault_address
              let timestamp = cursor.u64(),
              cursor.u64() != nil,              // thread_id
              let frameCount = cursor.u32(),
              let imageCount = cursor.u32(),
              let typeLen = cursor.u16(),
              let nameLen = cursor.u16(),
              let reasonLen = cursor.u16(),
              let type = cursor.string(Int(typeLen)),
              let name = cursor.string(Int(nameLen)),
              let reason = cursor.string(Int(reasonLen)) else {
            return nil
        }

        // No reserveCapacity on the untrusted counts — a malformed frame_count/image_count of ~4e9 would
        // otherwise allocate gigabytes up front. The Cursor's bounds checks bail on a truncated record.
        var rawFrames: [UInt64] = []
        for _ in 0..<frameCount {
            guard let address = cursor.u64() else { return nil }
            rawFrames.append(address)
        }

        var images: [Image] = []
        for _ in 0..<imageCount {
            guard let load = cursor.u64(),
                  let size = cursor.u64(),
                  let uuid = cursor.take(16),
                  let pathLen = cursor.u16(),
                  let path = cursor.string(Int(pathLen)) else {
                return nil
            }
            images.append(Image(load: load, size: size, uuid: uuid, path: path))
        }

        // v2 trailer: crash-time session + screen (left nil for a v1 record). An empty staged string /
        // a negative time means "unset" → nil, so downstream falls back to the launch context.
        var sessionId: String?
        var screenId: String?
        var screenName: String?
        var screenType: String?
        var screenEnteredAt: String?
        var screenLoadTime: Int64?
        var screenDuration: Int64?
        if version >= 2 {
            guard let sessionLen = cursor.u16(),
                  let screenIdLen = cursor.u16(),
                  let screenNameLen = cursor.u16(),
                  let screenCategoryLen = cursor.u16(),
                  let enteredAtLen = cursor.u16(),
                  let loadTime = cursor.i64(),
                  let duration = cursor.i64(),
                  let session = cursor.string(Int(sessionLen)),
                  let scrId = cursor.string(Int(screenIdLen)),
                  let scrName = cursor.string(Int(screenNameLen)),
                  let scrCategory = cursor.string(Int(screenCategoryLen)),
                  let enteredAt = cursor.string(Int(enteredAtLen)) else {
                return nil
            }
            sessionId = session.isEmpty ? nil : session
            screenId = scrId.isEmpty ? nil : scrId
            screenName = scrName.isEmpty ? nil : scrName
            screenType = scrCategory.isEmpty ? nil : scrCategory
            screenEnteredAt = enteredAt.isEmpty ? nil : enteredAt
            screenLoadTime = loadTime < 0 ? nil : loadTime
            screenDuration = duration < 0 ? nil : duration
        }

        // v3 trailer: one { cputype, cpusubtype } per image, parallel to `images` and in RECORD order —
        // so it must be zipped in before anything sorts them. A v1/v2 record simply has no arch.
        if version >= 3 {
            for index in 0..<images.count {
                guard let cputype = cursor.i32(), let cpusubtype = cursor.i32() else { return nil }
                images[index].arch = arch(cputype: cputype, cpusubtype: cpusubtype)
            }
        }

        // v4 trailer: the OTHER live threads — { name, frames } each (the crashed thread is the header's
        // frames). Empty for a v1..v3 record. Read raw here; mapped to frames after the images are sorted.
        var rawThreads: [(name: String, frames: [UInt64])] = []
        if version >= 4 {
            guard let threadCount = cursor.u32() else { return nil }
            for _ in 0..<threadCount {
                guard let tnameLen = cursor.u16(),
                      let tname = cursor.string(Int(tnameLen)),
                      let tframeCount = cursor.u32() else { return nil }
                var tframes: [UInt64] = []
                for _ in 0..<tframeCount {
                    guard let address = cursor.u64() else { return nil }
                    tframes.append(address)
                }
                rawThreads.append((name: tname, frames: tframes))
            }
        }

        let sortedImages = images.sorted { $0.load < $1.load }
        let frames = rawFrames.map { mapFrame($0, in: sortedImages) }
        // Every OTHER thread's frames, mapped into the same sorted images.
        let threads = rawThreads.map { thread in
            PantrixCrashReport.Thread(
                name: thread.name.isEmpty ? nil : thread.name,
                frames: thread.frames.map { mapFrame($0, in: sortedImages) }
            )
        }
        // Only the images a frame actually landed in. A device has 500+ loaded and a stack touches a
        // handful; the rest are bytes the backend would never consult, because it resolves purely by the
        // load address the frame already carries. Sentry and Measure prune identically.
        // G1×G2: the union must span the crashed thread AND every sibling thread — else a system (or app)
        // image touched only by a sibling is pruned here and its frames can never symbolicate.
        let referenced = Set((frames + threads.flatMap(\.frames)).compactMap { $0.binaryAddress })
        let reportImages = sortedImages
            .filter { referenced.contains(hex($0.load)) }
            .map { image in
                PantrixCrashReport.DebugImage(
                    uuid: uuidString(image.uuid),
                    baseAddress: hex(image.load),
                    endAddress: hex(image.load &+ max(1, image.size)),
                    name: (image.path as NSString).lastPathComponent,
                    path: image.path,
                    system: !isAppImage(image.path),
                    arch: image.arch
                )
            }

        return PantrixCrashReport(
            type: type.isEmpty ? nil : type,
            signal: signalName(signum),
            message: reason.isEmpty ? nil : reason,
            threadName: name.isEmpty ? nil : name,
            frames: frames,
            threads: threads,
            images: reportImages,
            foreground: (flags & 1) != 0,
            osBuildNumber: Self.osBuildNumber,
            timestamp: Int64(bitPattern: timestamp),
            sessionId: sessionId,
            screenId: screenId,
            screenName: screenName,
            screenType: screenType,
            screenEnteredAt: screenEnteredAt,
            screenLoadTime: screenLoadTime,
            screenDuration: screenDuration
        )
    }

    // MARK: - Frame → image mapping

    private struct Image {
        let load: UInt64
        let size: UInt64
        /// The raw 16 bytes of `LC_UUID`, exactly as the C layer memcpy'd them out of the load command.
        let uuid: [UInt8]
        let path: String
        /// From the v3 trailer; nil for a v1/v2 record, which carries no arch.
        var arch: String?
    }

    private static func mapFrame(_ address: UInt64, in sortedImages: [Image]) -> PantrixCrashReport.Frame {
        var frame = PantrixCrashReport.Frame(instructionAddress: hex(address))
        if let image = imageContaining(address, sortedImages) {
            frame.binaryAddress = hex(image.load)
            frame.moduleName = (image.path as NSString).lastPathComponent
            frame.inApp = isAppImage(image.path)
        }
        return frame
    }

    /// The image whose `[load, load + size)` range contains `address` — the rightmost image with
    /// `load <= address`, confirmed to be within its size.
    private static func imageContaining(_ address: UInt64, _ sorted: [Image]) -> Image? {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid].load <= address { lo = mid + 1 } else { hi = mid }
        }
        let index = lo - 1
        guard index >= 0 else { return nil }
        let image = sorted[index]
        if image.size == 0 || address < image.load &+ image.size {
            return image
        }
        return nil
    }

    /// `CFBundleExecutable` — bir kez okunur. In-app tespitinin çapası: uygulamanın kendi binary adı.
    private static let appExecutableName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String

    /// In-app = uygulamanın KENDİ kodu (main executable + gömülü framework'ler); OS framework'leri değil.
    ///
    /// **Path-prefix DEĞİL, İSİM karşılaştırması.** Eski heuristik `!hasPrefix("/System/", "/usr/lib/")`
    /// idi ve simülatörde SESSİZCE yanılıyordu: dyld sistem framework'lerini runtime-root path'inde verir
    /// (`.../CoreSimulator/.../RuntimeRoot/usr/lib/swift/libswiftCore.dylib`), bu `/usr/lib/` ile
    /// BAŞLAMAZ, o yüzden `libswiftCore`/`CoreFoundation`/`UIKitCore` "app" sanılıyordu — ama tesadüfen
    /// canonical yolla gelen `libsystem_kernel` (`/usr/lib/system/...`) doğru çıkıyordu. İsim vs
    /// `CFBundleExecutable` cihazda ve simülatörde AYNI çalışır (CRASH_FINGERPRINT_SPEC §5, Measure
    /// `isAppBinary` paritesi). `.debug.dylib`: debug build'de app kodunun konduğu dylib; `contains`:
    /// app adıyla adlandırılmış gömülü framework'ler.
    private static func isAppImage(_ path: String) -> Bool {
        isAppImage(path, executableName: appExecutableName)
    }

    /// [isAppImage]'in test edilebilir çekirdeği — `Bundle.main`'e bağlı değil.
    static func isAppImage(_ path: String, executableName: String?) -> Bool {
        let short = (path as NSString).lastPathComponent
        guard let exec = executableName, !exec.isEmpty else { return false }
        return short == exec || short.hasSuffix(".debug.dylib") || short.contains(exec)
    }

    private static func signalName(_ signum: Int32) -> String? {
        switch signum {
        case SIGSEGV: return "SIGSEGV"
        case SIGABRT: return "SIGABRT"
        case SIGBUS: return "SIGBUS"
        case SIGILL: return "SIGILL"
        case SIGFPE: return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        default: return signum != 0 ? "SIGNAL" : nil
        }
    }

    private static func hex(_ value: UInt64) -> String {
        "0x" + String(value, radix: 16)
    }

    /// `cputype`/`cpusubtype` → the arch name. Kept in lockstep with `BinaryImageTable.arch(cputype:
    /// cpusubtype:)` — both crash paths must name one arch one way, because both land in one column.
    ///
    /// Builds-UI metadata, NOT a symbolication input: a dSYM is found by `LC_UUID` alone, and each slice
    /// carries its own, so slices are already distinct keys (D3 in Docs/CRASH_SYMBOLICATION_PLAN.md
    /// retracts the reason this was first captured for). Only the arches iOS 13+ can actually run are
    /// named; anything else returns nil rather than a guess.
    private static func arch(cputype: Int32, cpusubtype: Int32) -> String? {
        // The subtype's high bits are capability flags (CPU_SUBTYPE_MASK), not part of the identity.
        let subtype = cpusubtype & ~Int32(bitPattern: UInt32(CPU_SUBTYPE_MASK))
        switch cputype {
        case CPU_TYPE_ARM64:
            switch subtype {
            case CPU_SUBTYPE_ARM64E: return "arm64e"
            case CPU_SUBTYPE_ARM64_ALL, CPU_SUBTYPE_ARM64_V8: return "arm64"
            default: return "arm64"
            }
        case CPU_TYPE_X86_64: return "x86_64"   // the Simulator
        default: return nil
        }
    }

    /// Dashless lowercase hex, the form every reference SDK sends and every dSYM index is keyed by
    /// (Sentry's `debug_id`, Measure's `uuid`). Built by hand rather than via `UUID` so the 16 raw bytes
    /// go straight to a string with no intermediate type to get the byte order wrong.
    private static func uuidString(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Little-endian byte cursor (bounds-checked)

    private struct Cursor {
        let raw: [UInt8]
        var offset = 0

        init(_ data: Data) { raw = [UInt8](data) }

        mutating func u16() -> UInt16? {
            guard offset + 2 <= raw.count else { return nil }
            let value = UInt16(raw[offset]) | (UInt16(raw[offset + 1]) << 8)
            offset += 2
            return value
        }
        mutating func u32() -> UInt32? {
            guard offset + 4 <= raw.count else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 { value |= UInt32(raw[offset + i]) << (8 * i) }
            offset += 4
            return value
        }
        mutating func i32() -> Int32? { u32().map { Int32(bitPattern: $0) } }
        mutating func i64() -> Int64? { u64().map { Int64(bitPattern: $0) } }
        mutating func u64() -> UInt64? {
            guard offset + 8 <= raw.count else { return nil }
            var value: UInt64 = 0
            for i in 0..<8 { value |= UInt64(raw[offset + i]) << (8 * i) }
            offset += 8
            return value
        }
        mutating func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, offset + count <= raw.count else { return nil }
            let slice = Array(raw[offset..<offset + count])
            offset += count
            return slice
        }
        mutating func string(_ count: Int) -> String? {
            guard let bytes = take(count) else { return nil }
            return String(bytes: bytes, encoding: .utf8) ?? ""
        }
    }
}
