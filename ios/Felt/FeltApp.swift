/* felt, native. Home lists the tables; a table is aimed by touch, fine-tuned on the wheel, given
   english on the pad and shot from the power bar alone: pull it down, let go. */
import FeltSim
import SwiftUI

@main
struct FeltApp: App {
  var body: some Scene {
    WindowGroup { Home().preferredColorScheme(.dark).statusBarHidden() }
  }
}

struct Home: View {
  @State private var playing: TableGame?
  @AppStorage("felt.opponent") private var opponent = "medium"
  @State private var exhibit: Exhibit?
  @State private var party: PartyGo?
  @State private var store = TourneyStore()
  @State private var playingTourney = false
  @State private var showTourney = false
  struct PartyGo: Identifiable { let game: TableGame, names: [String], ruleset: String; var id: String { ruleset + names.joined() } }
  struct Exhibit: Identifiable { let game: TableGame, levels: [String]; var archs: [String] = ["allround", "allround"]; var id: String { game.rawValue + levels.joined() + archs.joined() } }
  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("Opponent", selection: $opponent) {
            Text("2 Players").tag("two"); Text("Easy").tag("easy"); Text("Medium").tag("medium"); Text("Hard").tag("hard")
          }
          .pickerStyle(.segmented)
          .accessibilityIdentifier("opponent")
        } header: { Text("Opponent") } footer: { Text("The CPU plays every game at three levels, the web build's own search.") }
        Section {
          ForEach(TableGame.allCases) { g in
            Button { playing = g } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(g.rawValue).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(g.line).font(.footnote).foregroundStyle(.secondary)
              }.frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("game-\(g.rawValue)")
          }
        } header: { Text("Games") } footer: {
          Text("The web build's physics, rules and CPU, bit for bit.")
        }
        Section {
          NavigationLink { ExhibitionSetup { exhibit = $0 } } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text("Exhibition").font(.body.weight(.semibold))
              Text("Two CPU players, any game").font(.footnote).foregroundStyle(.secondary)
            }.frame(minHeight: 44, alignment: .leading)
          }
          .accessibilityIdentifier("mode-exhibit")
          NavigationLink { TourneyView(store: store) { store.markLive(); playingTourney = true } } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text("Quick Tournament").font(.body.weight(.semibold))
              Text(store.tour.map { $0.done ? "Finished: \(TourneyView.placeWords($0.place ?? 0))" : "In progress, \(TourneyView.kindName($0.kind))" } ?? "4, 8 or 16 players, a bracket").font(.footnote).foregroundStyle(.secondary)
            }.frame(minHeight: 44, alignment: .leading)
          }
          .accessibilityIdentifier("mode-tourney")
          NavigationLink { PartySetup { party = $0 } } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text("Party").font(.body.weight(.semibold))
              Text("2 to 4 players, one device").font(.footnote).foregroundStyle(.secondary)
            }.frame(minHeight: 44, alignment: .leading)
          }
          .accessibilityIdentifier("mode-party")
        } header: { Text("Modes") } footer: {
          Text("Watch the CPU play itself, each player at its own level.")
        }
      }
      .navigationTitle("felt")
      .navigationDestination(isPresented: $showTourney) { TourneyView(store: store) { store.markLive(); playingTourney = true } }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings").accessibilityIdentifier("settings")
        }
      }
      .tint(.primary)
    }
    /* a test hook, like the page's window.felt: `-felt-game "9-Ball"` opens that table */
    .onAppear {
      let a = ProcessInfo.processInfo.arguments
      if let i = a.firstIndex(of: "-felt-game"), i + 1 < a.count { playing = TableGame(rawValue: a[i + 1]) }
      /* `-felt-tourney`: the golden's first tournament (9-ball, 8 players, seed 11), its screen open */
      if a.contains("-felt-tourney") { store.start(Tourney.make(kind: "9", ruleset: nil, size: 8, fmt: "single", race: 3, field: "mixed", seed: 11)); showTourney = true }
      if let i = a.firstIndex(of: "-felt-party"), i + 1 < a.count, let n = Int(a[i + 1]) { party = PartyGo(game: .nine, names: (1...n).map { "Player \($0)" }, ruleset: "9-ring") }
      if let i = a.firstIndex(of: "-felt-exhibit"), i + 1 < a.count, let g = TableGame(rawValue: a[i + 1]) { exhibit = Exhibit(game: g, levels: ["medium", "hard"]) }
      /* `-felt-landscape left|right`: the interface turned on its side (the simulator cannot be turned from a script) */
      if let i = a.firstIndex(of: "-felt-landscape"), i + 1 < a.count,
         let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: a[i + 1] == "left" ? .landscapeLeft : .landscapeRight))
      }
    }
    .fullScreenCover(item: $playing) { g in TableScreen(model: TableModel(game: g, cpu: opponent == "two" ? nil : opponent)) }
    .fullScreenCover(item: $exhibit) { e in TableScreen(model: TableModel(game: e.game, exhib: e.levels, exhibArch: e.archs)) }
    .fullScreenCover(isPresented: $playingTourney) {
      if let t = store.tour, let g = TourneyView.game(t.kind) {
        TableScreen(model: { let m = TableModel(game: g, tourney: t); m.onReport = { store.report($0, $1, $2, $3) }; return m }())
      }
    }
    .fullScreenCover(item: $party) { p in TableScreen(model: TableModel(game: p.game, party: (p.names, p.ruleset))) }
  }
}

