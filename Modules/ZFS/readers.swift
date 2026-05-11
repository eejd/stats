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

    // Rolling window of per-interval (hits, misses) counts.
    // Ratio is computed from the window totals so that low-traffic intervals
    // contribute proportionally less (access-count-weighted, not time-weighted).
    // At the default 2 s poll interval, 60 samples ≈ 2 minutes of history.
    private var l2Window: [(hits: Int64, misses: Int64)] = []
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
            l2Window.append((dH, dM))
            if l2Window.count > l2WindowSize { l2Window.removeFirst() }
            let wH = l2Window.reduce(0) { $0 + $1.hits }
            let wM = l2Window.reduce(0) { $0 + $1.misses }
            let wT = wH + wM
            stats.l2HitRatio = wT > 0 ? Double(wH) / Double(wT) : 0
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
        let candidates = [
            "/usr/local/sbin/zpool",   // zfsonmacos default
            "/usr/sbin/zpool",
            "/sbin/zpool",
            "/usr/local/bin/zpool",
            "/opt/local/sbin/zpool",   // MacPorts
            "/opt/local/bin/zpool"     // MacPorts
        ]
        zpoolBin = candidates.first { FileManager.default.fileExists(atPath: $0) }
        return zpoolBin
    }

    private func readPools(zpool: String) -> [ZFS_Pool] {
        var pools: [String: ZFS_Pool] = [:]

        // Capacity and health (no -p: human-readable sizes parsed via parseSize)
        if let out = run(zpool, args: ["list", "-H", "-o", "name,health,size,alloc,free,cap,compressratio"]) {
            for line in out.components(separatedBy: "\n") {
                let cols = fields(line)
                guard cols.count >= 6 else { continue }
                var pool = ZFS_Pool()
                pool.name      = cols[0]
                pool.health    = cols[1]
                pool.size      = parseSize(cols[2])
                pool.allocated = parseSize(cols[3])
                pool.free      = parseSize(cols[4])
                let capStr     = cols[5].replacingOccurrences(of: "%", with: "")
                pool.capacity  = (Double(capStr) ?? 0) / 100.0
                if cols.count >= 7 {
                    let ratioStr = cols[6].replacingOccurrences(of: "x", with: "")
                    pool.compressRatio = Double(ratioStr) ?? 1.0
                }
                pools[pool.name] = pool
            }
        }

        // IO bandwidth: run a 1-second interval sample; take the last line per pool (interval data)
        if let out = run(zpool, args: ["iostat", "-H", "1", "2"], timeout: 4.0) {
            var lastIO: [String: (read: Int64, write: Int64)] = [:]
            for line in out.components(separatedBy: "\n") {
                let cols = fields(line)
                guard cols.count >= 7 else { continue }
                let name = cols[0]
                guard pools[name] != nil else { continue }
                lastIO[name] = (parseSize(cols[5]), parseSize(cols[6]))
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

        do { try task.launch() } catch { return nil }

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
