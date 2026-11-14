import AVFoundation
import AppKit
import SwiftUI

// MARK: - 视频层

/// 把 `AVPlayerLayer` 塞进 SwiftUI。
///
/// 桌宠窗口本身是 `isOpaque = false` + 透明背景的 `NSPanel`，
/// 所以只要图层别自己画底色，HEVC 的 alpha 通道就能透出桌面。
///
/// 用 `AVQueuePlayer` + `AVPlayerLooper` 做循环：`AVPlayerLooper` 会提前把
/// 下一份 item 排进队列，接缝处不会闪一下黑。
struct PetVideoView: NSViewRepresentable {
    /// 要播的片段。`nil` 表示不播视频（退回立绘）。
    var clip: PetClip?
    /// 暂停（窗口藏起来、或者用户关掉了动效）。
    var isPaused: Bool
    /// 一次性片段播完时回调。
    var onFinished: (() -> Void)?
    /// 视频起不来（素材坏了、解码器不支持）时回调，让上层退回立绘。
    var onUnavailable: (() -> Void)?

    func makeNSView(context: Context) -> PetVideoHostView {
        let view = PetVideoHostView()
        view.onFinished = onFinished
        view.onUnavailable = onUnavailable
        return view
    }

    func updateNSView(_ view: PetVideoHostView, context: Context) {
        view.onFinished = onFinished
        view.onUnavailable = onUnavailable
        view.show(clip: clip, paused: isPaused)
    }

    static func dismantleNSView(_ view: PetVideoHostView, coordinator: ()) {
        view.stop()
    }
}

// MARK: - 承载视图

/// 只负责播片，不管布局。
@MainActor
final class PetVideoHostView: NSView {
    var onFinished: (() -> Void)?
    var onUnavailable: (() -> Void)?

    private let playerLayer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var current: PetClip?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var readyPoll: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false

        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        playerLayer.isOpaque = false
        layer?.addSublayer(playerLayer)

        player.isMuted = true
        // 桌宠不该抢音频会话，也不该因为别的 App 在放歌就停。
        player.actionAtItemEnd = .pause
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        // 关掉隐式动画，否则改窗口大小时图层会「飘」一下。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    // MARK: 播放

    func show(clip: PetClip?, paused: Bool) {
        guard let clip, let url = clip.url else {
            stop()
            return
        }

        if clip != current {
            load(clip: clip, url: url)
        }

        if paused {
            player.pause()
        } else if player.rate == 0 {
            player.play()
        }
    }

    private func load(clip: PetClip, url: URL) {
        current = clip
        teardownObservers()

        let item = AVPlayerItem(url: url)
        looper = nil
        player.removeAllItems()

        if clip.loops {
            looper = AVPlayerLooper(player: player, templateItem: item)
        } else {
            player.insert(item, after: nil)
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: item,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onFinished?()
                }
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            MainActor.assumeIsolated {
                self?.onUnavailable?()
            }
        }

        // 兜底：两秒还没出画面就当它放不了，让上层退回立绘。
        readyPoll?.cancel()
        readyPoll = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            if !self.playerLayer.isReadyForDisplay, self.current == clip {
                self.onUnavailable?()
            }
        }
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        looper = nil
        current = nil
        teardownObservers()
    }

    private func teardownObservers() {
        readyPoll?.cancel()
        readyPoll = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}