struct TableScreen: View {
  @State var model: TableModel
  @Environment(\.dismiss) private var dismiss
  @State private var aimDrag: Double?
  @State private var placing = false
  @State private var picking = false
  @Environment(\.displayScale) private var scale
  /* the window's interface orientation, read as the size changes (a turn) */
  private var interface: UIInterfaceOrientation { (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.effectiveGeometry.interfaceOrientation ?? .portrait }

  var body: some View {
    GeometryReader { geo in
      let ins = geo.safeAreaInsets, W = geo.size.width + ins.leading + ins.trailing, H = geo.size.height + ins.top + ins.bottom
      /* sideRot (6b): a phone on its side (under 600 pt tall) shows the upright layout turned a quarter, so the table
         keeps the same footprint either way. The column stands on the side away from the island (the larger side
         inset): anticlockwise with the island on the left (the strip's foot to the right), clockwise with it on the
         right. The upright insets are modelled from the side ones: the island's inset is the upright top, the foot
         HOME_UP (34 pt) with a home indicator, else 4. A tablet or desktop on its side keeps the column. */
      let side = W > H && H < 600
      if side {
        /* islandSide(): unequal insets, the larger; equal (as iOS gives them), the interface's orientation: landscape
           right has the island on the left (anticlockwise, the column right), landscape left on the right */
        let ccw = ins.leading != ins.trailing ? ins.leading > ins.trailing : interface != .landscapeLeft
        /* upright a phone has no side insets: the sides' padding is the upright one's (2 pt) */
        let up = EdgeInsets(top: max(ins.leading, ins.trailing), leading: 0, bottom: ins.bottom > 0 ? 34 : 4, trailing: 0)
        screen(W: H, H: W, ins: up, upright: true)
          .frame(width: H, height: W)
          .rotationEffect(.degrees(ccw ? -90 : 90))
          .frame(width: W, height: H)
          .offset(x: -ins.leading, y: -ins.top)
      } else {
        screen(W: W, H: H, ins: ins, upright: H > W)
          .frame(width: W, height: H)
          .offset(x: -ins.leading, y: -ins.top)
      }
    }
    .background(Color(rgb: 9, 9, 10).ignoresSafeArea())
    .overlay { Overlays(model: model, back: { dismiss() }) }
    .overlay(alignment: .bottomTrailing) { if model.callMenu && model.callMenuOffered { CallMenu(model: model) } }
    .overlay { if let h = model.handoff, !model.paused { Handoff(model: model, p: h.p, first: h.first) } }
    /* the exhibition's bar: the speed (felt.speed), over the table's top */
    .overlay(alignment: .top) {
      if model.exhib != nil && !model.paused {
        Picker("Speed", selection: Binding(get: { model.speed }, set: { model.speed = $0 })) { Text("1x").tag(1.0); Text("2x").tag(2.0); Text("4x").tag(4.0) }
          .pickerStyle(.segmented).frame(width: 180).padding(.top, 54).accessibilityIdentifier("exhibit-speed")
      }
    }
    .tint(.primary)
    .statusBarHidden()
  }

  /* #ui: padding max(2, the insets), max(4) at the foot; upright the stage over one 56 pt strip (#ctl), 4 apart, the
     strip stood in from the sides by 0.35 of the foot's inset (the display's rounded corners); else a column */
  @ViewBuilder private func screen(W: CGFloat, H: CGFloat, ins: EdgeInsets, upright: Bool) -> some View {
    let layout = upright ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
    layout {
      GeometryReader { tg in
        TimelineView(.animation(paused: model.paused)) { tl in
          TableCanvas(model: model, look: Look.of(model.game))
            .onChange(of: tl.date) { _, d in model.tick(d.timeIntervalSinceReferenceDate) }
        }
        .overlay { FlashBanner(model: model, size: tg.size) }
        .onAppear { model.bake(tg.size, scale: scale) }
        .onChange(of: tg.size) { _, s in model.bake(s, scale: scale) }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in touch(v, tg.size, began: v.translation == .zero) }
          .onEnded { _ in placing = false; picking = false })
        .accessibilityElement()
        .accessibilityLabel("Table")
        .accessibilityIdentifier("table")
      }
      Controls(model: model, upright: upright)
        .frame(width: upright ? nil : 64, height: upright ? 56 : nil)
        .padding(.horizontal, upright ? ins.bottom * 0.35 : 0)
    }
    .padding(.top, max(2, ins.top)).padding(.bottom, max(upright ? 4 : 8, ins.bottom))
    .padding(.leading, max(upright ? 2 : 8, ins.leading)).padding(.trailing, max(upright ? 2 : 8, ins.trailing))
    .frame(width: W, height: H)
  }

  private func touch(_ v: DragGesture.Value, _ size: CGSize, began: Bool) {
    let s = model.sim, m = Mapper(size: size, TL: s.TL, TW: s.TW)
    model.uprightView = m.upright
    let (x, y) = m.table(v.location)
    /* bumper pool: a touch on one of the shooter's own balls strikes that one from now on (pickBall) */
    if began, model.game == .bumper, let g = model.g {
      /* ballAt: the shooter's striker nearest the touch within max(22, 1.5 ball radii); the current one aims instead */
      let reach = max(22, 1.5 * s.BALL_R * m.k)
      var best: Int? = nil, bd = reach
      for n in model.engine.bumperStrikers(g) {
        guard let b = g.balls.first(where: { $0.n == n && $0.on }) else { continue }
        let p = m.pt(b.x, b.y), d = JSMath.hypot(Double(p.x - v.location.x), Double(p.y - v.location.y))
        if d < bd { bd = d; best = n }
      }
      if let n = best, n != model.cueN, model.pickBall(n) { picking = true; return }
    }
    if picking { return }
    /* a call open: a touch on a pocket calls it (pocketAt: 26 pt or 1.6 ball radii round its centre), on a ball calls
       that ball (and still aims) */
    if began, model.callOn {
      var best = -1, bd = Double.infinity
      for (k, p) in s.POCKETS.enumerated() {
        let q = m.pt(p[0], p[1]), d = JSMath.hypot(Double(q.x - v.location.x), Double(q.y - v.location.y))
        if d < max(26, 1.6 * s.BALL_R * m.k) && d < bd { bd = d; best = k }
      }
      if best >= 0 { model.pickPocket(best); picking = true; return }
      if let b = model.balls.first(where: { $0.on && $0.n != model.cueN && JSMath.hypot($0.x - x, $0.y - y) < s.BALL_R * 1.4 }) { model.pickCallBall(b.n) }
    }
    if began, model.inHand, let c = model.cue, JSMath.hypot(c.x - x, c.y - y) < s.BALL_R * 3 { placing = true }
    if placing { model.place(x, y); return }
    guard model.rolling == nil, let c = model.cue else { return }
    if JSMath.hypot(x - c.x, y - c.y) > s.BALL_R { model.aim = atan2(y - c.y, x - c.x) }
  }
}

/* 6b's strip, upright left to right: english (56), power (the biggest, flex), the fine-aim wheel (72-96) and pause
   (44 x 56); on its side the same as a column */
