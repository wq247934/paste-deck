import Darwin
import Foundation
import Testing
@testable import AgentSpeedCore

@Suite("Traffic samplers")
struct TrafficSamplerTests {
    /// Recorded on macOS 27.0.1 through a pseudo-terminal (CRLF line ends), trimmed; names keep dots and spaces.
    static let recorded = """
        ,bytes_in,bytes_out,\r
        apsd.577,264548,30437,\r
        mDNSResponder.662,2233207265,232304878,\r
        WeChatAppEx Hel.40989,202712184,30060,\r
        python3.14.86948,436364,120325,\r
        GitHub Desktop .66297,3875,2615,\r
        Codex (Service).97613,85013675,3192751,\r
        2.1.308.36412,5876095,265390404,\r
        ,bytes_in,bytes_out,\r
        apsd.577,264600,30500,\r
        2.1.308.36412,5877000,265400000,\r

        """

    static func feed(_ parser: inout NettopParser, _ text: String, chunk: Int) -> [NettopParser.Sample] {
        let bytes = Array(text.utf8)
        var samples: [NettopParser.Sample] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + chunk, bytes.count)
            samples += bytes[index..<end].withUnsafeBytes { parser.feed($0) }
            index = end
        }
        return samples
    }

    @Test(arguments: [1, 7, 4096])
    func recordedOutputParsesInAnyChunking(chunk: Int) throws {
        var parser = NettopParser()
        let completed = Self.feed(&parser, Self.recorded, chunk: chunk)
        #expect(completed.count == 1, "the second header completes the first sample")
        guard case .rows(let first) = try #require(completed.first) else { Issue.record("unparseable"); return }
        #expect(first.map(\.pid) == [577, 662, 40989, 86948, 66297, 97613, 36412])
        #expect(first[1] == .init(pid: 662, rx: 2_233_207_265, tx: 232_304_878))
        #expect(first[6] == .init(pid: 36412, rx: 5_876_095, tx: 265_390_404))
        let last = parser.finish()
        #expect(last == .rows([.init(pid: 577, rx: 264_600, tx: 30500), .init(pid: 36412, rx: 5_877_000, tx: 265_400_000)]))
        #expect(parser.finish() == nil)
    }

    @Test func nettopSelectsEverySocketButLoopback() {
        let arguments = NettopChild.arguments(interval: 5)
        #expect(arguments == ["nettop", "-P", "-L", "0", "-s", "5", "-x", "-n", "-t", "external", "-t", "undefined",
                              "-J", "bytes_in,bytes_out"])
        #expect(!arguments.contains("loopback"))
    }

    /// Recorded on macOS 27.0.1 with `-t external -t undefined` (issue #35): identityservicesd and the Python sender
    /// have traffic only on tunnel interfaces (`undefined`), the curl behind a local proxy only on loopback (0 here),
    /// the proxy only its outgoing socket.
    @Test func processesListedOnlyThroughUndefinedParseLikeAnyOther() {
        var parser = NettopParser()
        let text = """
            ,bytes_in,bytes_out,\r
            identityservice.782,2250,2248,\r
            Python.48674,0,284050,\r
            curl.47385,0,0,\r
            Python.47371,7015288,543,\r

            """
        _ = Self.feed(&parser, text, chunk: 5)
        #expect(parser.finish() == .rows([.init(pid: 782, rx: 2250, tx: 2248), .init(pid: 48674, rx: 0, tx: 284_050),
                                          .init(pid: 47385, rx: 0, tx: 0), .init(pid: 47371, rx: 7_015_288, tx: 543)]))
    }

    @Test func badLinesAreSkippedAndColumnsFollowTheHeader() {
        var parser = NettopParser()
        let text = """
            ,bytes_out,bytes_in,
            no-pid-here,1,2,
            odd,name.12,3,4,
            bad.13,x,4,
            huge.14,1,99999999999999999999,
            ok.15,10,20,

            """
        _ = Self.feed(&parser, text, chunk: 64)
        #expect(parser.finish() == .rows([.init(pid: 12, rx: 4, tx: 3), .init(pid: 15, rx: 20, tx: 10)]))
    }

    @Test func samplesWithoutColumnsOrParseableLinesAreUnparseable() {
        var parser = NettopParser()
        _ = Self.feed(&parser, ",time,state,\nfoo.1,a,b,\n", chunk: 64)
        #expect(parser.finish() == .unparseable)
        _ = Self.feed(&parser, ",bytes_in,bytes_out,\ngarbage\n", chunk: 64)
        #expect(parser.finish() == .unparseable)
        _ = Self.feed(&parser, ",bytes_in,bytes_out,\n", chunk: 64)
        #expect(parser.finish() == .rows([]), "a header alone is an empty sample")
    }

    @Test func anUnterminatedLineIsNeverReadAsACounter() {
        var parser = NettopParser()
        _ = Self.feed(&parser, ",bytes_in,bytes_out,\nok.15,10,20,\npartial.16,123", chunk: 64)
        #expect(parser.finish() == .rows([.init(pid: 15, rx: 10, tx: 20)]))
        let next = Self.feed(&parser, "456,7,\n,bytes_in,bytes_out,\nok.15,11,21,\n", chunk: 64)
        #expect(next.isEmpty, "the completed line arrived outside a sample and is dropped")
        #expect(parser.finish() == .rows([.init(pid: 15, rx: 11, tx: 21)]))
    }

    @Test func kernelProcessArgumentsParse() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { bytes += $0 }
        bytes += Array("/opt/homebrew/bin/node".utf8)
        bytes += [0, 0, 0, 0]
        bytes += Array("node".utf8)
        bytes += [0]
        bytes += Array("/x/@google/gemini-cli/dist/index.js".utf8)
        bytes += [0]
        bytes += Array("--yolo".utf8)
        bytes += [0]
        bytes += Array("PATH=/usr/bin".utf8)
        bytes += [0]
        let arguments = bytes.withUnsafeBytes { ProcessReader.parseArguments($0) }
        #expect(arguments == ["node", "/x/@google/gemini-cli/dist/index.js", "--yolo"])
    }

    @Test func interfaceCountersAre64BitAndFiltered() throws {
        let reader = MachineCounterReader()
        let counted = CountedInterfaces.current()
        let counters = try #require(reader.read(counted: counted))
        #expect(Set(counters.keys).isSubset(of: counted))
        #expect(!counted.contains("lo0") && !counted.contains { $0.hasPrefix("utun") || $0.hasPrefix("bridge") })
        let everything = try #require(reader.read(counted: ["lo0"]))
        #expect(everything["lo0"].map { $0.rx > 0 } ?? true)
    }

    @Test func processListingFindsThisProcessWithItsDetails() throws {
        let reader = ProcessReader()
        let entries = reader.list(nowMs: 0)
        let me = try #require(entries.first { $0.pid == getpid() })
        #expect(me.ppid == getppid())
        #expect(me.startUs > 1_600_000_000_000_000)
        #expect(reader.executablePath(of: me).map { !$0.isEmpty } == true)
        #expect(reader.arguments(of: me)?.isEmpty == false)
        #expect(reader.workingDirectory(of: me) == FileManager.default.currentDirectoryPath)
        let handle = try FileHandle(forReadingFrom: Fixtures.root.appendingPathComponent("traffic-cases.json"))
        defer { try? handle.close() }
        #expect(reader.openFiles(of: me, nowMs: 0).contains { $0.hasSuffix("traffic-cases.json") })
        let later = reader.list(nowMs: 1000)
        #expect(later.contains(me), "known pids keep their entry between full reads")
    }

    @Test(.enabled(if: NettopChild.isAvailable), .timeLimit(.minutes(1)))
    func nettopChildStreamsSamplesAndIsReaped() async throws {
        let queue = DispatchQueue(label: "test.nettop")
        let sampler = NettopSampler(queue: queue, clock: TrafficCore.monotonicMs)
        queue.sync { sampler.run(interval: 1) }
        let pid = try #require(queue.sync { sampler.childPid })
        var rows: [NettopParser.Row]?
        for _ in 0..<50 where rows == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
            rows = queue.sync { sampler.takeSample() }
        }
        #expect(rows?.isEmpty == false)
        #expect(queue.sync { sampler.status } == .sampling)
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        #expect(proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size)
        #expect(Int32(bitPattern: info.e_tdev) != -1, "the pseudo-terminal is its controlling terminal")
        queue.sync { sampler.stop() }
        #expect(kill(pid, 0) == -1 && errno == ESRCH, "killed and reaped")
    }

    /// Moves 16 MB over loopback (both ends, kept open), sends UDP through a tunnel interface when one is up and one
    /// datagram towards a documentation address (RFC 5737) when a route exists; prints its pid and byte counts.
    static let socketHelper = """
        import os, socket, struct, threading, time
        N = 8_000_000
        held = []
        srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1)
        def serve():
            c, _ = srv.accept(); held.append(c); got = 0
            while got < N:
                d = c.recv(65536)
                if not d: break
                got += len(d)
        t = threading.Thread(target=serve); t.start()
        cli = socket.create_connection(srv.getsockname()); held.append(cli)
        cli.sendall(bytes(N)); t.join()
        label = lambda s: bytes([len(s)]) + s
        query = struct.pack(">6H", 0, 0, 1, 0, 0, 0) + label(b"agent-speed") + label(b"local") + bytes(1) + struct.pack(">HH", 255, 1)
        tunnel = 0
        for name in sorted(n for _, n in socket.if_nameindex() if n.startswith("utun")):
            try:
                index = socket.if_nametoindex(name)
                s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM); held.append(s)
                s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_IF, index)
                s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_HOPS, 1)
                s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_MULTICAST_LOOP, 0)
                for _ in range(100):
                    tunnel += s.sendto(query, ("ff02::fb", 5353, 0, index))
                break
            except OSError:
                tunnel = 0
        outgoing = 0
        try:
            u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); held.append(u)
            u.connect(("192.0.2.1", 9))
            outgoing = u.send(bytes(1200))
        except OSError:
            outgoing = 0
        print(os.getpid(), 2 * N, tunnel, outgoing, flush=True)
        time.sleep(50)
        """

    @Test(.enabled(if: NettopChild.isAvailable && FileManager.default.isExecutableFile(atPath: "/usr/bin/python3")),
          .timeLimit(.minutes(1)))
    func nettopCountsTunnelAndOutgoingBytesButNotLoopback() async throws {
        let queue = DispatchQueue(label: "test.nettop.types")
        let sampler = NettopSampler(queue: queue, clock: TrafficCore.monotonicMs)
        queue.sync { sampler.run(interval: 1) }
        defer { queue.sync { sampler.stop() } }
        for _ in 0..<50 where queue.sync(execute: { sampler.takeSample() }) == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        helper.arguments = ["-I", "-c", Self.socketHelper]
        let output = Pipe()
        helper.standardOutput = output
        try helper.run()
        defer {
            helper.terminate()
            helper.waitUntilExit()
        }
        let report = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
            .split(whereSeparator: \.isWhitespace).compactMap { Int64($0) }
        try #require(report.count == 4, "helper report: \(report)")
        let pid = Int32(report[0])
        defer { kill(pid, SIGKILL) }
        let counted = report[2] + report[3]

        var row: NettopParser.Row?
        var samples = 0
        for _ in 0..<60 {
            try await Task.sleep(nanoseconds: 200_000_000)
            guard let rows = queue.sync(execute: { sampler.takeSample() }) else { continue }
            samples += 1
            row = rows.first { $0.pid == pid }
            if samples >= 2, counted == 0 || (row?.tx ?? 0) >= counted { break }
        }
        if counted > 0 {
            #expect(row != nil, "the helper is listed through its tunnel or outgoing socket")
            #expect((row?.tx ?? 0) >= counted, "tunnel \(report[2]) B and outgoing \(report[3]) B are counted")
        }
        let listed = (row?.rx ?? 0) + (row?.tx ?? 0)
        #expect(listed < counted + 1_000_000, "the \(report[1]) B over loopback are not counted (listed \(listed) B)")
    }
}
