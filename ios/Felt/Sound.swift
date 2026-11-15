/* The table's sounds: the same CC0 recordings as the web build (sounds/, credited in CREDITS.md),
   one take per impact picked so the same take never plays twice running, louder and brighter with
   the impact speed. The audio session is playback, as the page sets it, so the silent switch does
   not mute the table. A small pool of player nodes bounds the voices. */
import AVFoundation
import FeltSim
import UIKit

@MainActor
final class Sound {
  private let engine = AVAudioEngine()
  private var players: [AVAudioPlayerNode] = []
  private var next = 0
  private var takes: [String: [AVAudioPCMBuffer]] = [:]
  private var last: [String: Int] = [:]
  private let haptic = UIImpactFeedbackGenerator(style: .light)
  private var ok = false

  init() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    guard let dir = Bundle.main.url(forResource: "sounds", withExtension: nil) else { return }
    var format: AVAudioFormat?
    for (kind, names) in [("ball", (1...10).map { "ball-\($0)" }), ("rail", (1...3).map { "rail-\($0)" }),
                          ("pocket", (1...3).map { "pocket-\($0)" }), ("cue", (1...4).map { "cue-\($0)" }), ("break", ["break-1"])] {
      for n in names {
        guard let f = try? AVAudioFile(forReading: dir.appendingPathComponent(n + ".wav")),
              let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: b)) != nil else { continue }
        format = format ?? f.processingFormat
        takes[kind, default: []].append(b)
      }
    }
    guard let fmt = format else { return }
    for _ in 0..<10 {
      let p = AVAudioPlayerNode()
      engine.attach(p); engine.connect(p, to: engine.mainMixerNode, format: fmt)
      players.append(p)
    }
    ok = (try? engine.start()) != nil
    for p in players { p.play() }
  }

  func hit(_ h: Hit) {
    guard Prefs.sound else { if h.kind == "pocket" && Prefs.haptics { haptic.impactOccurred(intensity: min(1, 0.4 + h.v / 3)) }; return }
    switch h.kind {
    case "ball": play("ball", gain: h.v / 3)
    case "rail", "jaw", "land": play("rail", gain: h.v / 3.5)
    case "pocket": play("pocket", gain: 0.35 + h.v / 3); if Prefs.haptics { haptic.impactOccurred(intensity: min(1, 0.4 + h.v / 3)) }
    case "cue": play(h.v > 6 ? "break" : "cue", gain: 0.25 + h.v / 6)
    default: break
    }
  }

  private func play(_ kind: String, gain: Double) {
    guard ok, let list = takes[kind], !list.isEmpty, gain > 0.01 else { return }
    var k = Int.random(in: 0..<list.count)
    if list.count > 1 && k == last[kind] { k = (k + 1) % list.count }
    last[kind] = k
    let p = players[next]; next = (next + 1) % players.count
    p.volume = Float(min(1, pow(gain, 0.8)))
    p.scheduleBuffer(list[k], at: nil, options: .interrupts)
    if !p.isPlaying { p.play() }
  }
}
