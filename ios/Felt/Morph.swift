/* index.html 6m, a home card into its page and back (morphOpen, morphClose): the card grows as a window (morphWin, .mClip)
   on the spring (springAt, MORPH_MS), each picture in it at one scale both ways, covering it and cropped by it, never
   stretched; the panel's ground comes up over the home and the page's content under it; a game card's name flies to the
   setup's Large Title (.mTitle) and the hero holds its first frame until the landing (morphHolds), the card's art under
   it until that frame is made (heroUnder). Back runs it the other way, the hero's frame going down into the card under
   its art. Reduce Motion: a cross-fade (FADE_MS). The page is pushed (or popped) at once under the morph, so the side it
   leaves is a still of the screen. */
import SwiftUI
import UIKit

enum MorphK {
  static let MS = 380.0, FADE_MS = 200.0, EDGE_PX = 24.0, HERO_FADE = 180.0
  /* springAt: the curve SPRING draws, a hair of overshoot, settled at the end */
  static func spring(_ t: Double) -> Double {
    if t >= 1 { return 1 }
    let z = 0.78, w = 8.4, wd = w * (1 - z * z).squareRoot()
    return 1 - exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))
  }
  /* the CSS easings the page's pieces run on: cubic-bezier, solved for x */
  static func bez(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
    let x = min(1, max(0, x))
    if x == 0 || x == 1 { return x }
    func c(_ a: Double, _ b: Double, _ s: Double) -> Double { 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s }
    var lo = 0.0, hi = 1.0, s = x
    for _ in 0..<30 { s = (lo + hi) / 2; if c(x1, x2, s) < x { lo = s } else { hi = s } }
    return c(y1, y2, s)
  }
  static func out(_ x: Double) -> Double { bez(0, 0, 0.58, 1, x) }
  static func inOut(_ x: Double) -> Double { bez(0.42, 0, 0.58, 1, x) }
  static func easeIn(_ x: Double) -> Double { bez(0.42, 0, 1, 1, x) }
  static func L(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
  static func L(_ a: CGRect, _ b: CGRect, _ p: Double) -> CGRect {
    CGRect(x: L(a.minX, b.minX, p), y: L(a.minY, b.minY, p), width: L(a.width, b.width, p), height: L(a.height, b.height, p))
  }
}

@MainActor @Observable final class Morph {
  /* a card on the home as last laid out: its box, its name's and its line's (global points) */
  struct Card { var rect = CGRect.zero, title = CGRect.zero, line = CGRect.zero, narrow = false }
  /* what a card's page is made of: a game's setup (its art) or a mode's page (its glow) */
  struct Face { var game: TableGame? = nil, art: CGImage? = nil, scale: CGFloat = 3, glow: (Double, Double, Double) = (0, 0, 0) }
  struct Run {
    let open: Bool, fade: Bool, card: Card, face: Face, zoom: Double
    /* the side left: the home (open) or the page (close), and the open's ghost of a mode card */
    let still: UIImage?, ghost: CGImage?
    /* the close: where it starts (the hero or the page, the Large Title) and the hero's frame */
    let from: CGRect?, fromTitle: CGRect?, snap: CGImage?
    let born: Double
    var t0: Double? = nil
  }
  var run: Run? = nil
  var hideTitle = false
  var hideHero = false
  var heroHold = false
  var cardTitleHidden: String? = nil
  var under: CGImage? = nil
  var underScale: CGFloat = 3
  @ObservationIgnored var cards: [String: Card] = [:]
  @ObservationIgnored var heroRect: CGRect? = nil
  @ObservationIgnored var titleRect: CGRect? = nil
  @ObservationIgnored var heroFrame: CGImage? = nil
  /* mo.src: the card whose page is open */
  @ObservationIgnored var src: String? = nil
  @ObservationIgnored var zoom = 1.0

