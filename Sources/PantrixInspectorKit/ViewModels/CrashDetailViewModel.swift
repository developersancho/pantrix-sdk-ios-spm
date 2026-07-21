//
//  CrashDetailViewModel.swift
//  Pantrix
//
//  Prepares one crash for the detail screen: Overview / Stack Trace / Threads / Raw. The Stack Trace is the
//  CRASHED thread's frames (the exception's own frames); the crashed thread is identified by
//  `ExceptionUnit.threadSequence`, not by name (iOS Mach thread names are often blank). `crashId` and the
//  `debugImages` are surfaced — they're the only way to see why a frame did or didn't symbolicate. Frames
//  render via `FrameFormatter` (address + offset when unsymbolicated), never as blank name rows.
//

import Foundation

/// A rendered stack line.
public struct FrameDisplay: Equatable, Identifiable, Sendable {
    public let index: Int
    public let text: String
    public let inApp: Bool
    public var id: Int { index }
}

/// A thread with its rendered frames; `isCrashed` when it is the exception's `threadSequence`.
public struct ThreadDisplay: Equatable, Identifiable, Sendable {
    public let index: Int
    public let name: String
    public let isCrashed: Bool
    public let frames: [FrameDisplay]
    public var id: Int { index }
}

@MainActor
public final class CrashDetailViewModel: ObservableObject {
    public let row: CrashRow
    private let exceptions: [ExceptionUnit]
    private let threads: [ExceptionThread]

    public init(row: CrashRow) {
        self.row = row
        self.exceptions = (try? row.exceptions()) ?? []
        self.threads = (try? row.threads()) ?? []
    }

    public var kind: CrashKind { CrashKind.of(row) }
    public var title: String {
        kind == .anr ? "ANR" : (exceptions.first?.type ?? row.className).nonEmptyOr("Crash")
    }

    // MARK: - Segments

    public var overviewRows: [DetailRow] {
        let exception = exceptions.first
        var rows = [
            DetailRow(key: "kind", value: kind.label),
            DetailRow(key: "crash_id", value: row.crashId),
            DetailRow(key: "type", value: (exception?.type ?? row.className).nonEmptyOr("—")),
            DetailRow(key: "message", value: (exception?.message ?? row.message).nonEmptyOr("—")),
            DetailRow(key: "handled", value: row.handled ? "yes" : "no"),
            DetailRow(key: "foreground", value: row.foreground ? "yes" : "no"),
            DetailRow(key: "date", value: row.eventDate),
            DetailRow(key: "session_id", value: row.sessionId),
        ]
        if let signal = exception?.signal, !signal.isEmpty { rows.append(DetailRow(key: "signal", value: signal)) }
        if let threadName = exception?.threadName, !threadName.isEmpty { rows.append(DetailRow(key: "thread", value: threadName)) }
        rows.append(DetailRow(key: "crashed_thread", value: String(exception?.threadSequence ?? 0)))
        rows.append(DetailRow(key: "modules", value: String(moduleCount)))
        return rows
    }

    /// The crashed thread's stack — the exception's own frames.
    public var stackTrace: [FrameDisplay] {
        rendered(exceptions.first?.frames ?? [])
    }

    /// All captured sibling threads; the one at `threadSequence` is flagged as crashed.
    public var threadList: [ThreadDisplay] {
        let crashedIndex = exceptions.first?.threadSequence
        return threads.enumerated().map { index, thread in
            ThreadDisplay(
                index: index,
                name: thread.name.nonEmptyOr("thread \(index)"),
                isCrashed: index == crashedIndex,
                frames: rendered(thread.frames)
            )
        }
    }

    public var rawRows: [DetailRow] {
        [
            DetailRow(key: "exceptions", value: prettyJSON(row.exceptionsJSON)),
            DetailRow(key: "threads", value: prettyJSON(row.threadsJSON)),
        ]
    }

    /// Distinct binary images referenced by the crashed thread's frames — the modules that would need a
    /// dSYM to symbolicate. (The full `debugImages` list lives in the crash event's `event_attrs`, not in
    /// `pntrx_crashes`; the module set is what's reachable from here.)
    public var moduleCount: Int {
        Set(exceptions.flatMap { $0.frames }.compactMap { $0.moduleName?.nonEmptyOr("") }.filter { !$0.isEmpty }).count
    }

    // MARK: - Helpers

    private func rendered(_ frames: [Frame]) -> [FrameDisplay] {
        frames.enumerated().map { index, frame in
            FrameDisplay(index: index, text: FrameFormatter.line(frame), inApp: frame.inApp)
        }
    }

    private func prettyJSON(_ json: String) -> String {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let string = String(data: pretty, encoding: .utf8) else { return json.isEmpty ? "—" : json }
        return string
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String { isEmpty ? fallback : self }
}
