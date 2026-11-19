import Foundation
import CoreMIDI

/// Zero-configuration MIDI: every MIDI source (USB, Bluetooth, network session, other apps' virtual ports)
/// is connected automatically as soon as it appears, and ChordPilot publishes its own virtual ports
/// ("ChordPilot In" / "ChordPilot Out") so DAWs and apps such as AUM or Logic can find it without setup.
final class MIDIManager: ObservableObject {

    @Published private(set) var inputNames: [String] = []
    @Published private(set) var outputNames: [String] = []
    /// Also send generated MIDI (genre player, on-screen keys) to hardware outputs.
    @Published var sendToHardware = true

    /// Receives every channel message (status, data1, data2) from every connected source.
    var onMessage: ((UInt8, UInt8, UInt8) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var virtualSource = MIDIEndpointRef()
    private var virtualDestination = MIDIEndpointRef()
    private var connected = Set<MIDIUniqueID>()
    private let parserLock = NSLock()
    private var parsers: [MIDIUniqueID: MIDIByteParser] = [:]

    init() {
        MIDIClientCreateWithBlock("ChordPilot" as CFString, &client) { [weak self] notification in
            let id = notification.pointee.messageID
            if id == .msgSetupChanged || id == .msgObjectAdded || id == .msgObjectRemoved {
                DispatchQueue.main.async { self?.refresh() }
            }
        }
        MIDIInputPortCreateWithBlock(client, "ChordPilot Input" as CFString, &inputPort) { [weak self] list, srcRef in
            let uid = srcRef.map { Int32(truncatingIfNeeded: Int(bitPattern: $0)) } ?? 0
            self?.receive(list, sourceID: uid)
        }
        MIDIOutputPortCreate(client, "ChordPilot Output" as CFString, &outputPort)
        MIDISourceCreate(client, "ChordPilot Out" as CFString, &virtualSource)
        MIDIDestinationCreateWithBlock(client, "ChordPilot In" as CFString, &virtualDestination) { [weak self] list, _ in
            self?.receive(list, sourceID: -1)
        }
        // Allow the network session (Wi-Fi MIDI from a Mac) to be seen automatically.
        let session = MIDINetworkSession.default()
        session.isEnabled = true
        session.connectionPolicy = .anyone
        refresh()
    }

    deinit {
        MIDIClientDispose(client)
    }

    /// Connects every available source. Called automatically whenever the MIDI setup changes.
    func refresh() {
        var names: [String] = []
        var stillPresent = Set<MIDIUniqueID>()
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            guard src != virtualSource else { continue }
            let uid = uniqueID(src)
            stillPresent.insert(uid)
            if !connected.contains(uid) {
                // The connection refCon carries the unique ID so each source gets its own running-status parser.
                let refCon = UnsafeMutableRawPointer(bitPattern: Int(uid))
                if MIDIPortConnectSource(inputPort, src, refCon) == noErr { connected.insert(uid) }
            }
            names.append(displayName(src))
        }
        connected = connected.intersection(stillPresent)
        inputNames = names

        var outs: [String] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            if d != virtualDestination { outs.append(displayName(d)) }
        }
        outputNames = outs
    }

    // MARK: Sending

    /// Sends a MIDI message to the virtual "ChordPilot Out" port and (optionally) to all hardware outputs.
    func send(_ bytes: UnsafePointer<UInt8>, length: Int) {
        var list = MIDIPacketList()
        let packet = MIDIPacketListInit(&list)
        _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, length, bytes)
        MIDIReceived(virtualSource, &list)
        guard sendToHardware else { return }
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            if d != virtualDestination { MIDISend(outputPort, d, &list) }
        }
    }

    // MARK: Receiving

    private func receive(_ list: UnsafePointer<MIDIPacketList>, sourceID: MIDIUniqueID) {
        parserLock.lock()
        let parser = parsers[sourceID] ?? MIDIByteParser()
        parsers[sourceID] = parser
        parserLock.unlock()
        for packet in list.unsafeSequence() {
            let length = Int(packet.pointee.length)
            withUnsafeBytes(of: packet.pointee.data) { raw in
                for b in raw.prefix(length) {
                    if let m = parser.feed(b) { onMessage?(m.0, m.1, m.2) }
                }
            }
        }
    }

    private func uniqueID(_ obj: MIDIObjectRef) -> MIDIUniqueID {
        var id: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(obj, kMIDIPropertyUniqueID, &id)
        return id
    }

    private func displayName(_ obj: MIDIObjectRef) -> String {
        var name: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &name) == noErr, let n = name {
            return n.takeRetainedValue() as String
        }
        return "MIDI"
    }
}

/// Turns a raw MIDI byte stream into channel messages (handles running status, ignores SysEx and real-time).
final class MIDIByteParser {
    private var status: UInt8 = 0
    private var data: [UInt8] = []
    private var inSysEx = false

    func feed(_ b: UInt8) -> (UInt8, UInt8, UInt8)? {
        if b >= 0xF8 { return nil }                 // real-time (clock etc.)
        if b == 0xF0 { inSysEx = true; return nil }
        if b == 0xF7 { inSysEx = false; return nil }
        if inSysEx { return nil }
        if b & 0x80 != 0 {
            status = b >= 0xF0 ? 0 : b
            data.removeAll(keepingCapacity: true)
            return nil
        }
        guard status != 0 else { return nil }
        data.append(b)
        let type = status & 0xF0
        let needed = (type == 0xC0 || type == 0xD0) ? 1 : 2
        guard data.count >= needed else { return nil }
        let msg = (status, data[0], needed == 2 ? data[1] : 0)
        data.removeAll(keepingCapacity: true)   // keep status for running status
        return msg
    }
}
