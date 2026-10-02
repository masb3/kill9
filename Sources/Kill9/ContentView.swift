import SwiftUI
import AppKit

enum ViewMode: String { case list, apps }
enum ProtoFilter: String, CaseIterable { case favorites = "Favorites", tcp = "TCP", udp = "UDP", all = "All" }

/// All ports held by one app (helper processes inside the same .app are merged).
struct AppGroup: Identifiable {
    let id: String
    let name: String
    let items: [PortProcess]

    var summary: String {
        var seen = Set<String>()
        let ports = items
            .map { $0.proto == .udp ? ":\($0.port)/udp" : ":\($0.port)" }
            .filter { seen.insert($0).inserted }
        let pidCount = Set(items.map(\.pid)).count
        return ports.joined(separator: " ") + (pidCount > 1 ? " · \(pidCount) processes" : "")
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: PortStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("viewMode") private var viewMode: ViewMode = .list
    @AppStorage("protoFilter") private var protoFilter: ProtoFilter = .favorites

    // MARK: Filtering

    private var normalizedQuery: String {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.hasPrefix(":") { q.removeFirst() }
        return q
    }

    /// The query as a valid port number, if it is one.
    private var queryPort: Int? {
        guard let port = Int(normalizedQuery), (1...65535).contains(port) else { return nil }
        return port
    }

    private var protocolFiltered: [PortProcess] {
        switch protoFilter {
        case .all: return store.ports
        case .tcp: return store.ports.filter { $0.proto == .tcp }
        case .udp: return store.ports.filter { $0.proto == .udp }
        case .favorites: return store.ports.filter { store.favorites.contains($0.port) }
        }
    }

    private var filtered: [PortProcess] {
        let q = normalizedQuery
        guard !q.isEmpty else { return protocolFiltered }
        return protocolFiltered.filter {
            String($0.port).hasPrefix(q)
                || $0.command.lowercased().contains(q)
                || $0.appName.lowercased().contains(q)
                || String($0.pid) == q
        }
    }

    private var groups: [AppGroup] {
        Dictionary(grouping: filtered, by: \.groupKey)
            .map { AppGroup(id: $0.key, name: $0.value[0].appName, items: $0.value) }
            .sorted {
                ($0.items.map(\.port).min() ?? 0, $0.name) < ($1.items.map(\.port).min() ?? 0, $1.name)
            }
    }

    /// When the query is an exact port that's in use, offer one-tap "kill port".
    private var exactPortTargets: (port: Int, items: [PortProcess])? {
        guard let port = Int(normalizedQuery) else { return nil }
        let items = protocolFiltered.filter { $0.port == port }
        return items.isEmpty ? nil : (port, items)
    }

    private func killExactPort() {
        guard let target = exactPortTargets else { return }
        store.kill(target.items)
        query = ""
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            controls
            if let target = exactPortTargets { killPortBanner(target.port, count: target.items.count) }
            Divider()
            content.frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 400, height: 520)
        .overlay(alignment: .bottom) { toastView }
        .animation(.easeOut(duration: 0.2), value: store.toast)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.startAutoRefresh()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            store.stopAutoRefresh()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "9.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.red)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "kill -9")
                    .font(.system(.headline, design: .monospaced))
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")
        }
        .padding(12)
    }

    private var subtitle: String {
        let tcp = store.ports.filter { $0.proto == .tcp }.count
        let udp = store.ports.count - tcp
        if tcp + udp == 0 { return "No open ports" }
        return "\(tcp) TCP listening · \(udp) UDP bound"
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Port, app, process or PID", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit(killExactPort)
            if let port = queryPort {
                let isFavorite = store.favorites.contains(port)
                Button { store.toggleFavorite(port) } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.plain)
                .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
                .help(isFavorite ? "Remove :\(port) from Favorites" : "Add :\(port) to Favorites")
            }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Protocol", selection: $protoFilter) {
                ForEach(ProtoFilter.allCases, id: \.self) { filter in
                    if filter == .favorites {
                        Image(systemName: "star.fill").tag(filter)
                    } else {
                        Text(verbatim: filter.rawValue).tag(filter)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .contextMenu {
                Button("Reset Favorites to Defaults") { store.resetFavorites() }
            }

            Spacer()

            Picker("View", selection: $viewMode) {
                Image(systemName: "list.bullet").tag(ViewMode.list)
                Image(systemName: "square.stack.3d.up").tag(ViewMode.apps)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
            .help("Flat list / Group by app")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func killPortBanner(_ port: Int, count: Int) -> some View {
        Button(action: killExactPort) {
            HStack {
                Image(systemName: "bolt.fill")
                Text(verbatim: "Kill everything on :\(port)" + (count > 1 ? " (\(count))" : ""))
                    .fontWeight(.semibold)
                Spacer()
                Text(verbatim: "↩").opacity(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.gradient))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.errorMessage {
            placeholder(icon: "exclamationmark.triangle", title: "Scan failed", detail: error)
        } else if filtered.isEmpty {
            if normalizedQuery.isEmpty && protoFilter == .favorites {
                placeholder(icon: "star",
                            title: "No favorite ports in use",
                            detail: "Type a port number and click ☆, or right-click any port.")
            } else if normalizedQuery.isEmpty {
                placeholder(icon: "checkmark.seal",
                            title: "All ports are free",
                            detail: "Start a dev server and it will show up here.")
            } else if Int(normalizedQuery) != nil {
                placeholder(icon: "checkmark.circle",
                            title: "Port :\(normalizedQuery) is free",
                            detail: "Nothing is using it.")
            } else {
                placeholder(icon: "magnifyingglass",
                            title: "No matches",
                            detail: "Nothing matches “\(query)”.")
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    switch viewMode {
                    case .list:
                        ForEach(filtered) { item in PortRow(item: item) }
                    case .apps:
                        ForEach(groups) { group in AppGroupView(group: group) }
                    }
                }
                .padding(6)
            }
        }
    }

    private func placeholder(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 32)).foregroundStyle(.tertiary)
            Text(verbatim: title).font(.headline)
            Text(verbatim: detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: Binding(
                get: { store.launchAtLogin },
                set: { store.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = store.toast {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(toast.isError ? Color.orange : Color.green)
                Text(verbatim: toast.message).font(.callout).lineLimit(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 44)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
        }
    }
}

// MARK: - App group

struct AppGroupView: View {
    let group: AppGroup
    @EnvironmentObject private var store: PortStore
    @State private var expanded = true
    @State private var hovering = false
    @State private var confirmKill = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12)
                ProcessIcon(item: group.items[0])
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: group.name).fontWeight(.semibold).lineLimit(1)
                    Text(verbatim: group.summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                killAllButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(hovering ? 0.08 : 0.04)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            }

            if expanded {
                ForEach(group.items) { item in
                    PortRow(item: item, showIcon: false)
                        .padding(.leading, 20)
                }
            }
        }
        .padding(.bottom, 4)
    }

    /// Two-step: first click arms it, second click (within 3s) kills.
    private var killAllButton: some View {
        Button {
            if confirmKill {
                confirmKill = false
                store.kill(group.items)
            } else {
                confirmKill = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmKill = false }
            }
        } label: {
            Text(verbatim: confirmKill ? "Confirm" : (group.items.count > 1 ? "Kill all" : "Kill"))
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(confirmKill ? Color.red : Color.primary.opacity(0.08)))
                .foregroundStyle(confirmKill ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help("Kill every process of \(group.name) shown here")
    }
}