struct Controls: View {
  let model: TableModel
  let upright: Bool
  var body: some View {
    let items = Group {
      SpinPad(model: model)
      PowerBar(model: model, upright: upright)
      FineWheel(model: model, upright: upright)
      pause
    }
    if upright {
      /* the strip's flex, as the CSS resolves it: power `flex: 1` (basis 0, at least 150, 136 under 390 pt), the wheel
         `flex: 1 1 72px` up to 96: the space past their bases shared evenly, the wheel's share capped */
      GeometryReader { g in
        let avail = g.size.width - 56 - 44 - 12, minP: CGFloat = g.size.width + 4 < 390 ? 136 : 150
        let wheel = max(44, min(96, 72 + (avail - 72) / 2, avail - minP))
        HStack(spacing: 4) {
          SpinPad(model: model)
          PowerBar(model: model, upright: true).frame(width: avail - wheel)
          FineWheel(model: model, upright: true).frame(width: wheel)
          pause
        }
      }
    } else { VStack(spacing: 10) { items } }
  }
  private var pause: some View {
    Button { model.paused = true } label: {
      Canvas { ctx, size in
        let o = CGPoint(x: size.width / 2 - 11, y: size.height / 2 - 11), k = 22.0 / 24
        for x in [6.0, 14.0] { ctx.fill(Path(roundedRect: CGRect(x: o.x + x * k, y: o.y + 5 * k, width: 4 * k, height: 14 * k), cornerRadius: 1.2 * k), with: .color(Color(rgb: 0xec, 0xec, 0xee))) }
      }
      .frame(width: upright ? 44 : 64, height: upright ? 56 : 44)
      .background(RoundedRectangle(cornerRadius: 12).fill(Color(rgb: 0x1b, 0x1b, 0x1d)))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Pause and menu")
    .accessibilityIdentifier("pause")
  }
}

/* fine aim (#fineWheel): a ridged thumbwheel, lit across the middle and falling into shadow at both ends; a drag
   along it turns the aim a little (0.15 degrees a point) and rolls the ridges with the finger */
struct FineWheel: View {
  let model: TableModel
  let upright: Bool
  @State private var last: CGFloat = 0
  @State private var roll: CGFloat = 0
  @State private var live = false
  var body: some View {
    let stops: [Gradient.Stop] = [.init(color: Color(rgb: 0x14, 0x14, 0x16), location: 0), .init(color: Color(rgb: 0x50, 0x50, 0x5a), location: 0.24),
      .init(color: Color(rgb: 0x6e, 0x6e, 0x78), location: 0.5), .init(color: Color(rgb: 0x50, 0x50, 0x5a), location: 0.76), .init(color: Color(rgb: 0x14, 0x14, 0x16), location: 1)]
    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
      .overlay {
        Canvas { ctx, size in
          /* .ridges: inset 8 across, every 4 pt a dark line and a light one under it, moved by --roll */
          var y = roll.truncatingRemainder(dividingBy: 4) - 4
          while y < size.height {
            ctx.fill(Path(CGRect(x: 8, y: y, width: size.width - 16, height: 1)), with: .color(.black.opacity(0.6)))
            ctx.fill(Path(CGRect(x: 8, y: y + 1, width: size.width - 16, height: 1)), with: .color(Color(rgb: 240, 240, 244).opacity(0.62)))
            y += 4
          }
          let sh: [Gradient.Stop] = [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.3), .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.55), location: 1)]
          ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(stops: sh), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(live ? Color(rgb: 0xec, 0xec, 0xee) : Color(rgb: 0x6b, 0x6b, 0x74), lineWidth: 1))
      .opacity(model.rolling != nil ? 0.5 : 1)
      .frame(minWidth: upright ? 44 : 64, maxWidth: upright ? 96 : 64, minHeight: upright ? 56 : 112, maxHeight: upright ? 56 : 200)
      .layoutPriority(upright ? 0 : 1)
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        live = true
        let d = v.translation.height
        if model.rolling == nil { model.aim += Double(d - last) * 0.15 * .pi / 180; roll += d - last }
        last = d
      }.onEnded { _ in last = 0; live = false })
      .accessibilityLabel("Fine aim")
  }
}

/* english (#spinPad): the cue ball, where the tip meets it: top is follow, bottom draw, side either way; the dashed
   ring is |spin| = 1 (inset 19%), the crosshair 62% long, the tip a chalk-blue dot ringed in white */
struct SpinPad: View {
  let model: TableModel
  var body: some View {
    GeometryReader { g in
      let d = min(g.size.width, g.size.height), R = d * 0.31
      ZStack {
        Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: Color(rgb: 0xf1, 0xef, 0xe8), location: 0.32),
          .init(color: Color(rgb: 0xcf, 0xcc, 0xc4), location: 0.72), .init(color: Color(rgb: 0x9d, 0x9a, 0x93), location: 1)],
          center: UnitPoint(x: 0.36, y: 0.30), startRadius: 0, endRadius: d * 0.81))
          .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        Circle().strokeBorder(.black.opacity(0.25), lineWidth: 1)
        Circle().strokeBorder(Color(rgb: 40, 40, 44).opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(d * 0.19)
        Rectangle().fill(Color(rgb: 40, 40, 44).opacity(0.2)).frame(width: 1, height: d * 0.62)
        Rectangle().fill(Color(rgb: 40, 40, 44).opacity(0.2)).frame(width: d * 0.62, height: 1)
        Circle().fill(RadialGradient(stops: [.init(color: Color(rgb: 0x5b, 0x95, 0xd0), location: 0), .init(color: Color(rgb: 0x2f, 0x6f, 0xb0), location: 0.6),
          .init(color: Color(rgb: 0x1f, 0x4f, 0x82), location: 1)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 9))
          .frame(width: 14, height: 14)
          .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2).padding(-1))
          .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
          .offset(x: CGFloat(model.spin.x) * R, y: -CGFloat(model.spin.y) * R)
      }
      .frame(width: d, height: d)
      .contentShape(Circle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        let dx = (v.location.x - d / 2) / R, dy = -(v.location.y - d / 2) / R
        model.spin = spinOf(x: Double(dx), y: Double(dy), e: nil)
      })
      .onTapGesture(count: 2) { model.spin = Spin() }
    }
    .frame(width: 56, height: 56)
    .accessibilityLabel("English")
    .accessibilityValue("side \(Int(model.spin.x * 100)), follow \(Int(model.spin.y * 100))")
  }
}

/* the only control that shoots (#powerBar): pull along it (upright to the right, on its side down), let go. Idle it
   shows only the chevrons pointing the way to pull, a slow shimmer running along them; pulled, the fill (cream, the
   signal red past 85%) and the percentage */
