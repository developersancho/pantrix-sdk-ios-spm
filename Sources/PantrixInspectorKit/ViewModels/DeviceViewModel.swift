//
//  DeviceViewModel.swift
//  Pantrix
//
//  Shows the device + build context from the most recent event's `device_attrs` / `build_attrs` — the
//  values the SDK actually stamped on the telemetry (iOS-shaped fields, §2). Offers a copy-all string.
//

import Foundation
import Combine

@MainActor
public final class DeviceViewModel: ObservableObject {
    @Published public private(set) var state: InspectorViewState<[DetailSection]> = .loading

    private let store: InspectorStore
    private var subscription: UUID?
    private var hasLoadedOnce = false

    public init(store: InspectorStore) {
        self.store = store
    }

    public func start() {
        subscription = store.subscribe { [weak self] in self?.reload() }
        reload()
    }

    public func stop() {
        if let subscription { store.unsubscribe(subscription) }
        subscription = nil
    }

    public func reload() {
        if !hasLoadedOnce { state = .loading }
        do {
            hasLoadedOnce = true
            guard let event = try store.repo.events(pageSize: 1).first else {
                state = .empty; return
            }
            state = .content(Self.sections(from: event))
        } catch {
            state = .error(InspectorViewState<[DetailSection]>.describe(error))
        }
    }

    /// A flat plain-text dump of all rows, for copy-all.
    public var copyAllText: String {
        guard case .content(let sections) = state else { return "" }
        return sections.map { section in
            "— \(section.title) —\n" + section.rows.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func sections(from event: InspectorEvent) -> [DetailSection] {
        var result: [DetailSection] = []
        if let device = try? event.deviceAttrs() {
            result.append(DetailSection(title: "Device", rows: [
                DetailRow(key: "model", value: device.model),
                DetailRow(key: "brand", value: device.brand),
                DetailRow(key: "manufacturer", value: device.manufacturer),
                DetailRow(key: "os", value: "\(device.osName) \(device.osVersion) (sdk \(device.osSdk))"),
                DetailRow(key: "orientation", value: device.orientation),
                DetailRow(key: "screen", value: "\(device.widthPx)×\(device.heightPx) @\(device.density)x (\(device.densityDpi)dpi)"),
                DetailRow(key: "physical", value: device.isPhysical ? "yes" : "no"),
                DetailRow(key: "carrier", value: device.carrier),
                DetailRow(key: "locale", value: device.locale),
                DetailRow(key: "language", value: device.languageCode),
                DetailRow(key: "country", value: device.countryCode),
                DetailRow(key: "timezone", value: device.timeZone),
                DetailRow(key: "device_id", value: device.deviceId),
                DetailRow(key: "install_id", value: device.installId),
            ]))
        }
        if let build = try? event.buildAttrs() {
            result.append(DetailSection(title: "Build", rows: [
                DetailRow(key: "app", value: build.appName),
                DetailRow(key: "bundle", value: build.appId),
                DetailRow(key: "version", value: "\(build.versionName) (\(build.versionCode))"),
                DetailRow(key: "build_id", value: build.buildId),
                DetailRow(key: "debuggable", value: build.isDebuggable ? "yes" : "no"),
            ]))
        }
        return result
    }
}
