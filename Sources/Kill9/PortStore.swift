import Foundation
import SwiftUI
import AppKit
import ServiceManagement

struct Toast: Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

final class PortStore: ObservableObject {
    @Published private(set) var ports: [PortProcess] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var killing: Set<pid_t> = []
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var toast: Toast?
    @Published private(set) var favorites: Set<Int> =
        (UserDefaults.standard.array(forKey: "favoritePorts") as? [Int]).map(Set.init) ?? PortStore.defaultFavorites

    /// Common dev-server, database and debugger ports.
    static let defaultFavorites: Set<Int> = [
        3000, 3001, 4000, 4200, 5000, 5173, 5174, 8000, 8080, 8081, 8888, 9000, // web dev servers
        3306, 5432, 6379, 27017, 9200,                                       // databases / search
        9229, 5672, 15672, 9092,                                             // node inspector, queues
    ]

    private var timer: Timer?
    private var scanInFlight = false

    init() { refresh() }

    // MARK: Scanning

    func refresh() {
        guard !scanInFlight else { return }
        scanInFlight = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PortScanner.scan() }
            DispatchQueue.main.async {
                self.scanInFlight = false
                switch result {
                case .success(let list):
                    self.errorMessage = nil
                    if list != self.ports {
                        withAnimation(.easeOut(duration: 0.2)) { self.ports = list }
                    }
                case .failure(let error):
                    self.errorMessage = "Couldn't run lsof: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Live refresh only while the popover is open.
    func startAutoRefresh() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Killing

    func kill(_ items: [PortProcess], force: Bool = false) {
        let pids = Set(items.map(\.pid)).subtracting(killing)
        guard !pids.isEmpty else { return }
        killing.formUnion(pids)

        let names = Set(items.map(\.command)).sorted().joined(separator: ", ")
        let portList = Set(items.map(\.port)).sorted().map { ":\($0)" }.joined(separator: " ")

        DispatchQueue.global(qos: .userInitiated).async {
            let errors = pids.compactMap { PortScanner.terminate(pid: $0, force: force) }
            DispatchQueue.main.async {
                self.killing.subtract(pids)
                if errors.isEmpty {
                    self.show("Killed \(names) on \(portList)")
                } else {
                    self.show(errors.joined(separator: "\n"), isError: true)
                }
                self.refresh()
            }
        }
    }

    // MARK: Favorites

    func toggleFavorite(_ port: Int) {
        if favorites.remove(port) == nil { favorites.insert(port) }
        UserDefaults.standard.set(favorites.sorted(), forKey: "favoritePorts")
    }

    func resetFavorites() {
        favorites = Self.defaultFavorites
        UserDefaults.standard.removeObject(forKey: "favoritePorts")
    }

    // MARK: Misc

    func show(_ message: String, isError: Bool = false) {
        let toast = Toast(message: message, isError: isError)
        self.toast = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 4 : 2.5)) { [weak self] in
            if self?.toast == toast { self?.toast = nil }
        }
    }

    func copy(_ text: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Copied \(label)")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            show("Login item: \(error.localizedDescription)", isError: true)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
