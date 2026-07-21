//
//  EventDetailViewModel.swift
//  Pantrix
//
//  Turns one `InspectorEvent` into display sections for the detail screen — event meta + the seven context
//  blobs + the raw payload. Decoding is per-section and defensive: an absent (nullable) blob drops its
//  section, a corrupt blob shows a single error row rather than throwing away the whole screen. All
//  formatting happens here (§4h); the view renders `DetailSection`s.
//

import Foundation

public struct DetailRow: Equatable, Identifiable, Sendable {
    public let key: String
    public let value: String
    public var id: String { key }
}

public struct DetailSection: Equatable, Identifiable, Sendable {
    public let title: String
    public let rows: [DetailRow]
    public var id: String { title }
}

@MainActor
public final class EventDetailViewModel: ObservableObject {
    public let event: InspectorEvent
    private let screenName: String?

    public init(event: InspectorEvent, screenName: String? = nil) {
        self.event = event
        self.screenName = screenName
    }

    public var title: String { event.name }

    public private(set) lazy var sections: [DetailSection] = build()

    private func build() -> [DetailSection] {
        var result: [DetailSection] = [meta()]
        result.append(section("Session") { rowsForSession(try event.sessionAttrs()) })
        result.append(section("Device") { rowsForDevice(try event.deviceAttrs()) })
        result.append(section("Build") { rowsForBuild(try event.buildAttrs()) })
        result.append(section("Network") { rowsForNetwork(try event.networkContext()) })
        if let s = optionalSection("Screen", try event.screenAttrs().map { rowsForScreen($0) }) { result.append(s) }
        if let s = optionalSection("User", try event.userAttrs().map { rowsForUser($0) }) { result.append(s) }
        if let s = optionalSection("Power", try event.powerStateAttrs().map { rowsForPower($0) }) { result.append(s) }
        if let payload = event.rawEventAttrs, !payload.isEmpty {
            result.append(DetailSection(title: "Payload", rows: [DetailRow(key: "event_attrs", value: prettyJSON(payload))]))
        }
        return result
    }

    // MARK: - Section helpers

    /// A required-blob section: `make` decodes (may throw) into rows; a throw becomes an error row, keeping
    /// the section visible rather than blanking the screen.
    private func section(_ title: String, _ make: () throws -> [DetailRow]) -> DetailSection {
        do {
            return DetailSection(title: title, rows: try make())
        } catch {
            return DetailSection(title: title, rows: [DetailRow(key: "⚠︎ decode error", value: "\((error as NSError).localizedDescription)")])
        }
    }

    /// An optional-blob section: `nil` rows (absent column) drops the section; a throw shows an error row.
    private func optionalSection(_ title: String, _ rows: @autoclosure () throws -> [DetailRow]?) -> DetailSection? {
        do {
            guard let rows = try rows() else { return nil }
            return DetailSection(title: title, rows: rows)
        } catch {
            return DetailSection(title: title, rows: [DetailRow(key: "⚠︎ decode error", value: "\((error as NSError).localizedDescription)")])
        }
    }

    private func meta() -> DetailSection {
        var rows = [
            DetailRow(key: "event_id", value: event.id),
            DetailRow(key: "name", value: event.name),
            DetailRow(key: "type", value: event.kind.wireValue),
            DetailRow(key: "date", value: event.date),
            DetailRow(key: "session_id", value: event.sessionId),
            DetailRow(key: "reported", value: event.isReported ? "yes" : "no"),
        ]
        if let screenName { rows.append(DetailRow(key: "screen", value: screenName)) }
        if let threadName = event.threadName { rows.append(DetailRow(key: "thread", value: threadName)) }
        return DetailSection(title: "Event", rows: rows)
    }

    // MARK: - Per-blob rows

