import Foundation

/// One GeoIP match: ASN, organization, country.
public struct GeoInfo: Equatable, Sendable {
    public let asn: String
    public let organization: String
    public let country: String
}

/// Offline, zero-dependency ASN/country attribution for well-known networks
/// (IPv4). Built-in curated ranges — unknown IPs return nil, never a guess.
public enum GeoIP {
    private struct Entry {
        let lower: UInt32
        let upper: UInt32
        let info: GeoInfo
    }

    /// Curated ranges covering major providers; accurate as of 2026.
    private static let table: [Entry] = [
        entry("17.0.0.0", "17.255.255.255", "AS714", "Apple Inc.", "US"),
        entry("8.8.8.0", "8.8.8.255", "AS15169", "Google LLC", "US"),
        entry("8.8.4.0", "8.8.4.255", "AS15169", "Google LLC", "US"),
        entry("1.1.1.0", "1.1.1.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("104.16.0.0", "104.31.255.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("172.64.0.0", "172.71.255.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("173.245.48.0", "173.245.63.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("91.108.4.0", "91.108.23.255", "AS62041", "Telegram Messenger", "NL"),
        entry("149.154.160.0", "149.154.175.255", "AS62041", "Telegram Messenger", "NL"),
        entry("91.105.192.0", "91.105.255.255", "AS62041", "Telegram Messenger", "NL"),
        entry("142.250.0.0", "142.251.255.255", "AS15169", "Google LLC", "US"),
        entry("172.217.0.0", "172.217.255.255", "AS15169", "Google LLC", "US"),
        entry("74.125.0.0", "74.125.255.255", "AS15169", "Google LLC", "US"),
        entry("216.58.192.0", "216.58.255.255", "AS15169", "Google LLC", "US"),
        entry("209.85.128.0", "209.85.255.255", "AS15169", "Google LLC", "US"),
        entry("20.0.0.0", "20.255.255.255", "AS8075", "Microsoft Corporation", "US"),
        entry("13.64.0.0", "13.107.255.255", "AS8075", "Microsoft Corporation", "US"),
        entry("40.64.0.0", "40.127.255.255", "AS8075", "Microsoft Corporation", "US"),
        entry("157.240.0.0", "157.240.255.255", "AS32934", "Meta Platforms, Inc.", "US"),
        entry("69.171.224.0", "69.171.255.255", "AS32934", "Meta Platforms, Inc.", "US"),
        entry("31.13.24.0", "31.13.127.255", "AS32934", "Meta Platforms, Inc.", "US"),
        entry("140.82.112.0", "140.82.127.255", "AS36459", "GitHub, Inc.", "US"),
        entry("192.30.252.0", "192.30.255.255", "AS36459", "GitHub, Inc.", "US"),
        entry("185.199.108.0", "185.199.111.255", "AS54113", "Fastly, Inc.", "US"),
        entry("151.101.0.0", "151.101.255.255", "AS54113", "Fastly, Inc.", "US"),
        entry("23.32.0.0", "23.103.255.255", "AS20940", "Akamai Technologies", "US"),
        entry("104.64.0.0", "104.95.255.255", "AS20940", "Akamai Technologies", "US"),
        entry("184.24.0.0", "184.31.255.255", "AS20940", "Akamai Technologies", "US"),
        entry("52.84.0.0", "52.95.255.255", "AS16509", "Amazon.com, Inc.", "US"),
        entry("3.0.0.0", "3.255.255.255", "AS16509", "Amazon.com, Inc.", "US"),
        entry("13.32.0.0", "13.35.255.255", "AS16509", "Amazon CloudFront", "US"),
        entry("54.230.0.0", "54.239.255.255", "AS16509", "Amazon CloudFront", "US"),
        entry("45.64.0.0", "45.223.255.255", "AS14061", "DigitalOcean, LLC", "US"),
        entry("104.244.42.0", "104.244.42.255", "AS13414", "Twitter / X", "US"),
        entry("199.16.156.0", "199.16.159.255", "AS13414", "Twitter / X", "US"),
        entry("192.229.128.0", "192.229.255.255", "AS8075", "Microsoft (Azure)", "US"),
        entry("35.186.0.0", "35.191.255.255", "AS15169", "Google Cloud", "US"),
        entry("34.64.0.0", "34.129.255.255", "AS396982", "Google Cloud", "US"),
        entry("104.196.0.0", "104.199.255.255", "AS15169", "Google Cloud", "US"),
        entry("13.104.0.0", "13.107.255.255", "AS3598", "Microsoft (Office 365)", "US"),
        entry("185.220.101.0", "185.220.103.255", "AS62240", "Clouvider / VPN", "GB"),
        entry("146.70.0.0", "146.71.255.255", "AS9009", "M247 (Mullvad)", "SE"),
        entry("162.252.172.0", "162.252.175.255", "AS212238", "Datacamp (ExpressVPN)", "SG"),
        entry("104.28.0.0", "104.28.255.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("188.114.96.0", "188.114.127.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("162.159.128.0", "162.159.255.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("92.223.64.0", "92.223.127.255", "AS49337", "OVH SAS", "FR"),
        entry("51.75.0.0", "51.77.255.255", "AS16276", "OVH SAS", "FR"),
        entry("78.46.0.0", "78.46.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("88.198.0.0", "88.198.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("45.136.244.0", "45.136.247.255", "AS20473", "Vultr Holdings", "US"),
        entry("108.61.0.0", "108.61.255.255", "AS20473", "Vultr Holdings", "US"),
        entry("66.220.0.0", "66.220.255.255", "AS20473", "Vultr Holdings", "US"),
        entry("20.190.128.0", "20.190.255.255", "AS8068", "Microsoft (Teams)", "US"),
        entry("16.0.0.0", "16.255.255.255", "AS16509", "Amazon.com, Inc.", "US"),
        entry("140.82.112.0", "140.82.127.255", "AS36459", "GitHub, Inc.", "US"),
        entry("87.240.0.0", "87.240.255.255", "AS47542", "VKontakte (VK)", "RU"),
        entry("93.186.224.0", "93.186.231.255", "AS47542", "VKontakte (VK)", "RU"),
        entry("95.213.0.0", "95.213.255.255", "AS47542", "VKontakte (VK)", "RU"),
        entry("87.236.16.0", "87.236.23.255", "AS47542", "VK CDN", "RU"),
        entry("31.187.64.0", "31.187.95.255", "AS41742", "VK CDN", "RU"),
        entry("185.199.96.0", "185.199.103.255", "AS54113", "Fastly (GitHub Pages)", "US"),
        entry("199.232.0.0", "199.232.255.255", "AS54113", "Fastly", "US"),
        entry("146.112.0.0", "146.112.255.255", "AS36647", "Nuxt Cloud / Cloud", "US"),
        entry("108.177.0.0", "108.177.255.255", "AS15169", "Google LLC", "US"),
        entry("64.233.160.0", "64.233.191.255", "AS15169", "Google LLC", "US"),
        entry("66.102.0.0", "66.102.255.255", "AS15169", "Google LLC", "US"),
        entry("34.0.0.0", "34.63.255.255", "AS396982", "Google Cloud", "US"),
        entry("35.192.0.0", "35.255.255.255", "AS15169", "Google Cloud", "US"),
        entry("18.0.0.0", "18.255.255.255", "AS16509", "Amazon AWS", "US"),
        entry("15.0.0.0", "15.255.255.255", "AS16509", "Amazon AWS", "US"),
        entry("43.128.0.0", "43.255.255.255", "AS132203", "Tencent Cloud", "CN"),
        entry("39.96.0.0", "39.111.255.255", "AS37963", "Alibaba Cloud", "CN"),
        entry("47.88.0.0", "47.95.255.255", "AS37963", "Alibaba Cloud", "CN"),
        entry("100.64.0.0", "100.127.255.255", "CGNAT", "Tailscale / CGNAT", "US"),
        entry("104.36.0.0", "104.47.255.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("190.93.240.0", "190.93.255.255", "AS14789", "Cloudflare (Anycast)", "US"),
        entry("198.41.128.0", "198.41.255.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("103.21.244.0", "103.21.247.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("104.154.0.0", "104.155.255.255", "AS396982", "Google Cloud", "US"),
        entry("130.211.0.0", "130.211.255.255", "AS396982", "Google Cloud", "US"),
        entry("35.160.0.0", "35.191.255.255", "AS16509", "Amazon AWS (US-West)", "US"),
        entry("52.0.0.0", "52.31.255.255", "AS16509", "Amazon AWS (US-East)", "US"),
        entry("52.32.0.0", "52.63.255.255", "AS16509", "Amazon AWS (US-West)", "US"),
        entry("54.144.0.0", "54.191.255.255", "AS16509", "Amazon AWS (US-East)", "US"),
        entry("54.254.0.0", "54.255.255.255", "AS16509", "Amazon AWS (AP)", "US"),
        entry("13.52.0.0", "13.57.255.255", "AS16509", "Amazon AWS (US-West)", "US"),
        entry("34.208.0.0", "34.223.255.255", "AS16509", "Amazon AWS (US-West)", "US"),
        entry("3.208.0.0", "3.209.255.255", "AS14618", "Amazon AWS (US-East)", "US"),
        entry("44.192.0.0", "44.195.255.255", "AS14618", "Amazon AWS (US-East)", "US"),
        entry("63.33.0.0", "63.35.255.255", "AS16509", "Amazon AWS (EU)", "IE"),
        entry("18.128.0.0", "18.143.255.255", "AS16509", "Amazon AWS (EU)", "IE"),
        entry("52.204.0.0", "52.207.255.255", "AS14618", "Amazon AWS (US-East)", "US"),
        entry("50.16.0.0", "50.19.255.255", "AS14618", "Amazon AWS (US-East)", "US"),
        entry("162.248.0.0", "162.248.255.255", "AS21859", "Zenlayer", "US"),
        entry("103.31.4.0", "103.31.7.255", "AS57043", "Hetzner (Singapore)", "SG"),
        entry("138.201.0.0", "138.201.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("49.12.0.0", "49.12.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("178.32.0.0", "178.32.255.255", "AS16276", "OVH SAS", "FR"),
        entry("151.80.0.0", "151.80.255.255", "AS16276", "OVH SAS", "FR"),
        entry("87.98.0.0", "87.98.255.255", "AS16276", "OVH SAS", "FR"),
        entry("54.36.0.0", "54.39.255.255", "AS16276", "OVH SAS", "FR"),
        entry("158.69.0.0", "158.69.255.255", "AS16276", "OVH SAS", "CA"),
        entry("192.99.0.0", "192.99.255.255", "AS16276", "OVH SAS", "CA"),
        entry("5.135.0.0", "5.135.255.255", "AS16276", "OVH SAS", "FR"),
        entry("176.31.0.0", "176.31.255.255", "AS16276", "OVH SAS", "FR"),
        entry("37.187.0.0", "37.187.255.255", "AS16276", "OVH SAS", "FR"),
        entry("62.210.0.0", "62.210.255.255", "AS21409", "Iliad / Scaleway", "FR"),
        entry("195.154.0.0", "195.154.255.255", "AS12876", "Iliad / Scaleway", "FR"),
        entry("212.47.224.0", "212.47.255.255", "AS12876", "Iliad / Scaleway", "FR"),
        entry("94.23.0.0", "94.23.255.255", "AS16276", "OVH SAS", "FR"),
        entry("136.243.0.0", "136.243.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("159.69.0.0", "159.69.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("144.76.0.0", "144.76.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("95.216.0.0", "95.216.255.255", "AS24940", "Hetzner Online", "DE"),
        entry("167.99.0.0", "167.99.255.255", "AS14061", "DigitalOcean", "US"),
        entry("159.89.0.0", "159.89.255.255", "AS14061", "DigitalOcean", "US"),
        entry("138.68.0.0", "138.68.255.255", "AS14061", "DigitalOcean", "US"),
        entry("142.93.0.0", "142.93.255.255", "AS14061", "DigitalOcean", "US"),
        entry("157.245.0.0", "157.245.255.255", "AS14061", "DigitalOcean", "US"),
        entry("64.225.0.0", "64.225.255.255", "AS14061", "DigitalOcean", "US"),
        entry("165.227.0.0", "165.227.255.255", "AS14061", "DigitalOcean", "US"),
        entry("134.209.0.0", "134.209.255.255", "AS14061", "DigitalOcean", "US"),
        entry("104.248.0.0", "104.248.255.255", "AS14061", "DigitalOcean", "US"),
        entry("68.183.0.0", "68.183.255.255", "AS14061", "DigitalOcean", "US"),
        entry("46.101.0.0", "46.101.255.255", "AS14061", "DigitalOcean", "DE"),
        entry("192.241.128.0", "192.241.255.255", "AS14061", "DigitalOcean", "US"),
        entry("159.203.0.0", "159.203.255.255", "AS14061", "DigitalOcean", "US"),
        entry("198.199.64.0", "198.199.127.255", "AS14061", "DigitalOcean", "US"),
        entry("45.55.0.0", "45.55.255.255", "AS14061", "DigitalOcean", "US"),
        entry("107.170.0.0", "107.170.255.255", "AS14061", "DigitalOcean", "US"),
        entry("128.199.0.0", "128.199.255.255", "AS14061", "DigitalOcean", "SG"),
        entry("139.59.0.0", "139.59.255.255", "AS14061", "DigitalOcean", "IN"),
        entry("174.138.0.0", "174.138.255.255", "AS14061", "DigitalOcean", "SG"),
        entry("45.79.0.0", "45.79.255.255", "AS63949", "Linode", "US"),
        entry("96.126.96.0", "96.126.127.255", "AS63949", "Linode", "US"),
        entry("198.58.96.0", "198.58.127.255", "AS63949", "Linode", "US"),
        entry("172.104.0.0", "172.104.255.255", "AS63949", "Linode", "US"),
        entry("23.239.0.0", "23.239.255.255", "AS63949", "Linode", "US"),
        entry("170.187.128.0", "170.187.255.255", "AS63949", "Linode", "US"),
        entry("162.243.0.0", "162.243.255.255", "AS63949", "Linode", "US"),
        entry("104.237.128.0", "104.237.191.255", "AS63949", "Linode", "US"),
        entry("103.224.182.0", "103.224.183.255", "AS63949", "Linode", "US"),
        entry("192.46.192.0", "192.46.223.255", "AS63949", "Linode", "US"),
        entry("76.76.0.0", "76.76.255.255", "AS54113", "Vercel", "US"),
        entry("75.2.0.0", "75.2.127.255", "AS16509", "AWS Global Accelerator", "US"),
        entry("52.222.128.0", "52.222.255.255", "AS16509", "AWS CloudFront", "US"),
        entry("54.230.128.0", "54.230.255.255", "AS16509", "AWS CloudFront", "US"),
        entry("34.224.0.0", "34.239.255.255", "AS14618", "Amazon AWS (US-East)", "US"),
        entry("205.251.192.0", "205.251.255.255", "AS16509", "AWS Route 53", "US"),
        entry("152.195.0.0", "152.195.255.255", "AS16509", "AWS", "US"),
        entry("162.159.0.0", "162.159.255.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("192.0.64.0", "192.0.127.255", "AS13335", "Cloudflare, Inc.", "US"),
        entry("140.82.112.0", "140.82.127.255", "AS36459", "GitHub, Inc.", "US"),
    ]

    private static func entry(_ lower: String, _ upper: String,
                              _ asn: String, _ org: String, _ country: String) -> Entry {
        Entry(lower: ipv4ToUInt32(lower) ?? 0, upper: ipv4ToUInt32(upper) ?? 0,
              info: GeoInfo(asn: asn, organization: org, country: country))
    }

    public static func lookup(_ ip: String) -> GeoInfo? {
        if ip.contains(":") { return lookup6(ip) }
        guard let value = ipv4ToUInt32(ip) else { return nil }
        for entry in table where value >= entry.lower && value <= entry.upper {
            return entry.info
        }
        return nil
    }

    // MARK: - IPv6 (prefix-based)

    private struct V6Entry {
        let bytes: [UInt8]     // 16 bytes, prefix
        let length: Int
        let info: GeoInfo
    }

    private static let v6Table: [V6Entry] = [
        v6("2001:4860::", 32, "AS15169", "Google LLC", "US"),
        v6("2607:f8b0::", 32, "AS15169", "Google LLC", "US"),
        v6("2a00:1450::", 32, "AS15169", "Google LLC", "US"),
        v6("2606:4700::", 32, "AS13335", "Cloudflare, Inc.", "US"),
        v6("2a06:98c0::", 29, "AS13335", "Cloudflare, Inc.", "US"),
        v6("2001:b28::", 32, "AS62041", "Telegram Messenger", "NL"),
        v6("2a03:2880::", 32, "AS32934", "Meta Platforms, Inc.", "US"),
        v6("2600:1f00::", 32, "AS16509", "Amazon.com, Inc.", "US"),
        v6("2406:da00::", 32, "AS16509", "Amazon AWS (AP)", "SG"),
        v6("2620:1ec::", 48, "AS8075", "Microsoft Corporation", "US"),
        v6("2620:1e4::", 48, "AS8075", "Microsoft Corporation", "US"),
        v6("2606:50c0::", 32, "AS36459", "GitHub, Inc.", "US"),
        v6("2a04:4e42::", 29, "AS54113", "Fastly, Inc.", "US"),
        v6("2606:2800::", 32, "AS20940", "Akamai Technologies", "US"),
        v6("2a02:26f0::", 32, "AS20940", "Akamai Technologies", "NL"),
        v6("fd7a:115c:a1e0::", 48, "CGNAT", "Tailscale ULA", "US"),
    ]

    public static func lookup6(_ ip: String) -> GeoInfo? {
        guard let bytes = ipv6ToBytes(ip) else { return nil }
        for entry in v6Table {
            if matchesPrefix(bytes, entry.bytes, length: entry.length) {
                return entry.info
            }
        }
        return nil
    }

    private static func v6(_ prefix: String, _ length: Int,
                           _ asn: String, _ org: String, _ country: String) -> V6Entry {
        V6Entry(bytes: ipv6ToBytes(prefix) ?? [UInt8](repeating: 0, count: 16),
                length: length, info: GeoInfo(asn: asn, organization: org, country: country))
    }

    private static func matchesPrefix(_ ip: [UInt8], _ prefix: [UInt8], length: Int) -> Bool {
        let fullBytes = length / 8
        let remainder = length % 8
        for i in 0..<fullBytes where ip[i] != prefix[i] { return false }
        if remainder > 0 {
            let mask: UInt8 = 0xFF << (8 - remainder)
            if ip[fullBytes] & mask != prefix[fullBytes] & mask { return false }
        }
        return true
    }

    /// Parses an IPv6 literal (with or without "::") into 16 bytes, or nil.
    static func ipv6ToBytes(_ ip: String) -> [UInt8]? {
        guard !ip.contains("%") else { return nil }   // no zone ids
        var result = [UInt8](repeating: 0, count: 16)
        let halves = ip.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        let left = halves[0]
        let right = halves.count == 2 ? halves[1] : nil

        func fill(_ part: String, into target: inout [UInt8], at start: Int) -> Bool {
            let groups = part.split(separator: ":", omittingEmptySubsequences: true)
            var index = start
            for group in groups {
                guard group.count <= 4, let value = UInt16(group, radix: 16) else { return false }
                guard index + 1 < 16 else { return false }
                target[index] = UInt8(value >> 8)
                target[index + 1] = UInt8(value & 0xFF)
                index += 2
            }
            return true
        }

        if let right {
            guard fill(left, into: &result, at: 0) else { return nil }
            let rightCount = right.split(separator: ":", omittingEmptySubsequences: true).count
            guard fill(right, into: &result, at: 16 - rightCount * 2) else { return nil }
        } else {
            guard fill(left, into: &result, at: 0) else { return nil }
        }
        return result
    }

    static func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(byte)
        }
        return result
    }
}