struct PowerBar: View {
  let model: TableModel
  let upright: Bool
  @State private var t0: Date? = nil
  @State private var fullOnce = false
  @Environment(\.accessibilityReduceMotion) private var still
  var body: some View {
    GeometryReader { g in
      let len = upright ? g.size.width : g.size.height, p = CGFloat(model.power), live = p > 0
      let fill: [Gradient.Stop] = p > 0.85 ? [.init(color: Color(rgb: 0xcf, 0xc6, 0xb2), location: 0), .init(color: Color(rgb: 0xec, 0xe4, 0xd2), location: 0.6), .init(color: Color(rgb: 0xc0, 0x39, 0x2b), location: 1)]
        : [.init(color: Color(rgb: 0xcf, 0xc6, 0xb2), location: 0), .init(color: Color(rgb: 0xec, 0xe4, 0xd2), location: 1)]
      ZStack(alignment: upright ? .leading : .top) {
        RoundedRectangle(cornerRadius: 14).fill(Color(rgb: 0x26, 0x26, 0x2a))
        Rectangle().fill(LinearGradient(stops: fill, startPoint: upright ? .leading : .top, endPoint: upright ? .trailing : .bottom))
          .frame(width: upright ? len * p : nil, height: upright ? nil : len * p)
        if live {
          Text("\(Int((p * 100).rounded()))%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Color(rgb: 0xec, 0xec, 0xee))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: upright ? .trailing : .bottom).padding(upright ? .trailing : .bottom, 10)
        } else if model.rolling == nil, !model.cpuTurn, let lab = model.callLab(upright: upright) ?? (model.callReady ? nil : "Call your shot") {
          /* the call is the bar's own label (callLab): "10 · Top Left", "Safety", "Push Out", or Call your shot */
          HStack(spacing: 6) {
            Text(lab).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.tail)
              .foregroundStyle(model.callReady ? Color(rgb: 0xec, 0xec, 0xee) : Color(rgb: 0xff, 0xd5, 0x8a))
            if model.callMenuOffered { Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa)) }
          }
          .padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if model.rolling != nil {
          Text("Rolling").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa)).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          TimelineView(.animation(minimumInterval: 1 / 30, paused: still || model.paused)) { tl in
            /* pullShimmer: 2.6 s, a band 35% long from -60% to 160% over the first 70%, ease-in-out */
            let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6, u = min(1, t / 0.7), e = u * u * (3 - 2 * u)
            let band = len * 0.35, at = (-0.6 + 2.2 * e) * (len - band)
            ZStack(alignment: upright ? .leading : .top) {
              if !still {
                Rectangle().fill(LinearGradient(colors: [.clear, .white.opacity(0.09), .clear], startPoint: upright ? .leading : .top, endPoint: upright ? .trailing : .bottom))
                  .frame(width: upright ? band : nil, height: upright ? nil : band).offset(x: upright ? at : 0, y: upright ? 0 : at)
              }
              Text("\u{203A}\u{203A}\u{203A}").font(.system(size: 26)).kerning(-2).foregroundStyle(Color(rgb: 0xec, 0xec, 0xee))
                .rotationEffect(.degrees(upright ? 0 : 90))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(rgb: live ? 0x74 : 0x6b, live ? 0x74 : 0x6b, live ? 0x7e : 0x74), lineWidth: 1))
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        guard model.rolling == nil else { return }
        if t0 == nil { t0 = Date() }
        let d = upright ? v.translation.width : v.translation.height
        /* the bar does not arm without a needed call */
        let was = model.power
        model.power = model.callReady ? min(1, max(0, Double(d / len))) : 0
        /* powerFull: the bar at 100%, a soft tick in the ear and one in the hand, once per pull */
        if model.power >= 1 && was < 1 && !fullOnce { fullOnce = true; Sound.shared.cue("full") }
      }.onEnded { v in
        /* a tap (under BAR_TAP 10 pt of travel and BAR_TAP_MS 600 ms) opens the call's menu, never shoots */
        let tap = hypot(v.translation.width, v.translation.height) < 10 && Date().timeIntervalSince(t0 ?? Date()) < 0.6
        t0 = nil; fullOnce = false
        if tap && model.callMenuOffered { model.power = 0; model.callMenu.toggle(); return }
        model.shoot()
      })
    }
    .frame(minWidth: upright ? 136 : 64, maxWidth: .infinity, minHeight: upright ? 56 : 96, maxHeight: upright ? 56 : 440)
    .layoutPriority(1)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Power")
    .accessibilityIdentifier("power")
    /* aria-valuetext: the call's words with the percentage while a call is open (callSay) */
    .accessibilityValue(model.rolling != nil ? "Rolling" : model.callMenuOffered ? "\(model.callLab(upright: upright) ?? "Call your shot"), \(Int(model.power * 100)) percent" : "\(Int(model.power * 100)) percent")
  }
}

/* the quick tournament's state, kept as the page keeps it (felt.tourney.v1, at every change) */
@MainActor @Observable final class TourneyStore {
  var tour: Tourney?
  init() {
    tour = UserDefaults.standard.data(forKey: "felt.tourney.v1").flatMap { try? JSONDecoder().decode(Tourney.self, from: $0) }
    leftover()
  }
  /* tourneyLeftover: a match left by closing the app is forfeited (0 against the race), unless it is no longer the player's */
  private func leftover() {
    guard var t = tour, let m = t.live else { return }
    let o = CareerLib.outcome(t.ctx(), m)
    if o.st != "ready" || (o.a != 0 && o.b != 0) { t.live = nil; tour = t; save(); return }
    let foe = t.foe(m).name
    t.report(m, 0, t.race, forfeit: true)
    t.msg = "Forfeit: the match against \(foe) was left before its end, and counts as a loss."
    tour = t; save()
  }
  /* tourneyPlay: from here, leaving the match is a forfeit, even by closing the app */
  func markLive() { guard var t = tour, let m = t.mine() else { return }; t.live = m; t.msg = ""; tour = t; save() }
  func save() { if let t = tour, let d = try? JSONEncoder().encode(t) { UserDefaults.standard.set(d, forKey: "felt.tourney.v1") } else { UserDefaults.standard.removeObject(forKey: "felt.tourney.v1") } }
  func start(_ t: Tourney) { tour = t; save() }
  func report(_ m: Int, _ mine: Int, _ theirs: Int, _ forfeit: Bool) {
    guard var t = tour else { return }
    let foe = t.foe(m).name
    t.report(m, mine, theirs, forfeit: forfeit)
    t.msg = forfeit ? "Forfeit: the match against \(foe) was left before its end, and counts as a loss." : mine > theirs ? "You beat \(foe) \(mine)-\(theirs)." : "\(foe) beat you \(theirs)-\(mine)."
    tour = t; save()
  }
}