  static func instant(_ f: () -> Void) { var t = Transaction(); t.disablesAnimations = true; withTransaction(t, f) }
  /* a still of the screen as it is */
  static func shot() -> UIImage? {
    guard let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
    let f = UIGraphicsImageRendererFormat(); f.scale = w.screen.scale; f.opaque = true
    return UIGraphicsImageRenderer(bounds: w.bounds, format: f).image { _ in _ = w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) }
  }
  /* morphOpen: the page pushed at once, the card flying into it over the still */
  func open(_ id: String, _ face: Face, push: () -> Void) {
    end()
    guard let c = cards[id], c.rect.width > 1, let still = Self.shot() else { src = nil; push(); return }
    let fade = Prefs.reduceMotion, setup = face.game != nil
    src = id
    heroRect = nil; titleRect = nil; heroFrame = nil
    under = setup && !fade ? face.art : nil; underScale = face.scale
    if setup && !fade { hideTitle = true; hideHero = true; heroHold = true }
    var ghost: CGImage? = nil
    if !setup, let cg = still.cgImage {
      let k = still.scale
      ghost = cg.cropping(to: CGRect(x: c.rect.minX * k, y: c.rect.minY * k, width: c.rect.width * k, height: c.rect.height * k).integral)
    }
    run = Run(open: true, fade: fade, card: c, face: face, zoom: zoom, still: still, ghost: ghost, from: nil, fromTitle: nil, snap: nil, born: CACurrentMediaTime())
    Self.instant(push)
  }
  /* morphClose: home at once, the page flying back into its card; a page no card opened just goes back */
  func close(_ id: String, _ face: Face, pop: () -> Void) {
    end()
    let mine = src == id
    src = nil
    guard mine, let c = cards[id], c.rect.width > 1, let still = Self.shot() else { pop(); return }
    var fade = Prefs.reduceMotion
    let setup = face.game != nil
    if setup && (heroRect == nil || titleRect == nil) { fade = true }
    if setup && !fade { cardTitleHidden = id }
    run = Run(open: false, fade: fade, card: c, face: face, zoom: zoom, still: still, ghost: nil, from: setup ? heroRect : nil, fromTitle: titleRect,
              snap: setup ? heroFrame : nil, born: CACurrentMediaTime())
    Self.instant(pop)
  }
  /* a new morph, or the landing: done at once */
  func end() { if run != nil { finish() } }
  private func finish() {
    run = nil
    hideTitle = false; hideHero = false; heroHold = false; cardTitleHidden = nil
  }
  /* a frame: the clock starts once the setup has laid out its hero and title (else it just shows), the hero shows under
     the window for its last HERO_FADE ms, and the landing ends it */
  func tick(_ now: Double) {
    guard var r = run else { return }
    guard let t0 = r.t0 else {
      if r.open && !r.fade && r.face.game != nil && (heroRect == nil || titleRect == nil) {
        if now - r.born > 0.3 { finish() }
        return
      }
      r.t0 = now; run = r
      return
    }
    let t = (now - t0) * 1000, F = r.fade ? MorphK.FADE_MS : MorphK.MS
    if r.open && hideHero && t >= F - MorphK.HERO_FADE { hideHero = false }
    if t >= F { finish() }
  }
}

/* the morph's pieces over everything (.mPiece, .mClip, .mGhost, .mTitle), hidden from VoiceOver, eating every touch */
struct MorphLayer: View {
  let mo: Morph
  var body: some View {
    if let r = mo.run {
      GeometryReader { g in
        let o = g.frame(in: .global).origin, S = g.size
        TimelineView(.animation) { tl in
          let t = r.t0.map { (tl.date.timeIntervalSinceReferenceDate - $0) * 1000 } ?? 0
          MorphFrame(mo: mo, r: r, t: max(0, t), o: o, S: S)
            .onChange(of: tl.date) { _, d in mo.tick(d.timeIntervalSinceReferenceDate) }
        }
      }
      .ignoresSafeArea()
      .contentShape(Rectangle()).onTapGesture {}
      .accessibilityHidden(true)
    }
  }
}

