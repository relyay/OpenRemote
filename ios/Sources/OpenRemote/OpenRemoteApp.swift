import SwiftUI
import UIKit

@main
struct OpenRemoteApp: App {
    @UIApplicationDelegateAdaptor(OrientationDelegate.self) private var orientationDelegate
    @State private var session = Session()
    @State private var layout = LayoutStore()
    @State private var library = LayoutLibrary()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(layout)
                .environment(library)
                .onAppear { applyOrientation(.portrait) }
        }
    }
}

final class OrientationDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationDelegate.mask
    }
}

@MainActor
func applyOrientation(_ mask: UIInterfaceOrientationMask) {
    OrientationDelegate.mask = mask
    let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        scene.requestGeometryUpdate(preferences) { _ in }
        refreshOrientations(scene.keyWindow?.rootViewController)
    }
}

@MainActor
private func refreshOrientations(_ controller: UIViewController?) {
    guard let controller else { return }
    controller.setNeedsUpdateOfSupportedInterfaceOrientations()
    for child in controller.children {
        refreshOrientations(child)
    }
}

struct RootView: View {
    @Environment(Session.self) private var session
    @State private var scanning = false

    var body: some View {
        Group {
            if session.playing {
                MainShell()
            } else if scanning {
                ScannerView(onManual: { scanning = false }) { host, port in
                    session.host = host
                    session.portText = port
                    session.connect()
                    scanning = false
                }
            } else {
                ConnectView(onScan: { scanning = true })
            }
        }
        .onAppear { applyOrientation(.portrait) }
        .onChange(of: session.playing) { _, playing in
            if !playing { applyOrientation(.portrait) }
        }
    }
}

struct ConnectView: View {
    @Environment(Session.self) private var session
    var onScan: () -> Void

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 18) {
            Text("OpenRemote")
                .font(.largeTitle.bold())
            Text(L10n.connectTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("192.168.1.10", text: $session.host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .padding()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            TextField(L10n.port, text: $session.portText)
                .keyboardType(.numberPad)
                .padding()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
            Button(L10n.connect) {
                session.connect()
            }
            .buttonStyle(.glassProminent)
            .disabled(session.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(L10n.scanCode, action: onScan)
                .buttonStyle(.glass)
            if session.linkState != .offline {
                Text(session.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(screenBackground)
        .onAppear { applyOrientation(.portrait) }
    }
}

var screenBackground: some View {
    LinearGradient(
        colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
        startPoint: .top,
        endPoint: .bottom
    )
    .ignoresSafeArea()
}