/* the quick tournament (6f): its setup (game, size, format, race, field), then the player's next match, the bracket
   round by round (simulated matches marked), and the places at the end */
struct TourneyView: View {
  @Bindable var store: TourneyStore
  let play: () -> Void
  @State private var kind = "9"
  @State private var size = 8
  @State private var fmt = "single"
  @State private var race = 3
  @State private var field = "mixed"
  static func kindName(_ k: String) -> String { ["8": "8-Ball", "9": "9-Ball", "10": "10-Ball", "straight": "Straight Pool", "rotation": "Rotation", "heyball": "Chinese 8-Ball", "snooker": "Snooker", "carom": "Three-Cushion"][k] ?? k }
  static func game(_ k: String) -> TableGame? { ["8": .eight, "9": .nine, "10": .ten, "straight": .straight, "rotation": .rotation, "heyball": .heyball, "snooker": .snooker, "carom": .carom][k] }
  static func placeWords(_ p: Int) -> String { p == 1 ? "Champion" : p == 2 ? "Runner-up" : "Place \(p)" }
  var body: some View {
    List {
      if let t = store.tour, !t.done { running(t) } else {
        if let t = store.tour, t.done { results(t) }
        setup
      }
    }
    .navigationTitle("Quick Tournament").navigationBarTitleDisplayMode(.inline)
  }
  private var setup: some View {
    Group {
      Section {
        Picker("Game", selection: $kind) { ForEach(Tourney.KINDS, id: \.self) { Text(Self.kindName($0)).tag($0) } }
          .onChange(of: kind) { _, k in race = ["straight": 50, "snooker": 2, "carom": 10][k] ?? 3 }
        Picker("Players", selection: $size) { ForEach(Tourney.SIZES, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
        Picker("Format", selection: $fmt) { Text("Single Elimination").tag("single"); Text("Double Elimination").tag("double") }
        Picker(Tourney.points(kind) ? "Race (Points)" : kind == "snooker" ? "Race (Frames)" : "Race (Racks)", selection: $race) { ForEach(Tourney.races(kind), id: \.self) { Text("\($0)").tag($0) } }
        Picker("Field", selection: $field) { Text("Mixed").tag("mixed"); Text("Rookies").tag("easy"); Text("Regulars").tag("medium"); Text("Hustlers").tag("hard") }
      } header: { Text("New Tournament") } footer: { Text("Your matches are played on the table; the rest are simulated from each player's level and style.") }
      Section {
        Button { store.start(Tourney.make(kind: kind, ruleset: nil, size: size, fmt: fmt, race: race, field: field, seed: Int.random(in: 1...0x7fffffff))) } label: {
          Text("Start Tournament").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
        }
        .background(Capsule().fill(.white)).foregroundStyle(.black).listRowBackground(Color.clear).accessibilityIdentifier("tourney-start")
      }
    }
  }
  @ViewBuilder private func running(_ t: Tourney) -> some View {
    Section {
      if !t.msg.isEmpty { Text(t.msg) }
      if let m = t.mine() {
        let foe = t.foe(m)
        VStack(alignment: .leading, spacing: 2) {
          Text(t.round(m)).font(.footnote).foregroundStyle(.secondary)
          Text("You vs \(foe.name)").font(.headline)
          Text("\(TourneyView.kindName(t.kind)), race to \(t.race), \(TableModel.FOES[foe.level ?? "medium"] ?? "") level").font(.footnote).foregroundStyle(.secondary)
        }
        Button(action: play) { Text("Play Match").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).listRowBackground(Color.clear).accessibilityIdentifier("tourney-play")
      }
    } header: { Text("\(Self.kindName(t.kind)), \(t.size) players, \(t.fmt == "single" ? "single" : "double") elimination") }
    bracket(t)
    Section { Button(role: .destructive) { store.tour = nil; store.save() } label: { Text("Abandon Tournament") } }
  }
  @ViewBuilder private func results(_ t: Tourney) -> some View {
    Section {
      if !t.msg.isEmpty { Text(t.msg) }
      if let p = t.place { Text("You: \(Self.placeWords(p))").font(.headline) }
      ForEach(Array((t.places ?? []).prefix(4).enumerated()), id: \.offset) { _, p in
        HStack { Text(t.field[p[0]].name); Spacer(); Text(Self.placeWords(p[1])).foregroundStyle(.secondary) }
      }
    } header: { Text("Last Tournament") }
    bracket(t)
  }
  /* the bracket by round, in play order: each match's players and score, simulated ones marked */
  @ViewBuilder private func bracket(_ t: Tourney) -> some View {
    let c = t.ctx(), T = t.bracket
    let order = T.M.indices.reduce(into: [String]()) { acc, m in let r = t.round(m); if !acc.contains(r) { acc.append(r) } }
    ForEach(order, id: \.self) { r in
      Section(r) {
        ForEach(T.M.indices.filter { t.round($0) == r }, id: \.self) { m in
          let o = CareerLib.outcome(c, m), nm = { (p: Int?) -> String in p == nil ? "TBD" : p! < 0 ? "Bye" : t.field[p!].name }
          if o.st != "skip" {
            HStack {
              Text("\(nm(o.a)) vs \(nm(o.b))").lineLimit(1).fontWeight(o.a == 0 || o.b == 0 ? .bold : .regular)
              Spacer()
              if let s = t.res[m] { Text("\(s[0])-\(s[1])\(t.sim[m] ? ", simulated" : t.ff[m] ? ", forfeit" : "")").font(.footnote).monospacedDigit().foregroundStyle(.secondary) }
            }
          }
        }
      }
    }
  }
}

/* the party's setup (6f): the game (a ring ruleset: 9-ball ring, rotation ring, Around the table), how many play
   and their names */
struct PartySetup: View {
  let start: (Home.PartyGo) -> Void
  @State private var ruleset = "9-ring"
  @State private var count = 3
  @State private var names = ["", "", "", ""]
  static let SETS: [(String, String, TableGame)] = [("9-ring", "9-Ball Ring", .nine), ("rotation-ring", "Rotation Ring", .rotation), ("straight-ring", "Around the Table", .straight)]
  var body: some View {
    List {
      Section { Picker("Game", selection: $ruleset) { ForEach(Self.SETS, id: \.0) { Text($0.1).tag($0.0) } } }
      Section {
        Picker("Players", selection: $count) { Text("2").tag(2); Text("3").tag(3); Text("4").tag(4) }.pickerStyle(.segmented)
        ForEach(0..<count, id: \.self) { i in TextField("Player \(i + 1)", text: $names[i]).textInputAutocapitalization(.words) }
      } header: { Text("Players") } footer: { Text("The device is passed round as the turn goes to each player; racks won are kept.") }
      Section {
        Button {
          let set = Self.SETS.first { $0.0 == ruleset }!
          let nm = (0..<count).map { i in names[i].trimmingCharacters(in: .whitespaces).isEmpty ? "Player \(i + 1)" : String(names[i].prefix(16)) }
          start(Home.PartyGo(game: set.2, names: nm, ruleset: ruleset))
        } label: { Text("Start").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).listRowBackground(Color.clear).accessibilityIdentifier("party-start")
      }
    }
    .navigationTitle("Party").navigationBarTitleDisplayMode(.inline)
  }
}

/* showHandoff: whose turn it is, what they are on, everyone's score, and Ready; the table hidden under it */
struct Handoff: View {
  let model: TableModel
  let p: Int, first: Bool
  var body: some View {
    let gm = model.g!, P = model.party!, prev = (p + P.names.count - 1) % P.names.count, on = model.engine.legalTargets(gm)
    let why = !first && gm.verdict?.foul != nil ? "\(Words.nameOf(prev)) fouled: \(gm.verdict!.foul!). " : ""
    let what = gm.option != nil ? "A choice to make. " : gm.inHand != nil ? "Ball in hand. " : ""
    let ball = ["9", "rotation"].contains(gm.kind) && !on.isEmpty ? "Ball on: the \(on[0])." : model.engine.callScope(gm) != "none" && !gm.breakShot ? "Call your shot." : ""
    let sub = (why + what + ball).trimmingCharacters(in: .whitespaces)
    ZStack {
      Color(rgb: 9, 9, 10).opacity(0.97).ignoresSafeArea()
      VStack(spacing: 14) {
        Text(first ? "\(gm.rules.name.prefix(1).uppercased() + gm.rules.name.dropFirst()), \(P.names.count) players" : "Pass the device").font(.footnote).foregroundStyle(.secondary)
        Text(first ? "\(Words.nameOf(p)) breaks" : "Pass to \(Words.nameOf(p))").font(.title.weight(.bold)).multilineTextAlignment(.center)
        if !sub.isEmpty { Text(sub).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        VStack(spacing: 0) {
          ForEach(0..<P.names.count, id: \.self) { i in
            HStack {
              Text(P.names[i] + (i == p ? " (to shoot)" : "")).fontWeight(i == p ? .bold : .regular)
              Spacer()
              Text(model.partyScore(i)).monospacedDigit().fontWeight(.bold)
            }
            .padding(.horizontal, 16).frame(minHeight: 44)
            if i < P.names.count - 1 { Divider().padding(.leading, 16) }
          }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)))
        Button { model.handoff = nil } label: { Text("\(Words.nameOf(p)): ready").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("handoff-ready")
      }
      .padding(24).frame(maxWidth: 400)
    }
    .accessibilityElement(children: .contain).accessibilityIdentifier("handoff")
  }
}

/* the exhibition's setup (6f): the game and each CPU player's level, then Start */
struct ExhibitionSetup: View {
  let start: (Home.Exhibit) -> Void
  @State private var game: TableGame = .eight
  @State private var a = "medium"
  @State private var b = "hard"
  @State private var archA = "allround"
  @State private var archB = "allround"
  /* ARCH_WORDS: the career's archetypes as styles */
  static let STYLES = [("allround", "All-Round"), ("potter", "Potter"), ("shotmaker", "Shotmaker"), ("defender", "Defender"), ("positional", "Positional"),
                       ("breaker", "Breaker"), ("banker", "Banker"), ("grinder", "Grinder"), ("clutch", "Clutch")]
  var body: some View {
    List {
      Section { Picker("Game", selection: $game) { ForEach(TableGame.allCases) { Text($0.rawValue).tag($0) } } }
      Section {
        Picker("Player 1", selection: $a) { Text("Rookie").tag("easy"); Text("Regular").tag("medium"); Text("Hustler").tag("hard") }
        Picker("Player 1 Style", selection: $archA) { ForEach(Self.STYLES, id: \.0) { Text($0.1).tag($0.0) } }
        Picker("Player 2", selection: $b) { Text("Rookie").tag("easy"); Text("Regular").tag("medium"); Text("Hustler").tag("hard") }
        Picker("Player 2 Style", selection: $archB) { ForEach(Self.STYLES, id: \.0) { Text($0.1).tag($0.0) } }
      } header: { Text("Players") } footer: { Text("Each searches at its own level through the same physics and rules as any CPU turn.") }
      Section {
        Button { start(Home.Exhibit(game: game, levels: [a, b], archs: [archA, archB])) } label: { Text("Start").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).listRowBackground(Color.clear).accessibilityIdentifier("exhibit-start")
      }
    }
    .navigationTitle("Exhibition").navigationBarTitleDisplayMode(.inline)
  }
}

/* .pc: a player's card in the pause menu: the turn mark (the signal red, lit, for the player to shoot), the name, and a
   second line with the group or score in words (cardOf) and its balls as dots */
struct PlayerCard: View {
  let model: TableModel
  let p: Int
  var body: some View {
    let c = model.cardOf(p), on = model.g?.turn == p && model.g?.winner == nil
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        Circle().fill(on ? Color(rgb: 0xc0, 0x39, 0x2b) : .clear)
          .overlay(Circle().strokeBorder(on ? .clear : Color(rgb: 0x6b, 0x6b, 0x74), lineWidth: 1.5))
          .background(Circle().stroke(on ? Color(.sRGB, red: 192 / 255, green: 57 / 255, blue: 43 / 255, opacity: 0.28) : .clear, lineWidth: 3).padding(-1.5))
          .frame(width: 8, height: 8)
        Text(model.cardName(p)).font(.body.weight(.bold)).lineLimit(1).truncationMode(.tail)
      }
      if !c.meta.isEmpty { Text(c.meta).font(.system(size: 12)).monospacedDigit().foregroundStyle(c.warn ? Color(hex: 0xffe27a) : Color(rgb: 0xa3, 0xa3, 0xaa)).lineLimit(1) }
      if !c.dots.isEmpty { FlowDots(dots: c.dots, size: 12) }
    }
    .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color(.sRGB, red: 38 / 255, green: 38 / 255, blue: 42 / 255, opacity: 0.96) : Color(rgb: 0x26, 0x26, 0x2a)))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color(rgb: 0x74, 0x74, 0x7e) : Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
    .accessibilityElement(children: .combine)
  }
}
/* dotEl: a ball as a flat dot, its colour (colorOf), a stripe's ivory caps, bumper's marked spot, a dark ball ringed so
   it reads on the dark panel (darkBall: under 3:1 on #26262a), an inset shade; wrapped as the page's flex-wrap */