struct MorphFrame: View {
  let mo: Morph, r: Morph.Run, t: Double, o: CGPoint, S: CGSize
  private func loc(_ q: CGRect) -> CGRect { q.offsetBy(dx: -o.x, dy: -o.y) }
  /* a picture of w x h points covering the window's box at one scale, k going from covering box a to covering box b */
  private func cover<V: View>(_ v: V, _ q: CGSize, _ a: CGRect, _ b: CGRect, _ p: Double) -> some View {
    let k = MorphK.L(max(a.width / q.width, a.height / q.height), max(b.width / q.width, b.height / q.height), p)
    return v.frame(width: q.width * k, height: q.height * k)
  }
  /* the window: box R, its corners rad, its pictures centred in it and cropped by it */
  private func window<V: View>(_ R: CGRect, _ rad: Double, @ViewBuilder _ pics: () -> V) -> some View {
    let c = max(0, rad)
    return ZStack { pics() }
      .frame(width: max(1, R.width), height: max(1, R.height))
      .clipShape(RoundedRectangle(cornerRadius: c, style: .continuous))
      .offset(x: R.minX, y: R.minY)
  }
  private var art: some View {
    Group { if let a = r.face.art { Image(decorative: a, scale: r.face.scale).resizable() } else { Color(rgb: 0x12, 0x12, 0x14) } }
  }
  /* .mTitle: the name in the font of where it lands (b), scaled from a's size to its own, top left first */
  private func flown(_ a: CGRect, _ b: CGRect, _ p: Double, big: Bool) -> some View {
    let g = r.face.game!, s = r.zoom * MorphK.L(a.height / max(1, b.height), 1, p)
    return Group {
      if big { Text(g.rawValue).font(.largeTitle.bold()) }
      else { Text(g.rawValue).font(.system(size: r.card.narrow ? 16 : 17, weight: .semibold)).kerning(-0.2) }
    }
    .foregroundStyle(.white).lineLimit(1).fixedSize()
    .scaleEffect(s, anchor: .topLeading)
    .offset(x: MorphK.L(a.minX, b.minX, p) - o.x, y: MorphK.L(a.minY, b.minY, p) - o.y)
  }
  var body: some View {
    let F = MorphK.MS, full = CGRect(origin: .zero, size: S), setup = r.face.game != nil, p = MorphK.spring(t / F)
    let card = loc(r.card.rect), cardQ = r.card.rect.size
    ZStack(alignment: .topLeading) {
      if r.fade {
        if let s = r.still { Image(uiImage: s).resizable().frame(width: S.width, height: S.height).opacity(1 - MorphK.out(t / MorphK.FADE_MS)) }
      } else if r.open {
        let dst = setup ? (mo.heroRect.map(loc) ?? full) : full
        /* the home's still under the panel's ground (dim, pan); at a setup the form comes up through it */
        let b = setup ? MorphK.out((t - 60) / (0.75 * F)) : 0
        ZStack {
          if let s = r.still { Image(uiImage: s).resizable() }
          Color.black.opacity(MorphK.out(t / (0.7 * F)))
        }
        .frame(width: S.width, height: S.height).opacity(1 - b)
        /* the window: the card's art (or face) covering it; a mode's page colour coming over it (flat: it may stretch);
           it gives way to the page for the end of the flight, the hero under it at a setup */
        let R = MorphK.L(card, dst, p)
        let wo = setup ? (t < F - MorphK.HERO_FADE ? 1 : 1 - MorphK.inOut((t - (F - MorphK.HERO_FADE)) / MorphK.HERO_FADE))
          : (t < 0.5 * F ? 1 : 1 - MorphK.out((t - 0.5 * F) / (0.5 * F)))
        window(R, MorphK.L(22, 0, p)) {
          if setup { Color(rgb: 0x12, 0x12, 0x14); cover(art, cardQ, card, dst, p) }
          else {
            cover(ModeFace(glow: r.face.glow), cardQ, card, dst, p)
            Color.black.opacity(MorphK.inOut((t - 0.2 * F) / (0.6 * F)))
          }
        }
        .opacity(wo)
        /* the card's words where they were (.mGhost), fading; a game card's name flies instead */
        Group {
          if setup, let g = r.face.game {
            Text(HomeArt.line(g)).font(.system(size: r.card.narrow ? 12 : 13)).foregroundStyle(.white.opacity(0.74)).lineLimit(1).fixedSize()
              .scaleEffect(r.zoom, anchor: .topLeading).offset(x: loc(r.card.line).minX, y: loc(r.card.line).minY)
          } else if let gh = r.ghost {
            Image(decorative: gh, scale: r.still?.scale ?? 3).resizable().frame(width: card.width, height: card.height).offset(x: card.minX, y: card.minY)
          }
        }
        .opacity(1 - MorphK.out(t / 140))
        if setup, let to = mo.titleRect { flown(r.card.title, to, p, big: true) }
      } else {
        let from = r.from.map(loc) ?? full
        Color.black.opacity(1 - MorphK.easeIn(t / (0.6 * F))).frame(width: S.width, height: S.height)
        /* the window closing into the card: the hero's frame covering it, the card's art coming back over it */
        window(MorphK.L(from, card, p), MorphK.L(0, 22, p)) {
          if setup {
            Color(rgb: 0x12, 0x12, 0x14)
            if let sn = r.snap { cover(Image(decorative: sn, scale: HeroArt.DPR).resizable(), from.size, from, card, p) }
            cover(art, cardQ, from, card, p).opacity(MorphK.inOut((t - 0.1 * F) / (0.7 * F)))
          } else {
            cover(ModeFace(glow: r.face.glow), cardQ, from, card, p)
            Color.black.opacity(1 - MorphK.inOut((t - 0.1 * F) / (0.6 * F)))
          }
        }
        /* the card itself, words and all, comes back under it (the ghost's fade in) */
        .opacity(t < 0.55 * F ? 1 : 1 - (t - 0.55 * F) / (0.45 * F))
        if let s = r.still { Image(uiImage: s).resizable().frame(width: S.width, height: S.height).opacity(1 - MorphK.out(t / 150)) }
        if setup, let ft = r.fromTitle { flown(ft, r.card.title, p, big: false) }
      }
    }
    .frame(width: S.width, height: S.height, alignment: .topLeading)
  }
}

/* the page's Back (morphClose): the bar's chevron, and a swipe in from the left edge (EDGE_PX) */
struct MorphBack: ViewModifier {
  let back: () -> Void
  func body(content: Content) -> some View {
    content
      .navigationBarBackButtonHidden(true)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: back) { Image(systemName: "chevron.backward").font(.system(size: 17, weight: .semibold)) }
            .accessibilityLabel("Back").accessibilityIdentifier("back")
        }
      }
      .simultaneousGesture(DragGesture(minimumDistance: 16, coordinateSpace: .global).onEnded { v in
        if v.startLocation.x < MorphK.EDGE_PX, v.translation.width > 72, abs(v.translation.width) > abs(v.translation.height) * 1.5 { back() }
      })
  }
}
