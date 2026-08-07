import ServiceManagement
import SwiftUI

/// Native Settings window.
struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("startMonitoring") private var startMonitoring = true
    @AppStorage("pauseOnBattery") private var pauseOnBattery = false
    @AppStorage("updateFrequency") private var updateFrequency = 0.25
    @AppStorage("retentionDays") private var retentionDays = 30
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("compactDensity") private var compactDensity = false
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("showAppIcons") private var showAppIcons = true
    @AppStorage("showASN") private var showASN = true
    @AppStorage("metadataOnly") private var metadataOnly = true
    @AppStorage("dnsCorrelation") private var dnsCorrelation = true
    @AppStorage("reverseDNS") private var reverseDNS = true
    @AppStorage("captureInterface") private var captureInterface = "en0"
    @AppStorage("maxCaptureSize") private var maxCaptureSize = 500.0
    @AppStorage("autoDeleteCaptures") private var autoDeleteCaptures = true
    @AppStorage("includePayloads") private var includePayloads = false
    @AppStorage("redactHTTPHeaders") private var redactHTTPHeaders = true
    @AppStorage("processMetadata") private var processMetadata = true
    @AppStorage("tlsMetadata") private var tlsMetadata = true
    @AppStorage("connectionHistory") private var connectionHistory = true
    @AppStorage("packetCounters") private var packetCounters = true
    @AppStorage("ignoreLocal") private var ignoreLocal = false
    @AppStorage("debugLogging") private var debugLogging = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            monitoringTab
                .tabItem { Label("Monitoring", systemImage: "antenna.radiowaves.left.and.right") }
            captureTab
                .tabItem { Label("Capture", systemImage: "record.circle") }
            exclusionsTab
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 420)
        .onChange(of: launchAtLogin) { _, enabled in
            // real launch-at-login registration for the bundled app
            if enabled {
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }

    private var generalTab: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
            Toggle("Start monitoring automatically", isOn: $startMonitoring)
            Toggle("Pause monitoring when on battery", isOn: $pauseOnBattery)
            Picker("Update frequency", selection: $updateFrequency) {
                Text("0.25 s").tag(0.25)
                Text("0.5 s").tag(0.5)
                Text("1 s").tag(1.0)
                Text("2 s").tag(2.0)
                Text("5 s").tag(5.0)
            }
            .onChange(of: updateFrequency) { _, newValue in
                NotificationCenter.default.post(name: .netglassUpdateFrequency, object: newValue)
            }
            Picker("History retention", selection: $retentionDays) {
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("Forever").tag(0)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Density", selection: $compactDensity) {
                Text("Comfortable").tag(false)
                Text("Compact").tag(true)
            }
            Toggle("Reduce motion", isOn: $reduceMotion)
            Toggle("Show application icons", isOn: $showAppIcons)
            Toggle("Show country / ASN metadata", isOn: $showASN)
        }
        .formStyle(.grouped)
    }

    private var monitoringTab: some View {
        Form {
            Toggle("Metadata-only mode", isOn: $metadataOnly)
                .help("Never retain packet payloads")
            Toggle("Process metadata collection", isOn: $processMetadata)
            Toggle("DNS correlation", isOn: $dnsCorrelation)
            Toggle("Reverse DNS lookup", isOn: $reverseDNS)
            Toggle("TLS metadata extraction", isOn: $tlsMetadata)
            Toggle("Connection history", isOn: $connectionHistory)
            Toggle("Packet counters", isOn: $packetCounters)
        }
        .formStyle(.grouped)
    }

    private var captureTab: some View {
        Form {
            Picker("Default interface", selection: $captureInterface) {
                Text("en0 (Wi-Fi)").tag("en0")
                Text("en1").tag("en1")
                Text("Any").tag("any")
            }
            Picker("Maximum capture size", selection: $maxCaptureSize) {
                Text("100 MB").tag(100.0)
                Text("500 MB").tag(500.0)
                Text("2 GB").tag(2_000.0)
            }
            Toggle("Automatically delete old captures", isOn: $autoDeleteCaptures)
            Toggle("Include packet payloads", isOn: $includePayloads)
            Toggle("Redact sensitive HTTP headers", isOn: $redactHTTPHeaders)
        }
        .formStyle(.grouped)
    }

    private var exclusionsTab: some View {
        Form {
            LabeledContent("Excluded applications") { Text("None").foregroundStyle(.secondary) }
            LabeledContent("Excluded processes") { Text("None").foregroundStyle(.secondary) }
            LabeledContent("Excluded domains") { Text("None").foregroundStyle(.secondary) }
            LabeledContent("Excluded IP ranges") { Text("None").foregroundStyle(.secondary) }
            Toggle("Ignore local traffic", isOn: $ignoreLocal)
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            LabeledContent("DNS correlation window") { Text("30 s").foregroundStyle(.secondary) }
            LabeledContent("Process refresh interval") { Text("1 s").foregroundStyle(.secondary) }
            LabeledContent("Packet decoder backend") { Text("Native").foregroundStyle(.secondary) }
            Toggle("Debug logging", isOn: $debugLogging)
            LabeledContent("Database location") {
                Text("~/Library/Application Support/Netglass")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            Button("Export Diagnostics") {}
            Button("Reset Local Data", role: .destructive) {}
        }
        .formStyle(.grouped)
    }
}
