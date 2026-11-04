import Foundation

extension ReportStreamScheduler {
    /// The connection of the stream scheduler (METRICS 11.9, Scheduler state).
    public enum Connection: String, Equatable, Sendable { case closed, connecting, opening, open, closing }

    /// Why a built report was not delivered.
    public enum Drop: String, Equatable, Sendable {
        /// Its observation was older than 1 s at build, or its message did not fit: never written.
        case stale
        /// The service answered it with an `error`.
        case rejected
        /// The connection ended before an answer: its outcome is not known and it is never resent.
        case unknown
    }

    /// What ends automatic attempts until the user acts or the settings change (METRICS 11.9, Reactions).
    public enum Stop: String, Equatable, Sendable {
        case nonce, keyMismatch, apiKey, forbidden, clientState, upgrade, incompatible, rejected, gone, replaced, mismatch

        /// `mismatch` and `replaced` offer *Try Again*; the others wait for a change of the settings.
        public var offersRetry: Bool { self == .mismatch || self == .replaced }
    }

    /// The reactions of REPORTING 8.3 the scheduler asks its owner for.
    public enum Reaction: String, Equatable, Sendable {
        case correctClock, reRegister, recheckRegistration, rename, newRun, refreshDiscovery
    }

    public enum AckStatus: String, Equatable, Sendable { case accepted, duplicate }

    public struct Ticket: Equatable, Hashable, Sendable {
        public let seq: Int
        public let activity: ReportScheduler.Activity
        public let builtAt: Int64
        public let windowMs: Int64
        /// The window's earliest observation (monotonic ms), or nil when the window had no new data.
        public let observed: Int64?

        public var observationAgeMs: Int64? { observed.map { builtAt - $0 } }
    }

    /// What the scheduler asks its owner to do, in order.
    public enum Action: Equatable, Sendable {
        /// Empty the ledger without a report; `beforeIncrements` for the gap rule (METRICS 11.1).
        case discard(beforeIncrements: Bool)
        /// Open a connection (the signed upgrade, 10 s to the `101`).
        case connect
        /// Drop the socket without a close handshake.
        case abort
        /// Send `close 1000` and end the connection.
        case close
        /// Take the ledger and the instantaneous values into a report body.
        case build(Ticket)
        /// Sign the built body (a fresh nonce) and write it as one `report` message.
        case write(seq: Int)
        /// `latencyMs` is the answer time − the observation, when the report had one.
        case delivered(seq: Int, status: AckStatus, latencyMs: Int64?)
        case dropped(seq: Int, Drop)
        /// A due window was lost because every slot was awaited.
        case saturated
        case react(Reaction)
        case stop(Stop)
        /// A failure: no connection before `reconnectAt`.
        case backoff(reconnectAt: Int64)
        /// `Retry-After`: no connection before `until`.
        case wait(until: Int64)
        /// Tick again at `at` (the end of the minimum interval).
        case wake(at: Int64)

        /// The action as the fixtures write it (without its time); nil for a discard. Never carries a body.
        public var text: String? {
            switch self {
            case .discard: nil
            case .connect: "connect"
            case .abort: "abort"
            case .close: "close 1000"
            case .build(let ticket):
                "build \(ticket.seq) \(ticket.activity.rawValue) \(ticket.windowMs) "
                    + (ticket.observationAgeMs.map(String.init) ?? "-")
            case .write(let seq): "write \(seq)"
            case .delivered(let seq, let status, _): "delivered \(seq) \(status.rawValue)"
            case .dropped(let seq, let reason): "dropped \(seq) \(reason.rawValue)"
            case .saturated: "saturated"
            case .react(let reaction): "react \(reaction.rawValue)"
            case .stop(let reason): "stop \(reason.rawValue)"
            case .backoff(let at): "backoff \(at)"
            case .wait(let until): "wait \(until)"
            case .wake(let at): "wake \(at)"
            }
        }
    }

    /// The counters of a transport session (METRICS 11.9): they survive a new run, not a new session.
    public struct Counters: Equatable, Sendable {
        public internal(set) var built = 0
        public internal(set) var accepted = 0
        public internal(set) var duplicate = 0
        public internal(set) var rejected = 0
        public internal(set) var stale = 0
        public internal(set) var saturated = 0
        public internal(set) var unknown = 0
        public internal(set) var unmatched = 0

        public init(built: Int = 0, accepted: Int = 0, duplicate: Int = 0, rejected: Int = 0, stale: Int = 0,
                    saturated: Int = 0, unknown: Int = 0, unmatched: Int = 0) {
            self.built = built
            self.accepted = accepted
            self.duplicate = duplicate
            self.rejected = rejected
            self.stale = stale
            self.saturated = saturated
            self.unknown = unknown
            self.unmatched = unmatched
        }

        public var delivered: Int { accepted + duplicate }

        /// Windows that did not arrive: rejected, dropped as stale or while every slot was awaited, outcome unknown.
        public var notDelivered: Int { rejected + stale + saturated + unknown }

        /// The counters in the fixtures' names, in order.
        public var all: [(name: String, value: Int)] {[
            ("built", built), ("accepted", accepted), ("duplicate", duplicate), ("rejected", rejected), ("stale", stale),
            ("saturated", saturated), ("unknown", unknown), ("unmatched", unmatched),
        ]}
    }
}
