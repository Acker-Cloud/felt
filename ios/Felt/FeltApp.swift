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
        } header: { Text("Practice") } footer: {
          Text("The web build's physics, rules and CPU, bit for bit.")
        }
      }
      .navigationTitle("felt")
      .tint(.primary)
    }
    /* a test hook, like the page's window.felt: `-felt-game "9-Ball"` opens that table */
    .onAppear {
      let a = ProcessInfo.processInfo.arguments
      if let i = a.firstIndex(of: "-felt-game"), i + 1 < a.count { playing = TableGame(rawValue: a[i + 1]) }
    }
    .fullScreenCover(item: $playing) { g in TableScreen(model: TableModel(game: g, cpu: opponent == "two" ? nil : opponent)) }
  }
}

struct TableScreen: View {
  @State var model: TableModel
  @Environment(\.dismiss) private var dismiss
  @State private var aimDrag: Double?
  @State private var placing = false
  @State private var picking = false
  @Environment(\.displayScale) private var scale

  var body: some View {
    GeometryReader { geo in
      let ins = geo.safeAreaInsets, W = geo.size.width + ins.leading + ins.trailing, H = geo.size.height + ins.top + ins.bottom
      let upright = H > W
      /* #ui: padding max(2, the insets), max(4) at the foot; upright the stage over one 56 pt strip (#ctl), 4 apart,
         the strip stood in from the sides by 0.35 of the foot's inset (the display's rounded corners) */
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
      .offset(x: -ins.leading, y: -ins.top)
    }
    .background(Color(rgb: 9, 9, 10).ignoresSafeArea())
    .overlay { Overlays(model: model, back: { dismiss() }) }
    .overlay(alignment: .bottomTrailing) { if model.callMenu && model.callMenuOffered { CallMenu(model: model) } }
    .tint(.primary)
    .statusBarHidden()
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
        model.power = model.callReady ? min(1, max(0, Double(d / len))) : 0
      }.onEnded { v in
        /* a tap (under BAR_TAP 10 pt of travel and BAR_TAP_MS 600 ms) opens the call's menu, never shoots */
        let tap = hypot(v.translation.width, v.translation.height) < 10 && Date().timeIntervalSince(t0 ?? Date()) < 0.6
        t0 = nil
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
        Text("Paused, \(model.game.rawValue)" + (model.cpuLevel != nil ? " vs CPU" : "")).font(.footnote).foregroundStyle(.secondary)
        if !model.msg.isEmpty { Text(model.msg).font(.body).multilineTextAlignment(.center).accessibilityIdentifier("msg") }
        Button { model.paused = false } label: { Label("Resume", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("resume")
        Button { model.paused = false; model.rerack() } label: { Label("Restart", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 44) }
          .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
        Button { model.paused = false; back() } label: { Text("Quit to Home").frame(maxWidth: .infinity, minHeight: 44) }
          .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2)))
      }
    } else if let g = model.g, g.winner != nil, model.rolling == nil {
      card {
        Text(Words.overLine(g)).font(.headline).multilineTextAlignment(.center)
        Button { model.rerack() } label: { Text("Play Again").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black)
        Button(action: back) { Text("Home").frame(maxWidth: .infinity, minHeight: 44) }
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