struct FlowDots: View {
  let dots: [Int]
  let size: CGFloat
  var body: some View {
    let cols = max(1, Int(9 * 12 / size))
    VStack(alignment: .leading, spacing: 3) {
      ForEach(Array(stride(from: 0, to: dots.count, by: cols)), id: \.self) { i in
        HStack(spacing: size > 13 ? 3 : 2) { ForEach(dots[i..<min(dots.count, i + cols)], id: \.self) { Dot(n: $0, size: size) } }
      }
    }
  }
}
struct Dot: View {
  let n: Int
  let size: CGFloat
  var body: some View {
    let c = ballColor(n), col = Color(rgb: c.0, c.1, c.2)
    let lum = { (v: Int) -> Double in let x = Double(v) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    let L = 0.2126 * lum(c.0) + 0.7152 * lum(c.1) + 0.0722 * lum(c.2), Lp = 0.2126 * lum(38) + 0.7152 * lum(38) + 0.0722 * lum(42)
    let dark = !(n > 20 && n < 40) && (n > 40 || n <= 8) && (L + 0.05) / (Lp + 0.05) < 3
    ZStack {
      Circle().fill(col)
      if n > 8 && n < 16 {
        Circle().fill(LinearGradient(stops: [.init(color: Color(hex: 0xf6f4ec), location: 0), .init(color: Color(hex: 0xf6f4ec), location: 0.24),
          .init(color: .clear, location: 0.24), .init(color: .clear, location: 0.76), .init(color: Color(hex: 0xf6f4ec), location: 0.76), .init(color: Color(hex: 0xf6f4ec), location: 1)],
          startPoint: .top, endPoint: .bottom))
      }
      if n == 21 || n == 31 { Circle().fill(n == 21 ? Color(hex: 0xf7f4ea) : Color(hex: 0xc8262c)).frame(width: size * 0.52, height: size * 0.52) }
      Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.35)], center: UnitPoint(x: 0.4, y: 0.4), startRadius: size * 0.2, endRadius: size * 0.6))
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(dark ? Color(rgb: 0xa3, 0xa3, 0xaa) : .black.opacity(0.3), lineWidth: dark ? 1.5 : 1).padding(dark ? -0.75 : -0.5))
    .padding(.horizontal, dark ? 1.5 : 0)
    .accessibilityLabel(String(n))
  }
}

