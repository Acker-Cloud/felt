/* The table's sounds (index.html section 2) and haptics (2h), ported: the same CC0 recordings (sounds/, credited in
   CREDITS.md), each hit a take chosen by the page's hash (never the one played last), through its own varispeed (the
   page's playbackRate, +-3%) and low-pass (brightness from the impact speed) at the page's loudness curve per kind:
   ball clacks, the cue's strike, cushions, the jaw's harder double knock, a bumper post's rounder bonk, a jump's
   landing, the drop into a corner, side pocket or bumper cup, and the recorded break layered under a hard cluster of
   clacks. Each kind keeps the page's voice cap and shortest gap, and a crowd of one kind arriving together is ducked
   (1 / sqrt of its recent count), so a break is a crack and a scatter rather than one wall of sound. The bus runs at
   the page's 0.55 into a peak limiter (the page's limiter and soft clip). The UI's cues (foul, turn, win, lose, a
   carom point, the power bar at 100%) are the page's notes, synthesised. The audio session is playback, so the silent
   switch does not mute the table. */
import AVFoundation
import FeltSim
import UIKit

@MainActor
final class Sound {
  static let shared = Sound()
  private let engine = AVAudioEngine()
  private let bus = AVAudioMixerNode()
  private var chains: [(p: AVAudioPlayerNode, v: AVAudioUnitVarispeed, eq: AVAudioUnitEQ, end: Double)] = []
  private var takes: [String: [AVAudioPCMBuffer]] = [:]
  private var cuts: [String: AVAudioPCMBuffer] = [:]
  private var ui: [String: AVAudioPCMBuffer] = [:]
  private var last: [String: Int] = [:]
  private var voices: [String: [Double]] = [:]
  private var crowd: [String: (t: Double, e: Double)] = [:]
  private var vseed: Int32 = 1
  private var format: AVAudioFormat?
  private var ok = false
  private var sr = 44100.0

  /* VOICE: per kind, most voices at once and shortest gap between two (s) */
  private static let VOICE: [String: (Int, Double)] = ["ball": (8, 0.004), "cue": (1, 0.04), "rail": (4, 0.02), "jaw": (3, 0.03), "post": (3, 0.03), "pocket": (3, 0.05),
    "brk": (1, 0.35), "land": (2, 0.03), "foul": (1, 0.3), "turn": (1, 0.1), "win": (1, 0.5), "lose": (1, 0.5), "tap": (2, 0.05), "point": (1, 0.3), "full": (1, 0.2)]

