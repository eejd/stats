//
//  readers.swift
//  ZFS
//
//  Created by Eric DeWitt on 09/05/2026.
//  Using Swift 5.0.
//  Running on macOS 11.0.
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class UsageReader: Reader<ZFS_Stats> {
    private var prevArcHits: Int64 = -1
    private var prevArcMisses: Int64 = -1
    private var prevL2Hits: Int64 = -1
    private var prevL2Misses: Int64 = -1

    // Rolling window of per-interval hit ratios (time-weighted: each active interval
    // counts equally regardless of access volume). Idle intervals — where neither
    // hits nor misses changed — are skipped so a warmup burst of misses cannot
    // depress the displayed ratio long after the cache has stabilised.
    // At the default 2 s poll interval, 60 active samples ≈ up to 2 min of history.
    private var l2RatioHistory: [Double] = []
    private let l2WindowSize = 60

    private var zpoolBin: String? = nil

    public override func read() {
        var stats = ZFS_Stats()

        func readU64(_ name: String) -> Int64 {
            var sz: size_t = MemoryLayout<UInt64>.size
            var val: UInt64 = 0
            guard sysctlbyname(name, &val, &sz, nil, 0) == 0 else { return 0 }
            return Int64(bitPattern: val)
        }

        stats.arcSize     = readU64("kstat.zfs.misc.arcstats.size")
        stats.arcMax      = readU64("kstat.zfs.misc.arcstats.c_max")
        stats.arcMetaUsed = readU64("kstat.zfs.misc.arcstats.arc_meta_used")
        stats.arcHits     = readU64("kstat.zfs.misc.arcstats.hits")
        stats.arcMisses   = readU64("kstat.zfs.misc.arcstats.misses")
        stats.l2Size      = readU64("kstat.zfs.misc.arcstats.l2_size")
        stats.l2Hits      = readU64("kstat.zfs.misc.arcstats.l2_hits")
        stats.l2Misses    = readU64("kstat.zfs.misc.arcstats.l2_misses")

        if prevArcHits >= 0 {
            let dH = max(0, stats.arcHits - prevArcHits)
            let dM = max(0, stats.arcMisses - prevArcMisses)
            let t  = dH + dM
            stats.arcHitRatio = t > 0 ? Double(dH) / Double(t) : 0
        }
        prevArcHits   = stats.arcHits
        prevArcMisses = stats.arcMisses

        if prevL2Hits >= 0 {
            let dH = max(0, stats.l2Hits - prevL2Hits)
            let dM = max(0, stats.l2Misses - prevL2Misses)
            let dT = dH + dM
            if dT > 0 {
                l2RatioHistory.append(Double(dH) / Double(dT))
                if l2RatioHistory.count > l2WindowSize { l2RatioHistory.removeFirst() }
            }
            stats.l2HitRatio = l2RatioHistory.isEmpty
                ? 0
                : l2RatioHistory.reduce(0, +) / Double(l2RatioHistory.count)
        }
        prevL2Hits   = stats.l2Hits
        prevL2Misses = stats.l2Misses

        if let zpool = zpoolBinary() {
            stats.pools = readPools(zpool: zpool)
        }

        self.callback(stats)
    }

    // MARK: - Pool reading

    private func zpoolBinary() -> String? {
        if let cached = zpoolBin { return cached }

        // Prefer PATH so any installation method (ports, manual, future) works.
        // GUI apps may inherit a restricted PATH from launchd, so append known
        // locations that are frequently absent from the GUI environment.
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .components(separatedBy: ":")
            .filter { !$0.isEmpty }

        let fallbackDirs = [
            "/usr/local/zfs/bin",  // zfsonmacos canonical
            "/usr/local/sbin",
            "/usr/sbin",
            "/sbin",
            "/usr/local/bin",
            "/opt/local/sbin",     // MacPorts
            "/opt/local/bin",      // MacPorts
        ]

        var seen = Set<String>()
        let dirs = (pathDirs + fallbackDirs).filter { seen.insert($0).inserted }

        zpoolBin = dirs
            .map { ($0 as NSString).appendingPathComponent("zpool") }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        return zpoolBin
    }

    private func readPools(zpool: String) -> [ZFS_Pool] {
        var pools: [String: ZFS_Pool] = [:]

        // --json-int gives exact integers with no text-parsing ambiguity.
        if let out = run(zpool, args: ["list", "-j", "--json-int"]),
           let data = out.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let poolsJson = root["pools"] as? [String: Any] {
            for (_, entry) in poolsJson {
                guard let d = entry as? [String: Any],
                      let name = d["name"] as? String,
                      let props = d["properties"] as? [String: Any] else { continue }
                func intProp(_ key: String) -> Int64 {
                    ((props[key] as? [String: Any])?["value"] as? NSNumber)?.int64Value ?? 0
                }
                var pool = ZFS_Pool()
                pool.name      = name
                pool.health    = (d["state"] as? String) ?? "UNKNOWN"
                pool.size      = intProp("size")
                pool.allocated = intProp("allocated")
                pool.free      = intProp("free")
                pool.capacity  = Double(intProp("capacity")) / 100.0
                pools[name] = pool
            }
        }

        // -p gives exact bytes/sec; cols: name alloc free read_ops write_ops read_bw write_bw.
        // First output block (cumulative since import) has '-' for ops/bw — Int64("-") is nil,
        // so the guard skips it and lastIO ends up holding the interval sample.
        if let out = run(zpool, args: ["iostat", "-H", "-p", "1", "2"], timeout: 4.0) {
            var lastIO: [String: (read: Int64, write: Int64)] = [:]
            for line in out.components(separatedBy: "\n") {
                let cols = fields(line)
                guard cols.count >= 7 else { continue }
                let name = cols[0]
                guard pools[name] != nil else { continue }
                guard let r = Int64(cols[5]), let w = Int64(cols[6]) else { continue }
                lastIO[name] = (r, w)
            }
            for (name, bw) in lastIO {
                pools[name]?.readBandwidth  = bw.read
                pools[name]?.writeBandwidth = bw.write
            }
        }

        return Array(pools.values).sorted { $0.name < $1.name }
    }

    // MARK: - Helpers

    /// Split a line on whitespace, dropping empty tokens (handles both tab and space separators)
    private func fields(_ line: String) -> [String] {
        return line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    /// Parse human-readable ZFS sizes: "144M", "1.63G", "18.4k", "7.27T", "0", "-"
    private func parseSize(_ s: String) -> Int64 {
        let s = s.trimmingCharacters(in: .whitespaces)
        guard s != "-", !s.isEmpty else { return 0 }
        let table: [(Character, Double)] = [
            ("P", 1024*1024*1024*1024*1024),
            ("T", 1024*1024*1024*1024),
            ("G", 1024*1024*1024),
            ("M", 1024*1024),
            ("K", 1024),  // zpool iostat may output uppercase K
            ("k", 1024),
            ("B", 1)
        ]
        if let last = s.last {
            for (ch, mult) in table where ch == last {
                if let v = Double(String(s.dropLast())) { return Int64(v * mult) }
            }
        }
        return Int64(s) ?? 0
    }

    private func run(_ path: String, args: [String], timeout: TimeInterval = 5.0) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = Pipe()

        do { try task.run() } catch { return nil }

        // Block the background reader thread; terminate if overdue
        let deadline = Date(timeIntervalSinceNow: timeout)
        while task.isRunning {
            if Date() > deadline { task.terminate(); return nil }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
