import CoreAudioKit
import SwiftUI
import AVFoundation

/// Entry point of the AUv3 extension: creates the Audio Unit for the host and shows the SwiftUI interface.
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {

    private var audioUnit: ChordPilotAudioUnit?
    private var hosting: UIHostingController<ChordPilotView>?
    private var controller: ChordPilotController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1)
        preferredContentSize = CGSize(width: 1024, height: 560)
        if let au = audioUnit { connectUI(to: au) }
    }

    // Called by the host, usually on a background thread.
    nonisolated public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try ChordPilotAudioUnit(componentDescription: componentDescription, options: [])
        Task { @MainActor [weak self] in self?.install(au) }
        return au
    }

    private func install(_ au: ChordPilotAudioUnit) {
        audioUnit = au
        if isViewLoaded { connectUI(to: au) }
    }

    private func connectUI(to au: ChordPilotAudioUnit) {
        guard hosting == nil else { return }
        let c = ChordPilotController()
        c.attach(au)
        controller = c
        let host = UIHostingController(rootView: ChordPilotView(controller: c))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        hosting = host
    }

    deinit {
        let c = controller
        DispatchQueue.main.async { c?.detach() }
    }
}
