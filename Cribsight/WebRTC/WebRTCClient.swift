import Foundation
import WebRTC

/// Manages a single recv-only WebRTC connection to one go2rtc stream.
///
/// Flow: add recv-only audio+video transceivers → create offer → set local
/// description → wait for ICE gathering to finish (so the offer carries our LAN
/// host candidate) → POST the offer to go2rtc (WHEP) → set the remote answer →
/// attach renderers to the remote video track.
final class WebRTCClient: NSObject {

    let streamName: String
    private let signaling: WHEPSignaling
    private let startMuted: Bool

    private var peerConnection: RTCPeerConnection?
    private(set) var remoteVideoTrack: RTCVideoTrack?
    private(set) var remoteAudioTrack: RTCAudioTrack?

    /// Renderers persist across reconnects and are re-attached to each new track.
    private var renderers: [RTCVideoRenderer] = []

    private var didSendOffer = false
    private var gatheringFallbackTimer: Timer?
    private var isMuted: Bool

    var onStateChange: ((PaneConnectionState) -> Void)?
    var onVideoTrack: ((RTCVideoTrack) -> Void)?

    private(set) var state: PaneConnectionState = .idle {
        didSet {
            guard oldValue != state else { return }
            DispatchQueue.main.async { self.onStateChange?(self.state) }
        }
    }

    init(streamName: String, startMuted: Bool, signaling: WHEPSignaling) {
        self.streamName = streamName
        self.signaling = signaling
        self.startMuted = startMuted
        self.isMuted = startMuted
        super.init()
    }

    // MARK: - Public control

    func connect() {
        teardownConnection()
        state = .connecting
        didSendOffer = false

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.continualGatheringPolicy = .gatherOnce
        config.iceServers = []   // LAN only — go2rtc supplies host candidates

        let pcConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )

        guard let pc = RTCFactory.shared.peerConnection(with: config,
                                                        constraints: pcConstraints,
                                                        delegate: self) else {
            fail("Could not create the connection.")
            return
        }
        peerConnection = pc

        // Request recv-only audio + video. With Unified Plan these constraints
        // make WebRTC create the recv-only transceivers for us.
        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ],
            optionalConstraints: nil)
        pc.offer(for: offerConstraints) { [weak self] sdp, error in
            guard let self = self else { return }
            if let error = error { self.fail("Offer failed: \(error.localizedDescription)"); return }
            guard let sdp = sdp else { self.fail("No offer produced."); return }
            pc.setLocalDescription(sdp) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.fail("setLocalDescription failed: \(error.localizedDescription)"); return
                }
                self.startGatheringFallback()
            }
        }
    }

    func disconnect() {
        teardownConnection()
        state = .idle
    }

    func add(renderer: RTCVideoRenderer) {
        renderers.append(renderer)
        remoteVideoTrack?.add(renderer)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        remoteAudioTrack?.isEnabled = !muted
    }

    func statistics(_ completion: @escaping (RTCStatisticsReport) -> Void) {
        peerConnection?.statistics(completionHandler: completion)
    }

    // MARK: - Internal

    private func teardownConnection() {
        gatheringFallbackTimer?.invalidate()
        gatheringFallbackTimer = nil
        if let track = remoteVideoTrack {
            renderers.forEach { track.remove($0) }
        }
        remoteVideoTrack = nil
        remoteAudioTrack = nil
        peerConnection?.close()
        peerConnection = nil
    }

    private func fail(_ message: String) {
        state = .failed(message)
    }

    private func startGatheringFallback() {
        DispatchQueue.main.async {
            self.gatheringFallbackTimer?.invalidate()
            // Host candidates gather almost instantly on a LAN; if "complete"
            // never fires, ship what we have after a short grace period.
            self.gatheringFallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.5,
                                                               repeats: false) { [weak self] _ in
                self?.sendOffer(force: true)
            }
        }
    }

    private func sendOffer(force: Bool) {
        guard !didSendOffer else { return }
        guard let pc = peerConnection, let local = pc.localDescription else { return }
        if !force && pc.iceGatheringState != .complete { return }

        didSendOffer = true
        gatheringFallbackTimer?.invalidate()
        gatheringFallbackTimer = nil

        signaling.exchange(offer: local.sdp, streamName: streamName) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.fail(error.localizedDescription)
            case .success(let answerSDP):
                guard self.peerConnection != nil else { return }   // torn down meanwhile
                let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
                pc.setRemoteDescription(answer) { [weak self] error in
                    guard let self = self else { return }
                    if let error = error {
                        self.fail("setRemoteDescription failed: \(error.localizedDescription)")
                        return
                    }
                    self.captureRemoteTracks()
                }
            }
        }
    }

    private func captureRemoteTracks() {
        guard let pc = peerConnection else { return }
        for transceiver in pc.transceivers {
            guard let track = transceiver.receiver.track else { continue }
            if let video = track as? RTCVideoTrack {
                remoteVideoTrack = video
                renderers.forEach { video.add($0) }
                DispatchQueue.main.async { self.onVideoTrack?(video) }
            } else if let audio = track as? RTCAudioTrack {
                remoteAudioTrack = audio
                audio.isEnabled = !isMuted
            }
        }
    }

    private func handleICE(_ newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed:
            state = .live
        case .disconnected:
            if state.isLive { state = .reconnecting }
        case .failed:
            state = .failed("Connection lost.")
        default:
            break
        }
    }
}

// MARK: - RTCPeerConnectionDelegate (all required methods)

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        handleICE(newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete {
            DispatchQueue.main.async { self.sendOffer(force: false) }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