/* the call's menu (#callBar, 6p's pop-up material) over the power bar: Change or Clear Call, the pockets as a
   picture of the table as the player sees it (callPkMap: a 3 x 3 grid, the called one checked), Bank, Kick and Combo
   under a detailed call, Safety where the rules allow one, Push Out when it is on offer. A pick or a tap outside closes it. */
struct CallMenu: View {
  let model: TableModel
  var body: some View {
    let c = model.humanCall(), gm = model.g!, need = model.engine.callNeed(gm)
    let open = model.callOn, push = model.pushOffer
    let change = open && !model.callSafe && !(model.callPushOn && push) && c?.ball != nil && !model.callLocked
    let showPk = open && !model.callSafe && !(model.callPushOn && push) && !model.callLocked && need?.pocket == true
    let flags = need?.flags == true && !model.callSafe && !(model.callPushOn && push)
    ZStack(alignment: .bottomTrailing) {
      Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.callMenu = false }
      VStack(alignment: .leading, spacing: 0) {
        if change { row(c?.auto == true ? "Change Call" : "Clear Call", false) { model.changeCall() } }
        if showPk {
          Text(c?.ball != nil ? "Pocket for the \(c!.ball!)" : "Pocket").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 10)
          pockets(c).padding(.horizontal, 12).padding(.vertical, 8)
          Divider()
        }
        if flags {
          row("Bank", c?.bank == true) { model.toggleFlag("bank") }
          row("Kick", c?.kick == true) { model.toggleFlag("kick") }
          row("Combo", c?.combo == true) { model.toggleFlag("combo") }
        }
        if open && gm.rules.safetyCall { row("Safety", model.callSafe) { model.toggleSafety() } }
        if push { row("Push Out", model.callPushOn) { model.togglePush() } }
      }
      .frame(width: 250)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      .accessibilityElement(children: .contain).accessibilityIdentifier("callMenu")
      .padding(.trailing, 60).padding(.bottom, 70)
    }
  }
  private func row(_ t: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
    Button { act(); model.callMenu = false } label: {
      HStack(spacing: 8) {
        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).opacity(on ? 1 : 0)
        Text(t).font(.body)
        Spacer()
      }
      .padding(.horizontal, 16).frame(minHeight: 44).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
  /* the pockets laid out as the table is seen: upright the long table's six (corners top and bottom, sides at the middle) */
  private func pockets(_ c: ShotCall?) -> some View {
    let s = model.sim, up = model.uprightView
    let cells: [(Int, Int, Int)] = s.POCKET_AIM.indices.map { k in
      let p = s.POCKET_AIM[k], f = up ? p[0] - s.TL / 2 : s.TW / 2 - p[1], r = up ? p[1] - s.TW / 2 : p[0] - s.TL / 2
      return (k, f > 0.01 ? 0 : f < -0.01 ? 2 : 1, r < -0.01 ? 0 : r > 0.01 ? 2 : 1)
    }
    let rows = Array(Set(cells.map { $0.1 })).sorted(), cols = Array(Set(cells.map { $0.2 })).sorted()
    return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
      ForEach(rows, id: \.self) { rr in
        GridRow {
          ForEach(cols, id: \.self) { cc in
            if let k = cells.first(where: { $0.1 == rr && $0.2 == cc })?.0 {
              Button { model.pickPocket(k); model.callMenu = false } label: {
                ZStack {
                  Circle().fill(Color.black).frame(width: 34, height: 34)
                  if c?.pocket == k { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
              }
              .buttonStyle(.plain).accessibilityLabel(model.pocketShort(k, upright: up)).accessibilityIdentifier("pocket-\(k)")
            } else { Color.clear.frame(width: 44, height: 44) }
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(rgb: 0x1b, 0x5d, 0x47).opacity(0.6)))
  }
}

/* #banner (flash): a word over the table, on the half away from what the player needs to see (placeBanner): the
   kitchen or the D while the ball is in hand there, else the cue ball; upright 27% or 73% down the table. The page's
   box: rgba(22, 22, 24, .94), a hairline of --line, 12 pt corners, the head 16 bold, the line under it 12 muted; a
   foul in the signal red */
struct FlashBanner: View {
  let model: TableModel
  let size: CGSize
  var body: some View {
    if let b = model.banner, !model.paused {
      let s = model.sim, m = Mapper(size: size, TL: s.TL, TW: s.TW)
      let a = m.pt(0, 0), z = m.pt(s.TL, s.TW), top = min(a.y, z.y), H = abs(z.y - a.y), left = min(a.x, z.x), W = abs(z.x - a.x)
      let at: CGPoint = model.inHand && s.TABLE != "carom" ? m.pt(s.HEAD_X / 2, s.TW / 2) : model.cue.map { m.pt($0.x, $0.y) } ?? m.pt(s.TL / 2, s.TW / 2)
      let foul = b.title.hasPrefix("Foul")
      let pos: CGPoint = m.upright ? CGPoint(x: left + W / 2, y: top + H * (at.y > top + H / 2 ? 0.27 : 0.73))
        : CGPoint(x: left + W * (at.x > left + W / 2 ? 0.32 : 0.68), y: top + H * (at.y >= top + H / 2 ? 0.3 : 0.7))
      VStack(spacing: 1) {
        Text(b.title).font(.system(size: 16, weight: .bold)).kerning(-0.16)
        if !b.sub.isEmpty { Text(b.sub).font(.system(size: 12)).foregroundStyle(foul ? .white : Color(rgb: 0xa3, 0xa3, 0xaa)) }
      }
      .multilineTextAlignment(.center)
      /* width: max-content, up to min(84%, 300) with the padding */
      .frame(maxWidth: min(size.width * 0.84, 300) - 28)
      .fixedSize()
      .padding(.horizontal, 14).padding(.top, 7).padding(.bottom, 8)
      .background(RoundedRectangle(cornerRadius: 12).fill(foul ? Color(rgb: 0xc0, 0x39, 0x2b) : Color(.sRGB, red: 22 / 255, green: 22 / 255, blue: 24 / 255, opacity: 0.94)))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(foul ? Color(rgb: 0xd9, 0x58, 0x4a) : Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
      .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
      .position(pos)
      .allowsHitTesting(false)
      .transition(.opacity)
      .accessibilityElement(children: .combine)
    }
  }
}

/* over the table: the banner after a shot (flash), a choice the rules give (5c's option box), and the
   game over (showOver), each in the HIG's materials */
struct Overlays: View {
  let model: TableModel
  let back: () -> Void
  var body: some View {
    if model.paused {
      /* the pause menu (6): what game this is, the latest word (#menuMsg), Resume, Restart, Quit to Home */
      card {
        Text("Paused, \(model.game.rawValue)" + (model.cpuLevel != nil ? " vs \(model.cardName(1).replacingOccurrences(of: " (CPU)", with: ""))" : "")).font(.footnote).foregroundStyle(.secondary)
        /* gameNow: both players' cards (the shooter's lit), the potted balls in pot order, the latest word */
        /* a card per player: two side by side, a party's three or four two to a row */
        let n = model.party?.names.count ?? 2
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
          ForEach(Array(stride(from: 0, to: n, by: 2)), id: \.self) { r in
            GridRow { PlayerCard(model: model, p: r); if r + 1 < n { PlayerCard(model: model, p: r + 1) } else { Color.clear } }
          }
        }
        if model.game != .carom {
          HStack(spacing: 10) {
            Text("POTTED").font(.system(size: 12, weight: .bold)).kerning(1.1).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa))
            let pr = model.pottedRow
            if pr.isEmpty { Text("none yet").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa)) }
            else { FlowDots(dots: pr, size: 18) }
            Spacer(minLength: 0)
          }
          .frame(minHeight: 30)
        }
        if !model.msg.isEmpty { Text(model.msg).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa)).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("msg") }
        Button { model.paused = false } label: { Label("Resume", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("resume")
        Button { model.paused = false; model.rerack() } label: { Label("Restart", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 44) }
          .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
        Button { model.paused = false; model.tourneyAbandon(); back() } label: { Text(model.tmatch != nil ? "Forfeit Match" : "Quit to Home").frame(maxWidth: .infinity, minHeight: 44) }
          .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
      }
    } else if let g = model.g, g.winner != nil, model.rolling == nil {
      card {
        Text(Words.overLine(g)).font(.headline).multilineTextAlignment(.center)
        if let t = model.tmatch {
          /* a tournament match: the racks, then the next rack or back to the bracket */
          Text("You \(t.score[0]), \(t.foe) \(t.score[1]), race to \(t.need)").font(.subheadline).foregroundStyle(.secondary)
          if t.done {
            Button(action: back) { Text("Back to Tournament").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
              .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("tourney-back")
          } else {
            Button { model.tourneyNextRack() } label: { Text("Next Rack").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
              .background(Capsule().fill(.white)).foregroundStyle(.black)
          }
        } else {
          Button { model.party != nil ? model.partyAgain() : model.rerack() } label: { Text("Play Again").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black)
          Button(action: back) { Text("Home").frame(maxWidth: .infinity, minHeight: 44) }
        }
      }
    } else if let g = model.g, let o = g.option, model.rolling == nil {
      card {
        Text(Words.OPT[o.kind]?["head"] ?? o.kind).font(.headline)
        Text("\(Words.nameOf(o.who)): \(Words.OPT[o.kind]?["sub"] ?? "")").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        if model.cpuTurn { Text("CPU choosing").font(.footnote).foregroundStyle(.secondary) }
        else { ForEach(o.choices.flatMap { c in c == "free" ? model.engine.snkFreeBalls(g).map { "free:\($0)" } : [c] }, id: \.self) { c in
          Button { model.choose(c) } label: {
            Text(c.hasPrefix("free:") ? "Free ball: \(snkName(Int(c.dropFirst(5))!))" : Words.optLabel(o.kind, c)).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
          }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
            .accessibilityIdentifier("choice-\(c)")
        } }
      }
    }
  }
  private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    VStack(spacing: 12, content: c)
      .padding(20).frame(maxWidth: 340)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
      .padding(24)
  }
}