// MARK: - Row

struct PortRow: View {
    let item: PortProcess
    var showIcon = true
    @EnvironmentObject private var store: PortStore
    @State private var hovering = false

    private var isKilling: Bool { store.killing.contains(item.pid) }
    private var tint: Color { item.proto == .udp ? .orange : .accentColor }

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: String(item.port))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(minWidth: 52)
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(Capsule().fill(tint.opacity(0.15)))
                .foregroundStyle(tint)
                .overlay(alignment: .topTrailing) {
                    if store.favorites.contains(item.port) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.yellow)
                            .offset(x: 2, y: -2)
                    }
                }

            if showIcon { ProcessIcon(item: item) }

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.command)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .help(item.path ?? item.command)

            Spacer(minLength: 4)

            if hovering && !isKilling && item.proto == .tcp {
                Button { open() } label: { Image(systemName: "safari") }
                    .buttonStyle(.borderless)
                    .help("Open http://localhost:" + String(item.port))
            }

            Button { store.kill([item]) } label: {
                if isKilling {
                    ProgressView().controlSize(.small).frame(width: 18, height: 18)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(hovering ? Color.red : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .disabled(isKilling)
            .help("Kill (graceful, then force after 1.5s)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .opacity(isKilling ? 0.5 : 1)
        .contextMenu { menu }
    }

    private var details: String {
        var parts = [item.proto.rawValue, "PID \(item.pid)"]
        if !item.user.isEmpty { parts.append(item.user) }
        parts.append(item.isLocalOnly ? "localhost only" : "all interfaces")
        return parts.joined(separator: " · ")
    }

    private func open() {
        if let url = URL(string: "http://localhost:\(item.port)") { NSWorkspace.shared.open(url) }
    }

    @ViewBuilder
    private var menu: some View {
        if item.proto == .tcp {
            Button("Open in Browser") { open() }
            Divider()
        }
        Button(store.favorites.contains(item.port) ? "Remove from Favorites" : "Add to Favorites") {
            store.toggleFavorite(item.port)
        }
        Divider()
        Button("Copy Port") { store.copy(String(item.port), label: "port") }
        Button("Copy PID") { store.copy(String(item.pid), label: "PID") }
        Button("Copy Kill Command") { store.copy(item.killCommand, label: "kill command") }
        if let path = item.path {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        Divider()
        Button("Kill") { store.kill([item]) }
        Button("Force Kill (kill -9)") { store.kill([item], force: true) }
    }
}

// MARK: - Icon

struct ProcessIcon: View {
    let item: PortProcess

    var body: some View {
        Group {
            if let image = IconCache.icon(for: item) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
    }
}

enum IconCache {
    private static var cache: [String: NSImage?] = [:]

    /// Real app icon when the process lives inside a .app bundle; nil for CLI tools.
    static func icon(for item: PortProcess) -> NSImage? {
        let key = item.groupKey
        if let cached = cache[key] { return cached }

        var image: NSImage?
        if let bundle = item.appBundlePath {
            image = NSWorkspace.shared.icon(forFile: bundle)
        } else if let app = NSRunningApplication(processIdentifier: item.pid), app.bundleURL != nil {
            image = app.icon
        }
        cache[key] = image
        return image
    }
}
