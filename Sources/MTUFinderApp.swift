import SwiftUI

@main
struct MTUFinderApp: App {
    init() {
        // Apply the persisted language choice before the first view renders.
        let saved = UserDefaults.standard.string(forKey: Lang.storageKey) ?? AppLanguage.system.rawValue
        Lang.apply(saved)
    }

    var body: some Scene {
        WindowGroup("JumpIT MTU Finder") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