  private init() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    guard let dir = Bundle.main.url(forResource: "sounds", withExtension: nil) else { return }
    for (kind, n) in [("ball", 10), ("cue", 4), ("rail", 3), ("pocket", 3), ("break", 1)] {
      for i in 1...n {
        guard let f = try? AVAudioFile(forReading: dir.appendingPathComponent("\(kind)-\(i).wav")),
              let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: b)) != nil else { continue }
        format = format ?? f.processingFormat
        takes[kind, default: []].append(b)
      }
    }
    guard let fmt = format else { return }
    sr = fmt.sampleRate
    /* the master: the bus at BUS_GAIN, then the limiter (threshold -4 dB, fast: it only catches pile-ups) */
    engine.attach(bus)
    let lim = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
                                                                                     componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    engine.attach(lim)
    engine.connect(bus, to: lim, format: fmt)
    engine.connect(lim, to: engine.mainMixerNode, format: fmt)
    AudioUnitSetParameter(lim.audioUnit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
    AudioUnitSetParameter(lim.audioUnit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.1, 0)
    AudioUnitSetParameter(lim.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0, 0)
    bus.outputVolume = 0.55
    /* the voices: player -> varispeed (rate) -> low-pass (brightness) -> bus */
    for _ in 0..<16 {
      let p = AVAudioPlayerNode(), v = AVAudioUnitVarispeed(), eq = AVAudioUnitEQ(numberOfBands: 1)
      eq.bands[0].filterType = .lowPass; eq.bands[0].bypass = false; eq.bands[0].bandwidth = 0.5
      for n in [p, v, eq] as [AVAudioNode] { engine.attach(n) }
      engine.connect(p, to: v, format: fmt); engine.connect(v, to: eq, format: fmt); engine.connect(eq, to: bus, format: fmt)
      chains.append((p, v, eq, 0))
    }
    synthesiseUI()
    ok = (try? engine.start()) != nil
    for c in chains { c.p.play() }
  }

  private var now: Double { CACurrentMediaTime() }

  /* the hash: hash01 (a value in [0, 1) for a seed); vary(x, r): x within +-r of itself */
  private static func hash01(_ n: Int32) -> Double {
    var h = UInt32(bitPattern: n ^ Int32(bitPattern: 0x9e3779b9)) &* 0x85ebca6b
    h ^= h >> 13; h = h &* 0xc2b2ae35; h ^= h >> 16
    return Double(h) / 4294967296
  }
  private func varyU() -> Double { let v = Sound.hash01(vseed); vseed &+= 1; return v * 2 - 1 }
  private func vary(_ x: Double, _ r: Double) -> Double { x * (1 + varyU() * r) }
  /* sfxPick: a take of family k by the hash, never the one played last */
  private func pick(_ k: String) -> (AVAudioPCMBuffer, String)? {
    guard let l = takes[k], !l.isEmpty else { return nil }
    var i = min(l.count - 1, Int((Sound.hash01(vseed) * Double(l.count)).rounded(.down))); vseed &+= 1
    if l.count > 1 && i == last[k] { i = (i + 1) % l.count }
    last[k] = i
    return (l[i], "\(k)-\(i)")
  }
  /* hit: one take through a free voice at gain, rate and brightness; cut (s) ends it early with a fade. Its end. */
  @discardableResult private func hit(_ take: (AVAudioPCMBuffer, String)?, _ gain: Double, _ rate: Double, _ bright: Double, cut: Double = 0, fade: Double = 0.05, delay: Double = 0) -> Double {
    /* the volumes (settings.vol, settings.volFx): the bus carries the master times BUS_GAIN, each take the table
       sounds' share */
    bus.outputVolume = Float(0.55 * Double(Prefs.int("vol", 100)) / 100)
    let gain = gain * Double(Prefs.int("volFx", 100)) / 100
    guard ok, let (buf0, id) = take, gain > 0.0005 else { return now }
    let t = now + delay
    var buf = buf0
    let dur = Double(buf0.frameLength) / sr
    if cut > 0 && cut < dur { buf = cutBuffer(buf0, id, cut, fade) }
    guard let ci = chains.indices.min(by: { chains[$0].end < chains[$1].end }) else { return t }
    let c = chains[ci]
    c.v.rate = Float(rate)
    c.eq.bands[0].frequency = Float(min(bright, sr * 0.45))
    c.p.volume = Float(gain)
    let start = delay > 0 ? AVAudioTime(hostTime: mach_absolute_time() + UInt64(delay * 1e9 * Double(Sound.timebase))) : nil
    c.p.scheduleBuffer(buf, at: start, options: .interrupts)
    if !c.p.isPlaying { c.p.play() }
    let end = t + Double(buf.frameLength) / sr / rate
    chains[ci].end = end
    return end
  }
  private static let timebase: Double = { var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb); return Double(tb.denom) / Double(tb.numer) }()
  /* a take ended at cut with a linear fade (the page's gain ramp), made once */
  private func cutBuffer(_ b: AVAudioPCMBuffer, _ id: String, _ cut: Double, _ fade: Double) -> AVAudioPCMBuffer {
    let key = "\(id)@\(cut)"
    if let c = cuts[key] { return c }
    let n = AVAudioFrameCount(min(Double(b.frameLength), (cut + fade) * sr)), f0 = Int(cut * sr)
    guard let o = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: n), let src = b.floatChannelData, let dst = o.floatChannelData else { return b }
    o.frameLength = n
    for ch in 0..<Int(b.format.channelCount) {
      for i in 0..<Int(n) { dst[ch][i] = src[ch][i] * (i < f0 ? 1 : Float(max(0, 1 - Double(i - f0) / (fade * sr)))) }
    }
    cuts[key] = o
    return o
  }

  /* a hit of the table (tab.hits: [kind, v, extra]): sfxAt's caps, gap and crowd, then the voice */
  func hit(_ h: Hit) {
    var kind = h.kind
    if kind == "rail" && h.tag == "post" { kind = "post" }
    sfxAt(kind, h.v, h.extra)
    buzz(kind, h.v)
  }
  /* a UI cue (foul, turn, win, lose, point, full) */
  func cue(_ kind: String) { sfxAt(kind, 1, nil); buzz(kind, 1) }

  private func sfxAt(_ kind: String, _ v0: Double, _ x: Int?) {
    guard Prefs.sound, ok, let lim = Sound.VOICE[kind] else { return }
    let v = v0.isFinite ? v0 : 1, t = now
    if (kind == "ball" && v < 0.04) || (["rail", "jaw", "post", "land"].contains(kind) && v < 0.1) { return }
    var live = (voices[kind] ?? []).filter { $0 > t }
    if live.count >= lim.0 { return }
    var c = crowd[kind] ?? (-1, 0)
    if t - c.t < lim.1 { return }
    c.e = c.e * exp(-(t - c.t) / 0.06) + 1; c.t = t; crowd[kind] = c
    vseed = Int32(truncatingIfNeeded: Int((v * 1e4).rounded()) * 7 + kind.count)
    let end = voice(kind, v, (1 / c.e.squareRoot()), x, c.e)
    live.append(end); voices[kind] = live
  }
  private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }
  /* clack: ball on ball, louder and brighter with the speed; a glancing touch quiet and dull, but still a clack */
  @discardableResult private func clack(_ s: Double) -> Double {
    hit(pick("ball"), 0.62 * (0.035 + 0.965 * pow(s, 0.9)), vary(1, 0.03), 900 + 14000 * pow(s, 1.1))
  }
  private func voice(_ kind: String, _ v: Double, _ duck: Double, _ x: Int?, _ crowded: Double) -> Double {
    switch kind {
    case "ball":
      let s = clamp(v / 6, 0, 1), end = clack(s * duck)
      /* three or more hard contacts inside about 60 ms: the rack is breaking */
      if v > 2.5 && crowded >= 2.6 { sfxAt("brk", v, nil) }
      return end
    case "brk":
      let s = clamp(v / 8, 0, 1)
      return hit(pick("break"), 0.16 + 0.22 * s, vary(1, 0.03), 5000 + 7000 * s)
    case "cue":
      let s = clamp(v / 7, 0, 1)
      return hit(pick("cue"), 0.62 * (0.12 + 0.55 * pow(s, 0.8)), vary(1, 0.03), 1600 + 9000 * s)
    case "rail":
      let s = clamp(v / 5, 0, 1) * duck
      return hit(pick("rail"), 0.75 * (0.04 + 0.96 * pow(s, 1.3)), vary(1, 0.03), 700 + 4500 * s)
    case "jaw":
      /* the jaw's harder rubber on a narrower nose: higher, brighter, and a second knock at the far point */
      let s = clamp(v / 5, 0, 1) * duck, lvl = 0.75 * (0.04 + 0.96 * pow(s, 1.3))
      hit(pick("rail"), 0.9 * lvl, vary(1.12, 0.03), 1200 + 6000 * s)
      return hit(pick("rail"), 0.45 * lvl, vary(1.18, 0.03), 1200 + 4000 * s, delay: vary(0.032, 0.25))
    case "post":
      let s = clamp(v / 4, 0, 1) * duck
      return hit(pick("rail"), 0.7 * (0.04 + 0.96 * pow(s, 1.2)), vary(1.3, 0.03), 700 + 2200 * s)
    case "land":
      let s = clamp(v / 4, 0, 1) * duck
      return hit(pick("rail"), 0.55 * (0.05 + 0.95 * pow(s, 1.2)), vary(0.62, 0.03), 300 + 1500 * s)
    case "pocket":
      /* drop: a corner the whole take, a side pocket a hair higher and cut sooner, bumper's cup short and higher */
      let s = clamp(v / 2.5, 0, 1), lvl = 0.4 + 0.5 * s, buf = pick("pocket")
      if cupTable { return hit(buf, 0.6 * lvl, vary(1.15, 0.03), 4000, cut: 0.28) }
      if let k = x, sidePockets.contains(k) { return hit(buf, 0.66 * lvl, vary(1.06, 0.03), 5000, cut: 0.42) }
      return hit(buf, 0.66 * lvl, vary(1, 0.03), 4500)
    case "point":
      clack(0.22); hit(pick("ball"), 0.62 * (0.035 + 0.965 * pow(0.16, 0.9)), vary(1, 0.03), 900 + 14000 * pow(0.16, 1.1), delay: 0.11)
      return uiPlay("point")
    default:
      return uiPlay(kind)
    }
  }
  /* the table's pockets as the drops read them: a bumper table's cups, pool's side pockets (k 1 and 4) */
  var cupTable = false
  var sidePockets: Set<Int> = [1, 4]

  // MARK: the UI's notes (sfxVoice's foul, turn, tap, full, win, lose; point's bell), synthesised once
  private func uiPlay(_ kind: String) -> Double {
    guard let b = ui[kind] else { return now }
    return hit((b, "ui-" + kind), 1, 1, sr * 0.45)
  }
  private func synthesiseUI() {
    guard let fmt = format else { return }
    /* partial: a sine from f0 to f1 under a fast attack and an exponential tail (env), at time t in the buffer */
    func render(_ len: Double, _ parts: [(t: Double, f0: Double, f1: Double, peak: Double, decay: Double, attack: Double)]) -> AVAudioPCMBuffer? {
      let n = AVAudioFrameCount(len * sr)
      guard let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n), let d = b.floatChannelData else { return nil }
      b.frameLength = n
      for ch in 0..<Int(fmt.channelCount) { for i in 0..<Int(n) { d[ch][i] = 0 } }
      for p in parts {
        var ph = 0.0
        let i0 = Int(p.t * sr), i1 = min(Int(n), i0 + Int((p.attack + p.decay + 0.02) * sr))
        for i in max(0, i0)..<i1 {
          let u = Double(i - i0) / sr
          let g = u < p.attack ? p.peak * u / p.attack : p.peak * pow(1e-4 / max(p.peak, 2e-4), (u - p.attack) / p.decay)
          let f = p.f1 == p.f0 ? p.f0 : p.f0 * pow(p.f1 / p.f0, min(1, u / (p.attack + p.decay)))
          ph += 2 * Double.pi * f / sr
          let s = Float(g * sin(ph))
          for ch in 0..<Int(fmt.channelCount) { d[ch][i] += s }
        }
      }
      return b
    }
    func note(_ t: Double, _ f: Double, _ peak: Double, _ decay: Double) -> [(Double, Double, Double, Double, Double, Double)] {
      [(t, f, f, peak, decay, 0.01), (t, f * 2, f * 2, peak * 0.15, decay * 0.5, 0.01)]
    }
    ui["foul"] = render(0.55, note(0, 349.23, 0.11, 0.2) + note(0.15, 261.63, 0.11, 0.34))
    ui["turn"] = render(0.06, [(0, 1320, 1250, 0.045, 0.03, 0.002)])
    ui["tap"] = render(0.04, [(0, 2100, 1900, 0.022, 0.012, 0.001)])
    ui["full"] = render(0.04, [(0, 2600, 2450, 0.018, 0.01, 0.0008)])
    ui["moment"] = render(0.65, note(0, 783.99, 0.05, 0.4) + note(0.08, 1174.66, 0.04, 0.5))
    ui["point"] = render(0.6, [(0.11, 1567.98, 1567.98, 0.018, 0.45, 0.004)])
    ui["win"] = render(1.2, [523.25, 659.25, 783.99].enumerated().flatMap { i, f in note(Double(i) * 0.09, f, 0.1, 0.7 - Double(i) * 0.1) }
                       + note(0.18, 1046.5, 0.035, 0.6) + [(0.27, 2093, 2093, 0.012, 0.9, 0.04)])
    ui["lose"] = render(0.95, note(0, 392, 0.055, 0.45) + note(0.16, 311.13, 0.045, 0.7))
  }

  // MARK: 2h, haptics: a pot a firm double tick, a foul a distinct double, a win a triple, the power bar's 100% one;
  // impacts only when hard (a cushion, jaw or post over 2 m/s, a ball over 1.5), at most one per 140 ms
  private let tick = UISelectionFeedbackGenerator(), thud = UIImpactFeedbackGenerator(style: .light)
  private var hapLast = 0.0, hapHit = 0.0
  private static let PLANS: [String: [Double]] = ["pocket": [0, 0.07], "point": [0, 0.11], "foul": [0, 0.19], "win": [0, 0.13, 0.26], "lose": [0], "full": [0]]
  private func hapNow(_ firm: Bool) {
    guard Prefs.haptics else { return }
    let t = now
    if t - hapLast < 0.06 { return }
    hapLast = t
    if firm { thud.impactOccurred(intensity: 0.8) } else { tick.selectionChanged() }
  }
  private func buzz(_ kind: String, _ v: Double) {
    if ["ball", "rail", "jaw", "post"].contains(kind) {
      guard v >= (kind == "ball" ? 1.5 : 2) else { return }
      let t = now
      if t - hapHit >= 0.14 && Prefs.haptics && t - hapLast >= 0.06 { hapHit = t; hapLast = t; thud.impactOccurred(intensity: 0.45) }
      return
    }
    guard let plan = Sound.PLANS[kind] else { return }
    for at in plan {
      if at == 0 { hapNow(kind == "pocket") } else { DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in self?.hapNow(kind == "pocket") } }
    }
  }
}
