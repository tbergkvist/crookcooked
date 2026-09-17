import SwiftUI

@main
struct CrookcookedPhoneApp: App {
    @UIApplicationDelegateAdaptor(CrookcookedPhoneAppDelegate.self) private var appDelegate
    @StateObject private var model = PhoneModel()

    var body: some Scene {
        WindowGroup {
            PhoneDashboardView(model: model)
        }
    }
}