    private func rowsForSession(_ a: SessionAttrs) -> [DetailRow] {
        var rows = [
            DetailRow(key: "session_id", value: a.sessionId),
            DetailRow(key: "pid", value: String(a.pid)),
            DetailRow(key: "build_id", value: a.buildId),
            DetailRow(key: "start", value: a.startDate),
            DetailRow(key: "crashed", value: a.crashed ? "yes" : "no"),
            DetailRow(key: "supports_app_exit", value: a.supportsAppExit ? "yes" : "no"),
        ]
        if let d = a.duration { rows.append(DetailRow(key: "duration", value: InspectorFormatters.duration(millis: d))) }
        if let e = a.endDate { rows.append(DetailRow(key: "end", value: e)) }
        return rows
    }

    private func rowsForDevice(_ a: DeviceAttrs) -> [DetailRow] {
        [
            DetailRow(key: "model", value: a.model),
            DetailRow(key: "brand", value: a.brand),
            DetailRow(key: "os", value: "\(a.osName) \(a.osVersion) (sdk \(a.osSdk))"),
            DetailRow(key: "orientation", value: a.orientation),
            DetailRow(key: "screen", value: "\(a.widthPx)×\(a.heightPx) @\(a.density)x (\(a.densityDpi)dpi)"),
            DetailRow(key: "physical", value: a.isPhysical ? "yes" : "no"),
            DetailRow(key: "locale", value: a.locale),
            DetailRow(key: "carrier", value: a.carrier),
            DetailRow(key: "device_id", value: a.deviceId),
            DetailRow(key: "install_id", value: a.installId),
        ]
    }

    private func rowsForBuild(_ a: BuildAttrs) -> [DetailRow] {
        [
            DetailRow(key: "app", value: "\(a.appName) (\(a.appId))"),
            DetailRow(key: "version", value: "\(a.versionName) (\(a.versionCode))"),
            DetailRow(key: "build_id", value: a.buildId),
            DetailRow(key: "debuggable", value: a.isDebuggable ? "yes" : "no"),
        ]
    }

    private func rowsForNetwork(_ a: NetworkContextAttrs) -> [DetailRow] {
        var rows = [DetailRow(key: "connection", value: a.connectionType)]
        if let c = a.carrierName { rows.append(DetailRow(key: "carrier", value: c)) }
        if let up = a.upKbps { rows.append(DetailRow(key: "up", value: "\(up) kbps")) }
        if let down = a.downKbps { rows.append(DetailRow(key: "down", value: "\(down) kbps")) }
        return rows
    }

    private func rowsForScreen(_ a: ScreenAttrs) -> [DetailRow] {
        var rows = [
            DetailRow(key: "name", value: a.screenName),
            DetailRow(key: "class", value: a.className),
            DetailRow(key: "category", value: a.category),
        ]
        if let l = a.loadTime { rows.append(DetailRow(key: "load", value: InspectorFormatters.duration(millis: l))) }
        if let d = a.durationTime { rows.append(DetailRow(key: "on_screen", value: InspectorFormatters.duration(millis: d))) }
        return rows
    }

    private func rowsForUser(_ a: UserAttrs) -> [DetailRow] {
        var rows: [DetailRow] = []
        if let id = a.userId { rows.append(DetailRow(key: "user_id", value: id)) }
        for (key, value) in (a.userProperties ?? [:]).sorted(by: { $0.key < $1.key }) {
            rows.append(DetailRow(key: key, value: value.displayString))
        }
        return rows.isEmpty ? [DetailRow(key: "—", value: "no user data")] : rows
    }

    private func rowsForPower(_ a: PowerStateAttrs) -> [DetailRow] {
        var rows = [DetailRow(key: "thermal_throttling", value: a.thermalThrottlingEnabled ? "yes" : "no")]
        if let low = a.lowPowerModeEnabled { rows.append(DetailRow(key: "low_power_mode", value: low ? "yes" : "no")) }
        return rows
    }

    private func prettyJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else { return json }
        return string
    }
}
