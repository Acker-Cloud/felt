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
  @Environment(\.displayScale) private var scale

  var body: some View {
    GeometryReader { geo in
      let upright = geo.size.height > geo.size.width
      let layout = upright ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
      layout {
        GeometryReader { tg in
          TimelineView(.animation) { tl in
            TableCanvas(model: model, look: Look.of(model.game))
              .onChange(of: tl.date) { _, d in model.tick(d.timeIntervalSinceReferenceDate) }
          }
          .onAppear { model.bake(tg.size, scale: scale) }
          .onChange(of: tg.size) { _, s in model.bake(s, scale: scale) }
          .contentShape(Rectangle())
          .gesture(DragGesture(minimumDistance: 0).onChanged { v in touch(v, tg.size, began: v.translation == .zero) }
            .onEnded { _ in placing = false })
          .accessibilityElement()
          .accessibilityLabel("Table")
          .accessibilityIdentifier("table")
        }
        Text(model.cpuThinking ? "CPU thinking" : model.msg).font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, minHeight: 32).padding(.horizontal, 12)
          .accessibilityIdentifier("msg")
        Controls(model: model, upright: upright, back: { dismiss() })
          .frame(width: upright ? nil : 84, height: upright ? 96 : nil)
      }
      .padding(.horizontal, upright ? 0 : 8)
    }
    .background(Color(rgb: 9, 9, 10).ignoresSafeArea())
    .overlay { Overlays(model: model, back: { dismiss() }) }
    .tint(.primary)
    .statusBarHidden()
  }

  private func touch(_ v: DragGesture.Value, _ size: CGSize, began: Bool) {
    let s = model.sim, m = Mapper(size: size, TL: s.TL, TW: s.TW)
    let (x, y) = m.table(v.location)
    if began, model.inHand, let c = model.cue, JSMath.hypot(c.x - x, c.y - y) < s.BALL_R * 3 { placing = true }
    if placing { model.place(x, y); return }
    guard model.rolling == nil, let c = model.cue else { return }
    if JSMath.hypot(x - c.x, y - c.y) > s.BALL_R { model.aim = atan2(y - c.y, x - c.x) }
  }
}

struct Controls: View {
  let model: TableModel
  let upright: Bool
  let back: () -> Void
  var body: some View {
    let items = Group {
      Button(action: back) { Image(systemName: "chevron.backward").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
        .background(Circle().fill(Color(white: 0.17))).accessibilityLabel("Back")
      Button { model.rerack() } label: { Image(systemName: "arrow.counterclockwise").font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
        .background(Circle().fill(Color(white: 0.17))).accessibilityLabel("Re-rack").disabled(model.rolling != nil)
      FineWheel(model: model, upright: upright)
      SpinPad(model: model)
      PowerBar(model: model, upright: upright)
    }
    if upright { HStack(spacing: 10) { items }.padding(.horizontal, 12) } else { VStack(spacing: 10) { items }.padding(.vertical, 8) }
  }
}

/* fine aim: a drag along the wheel turns the aim a little (0.15 degrees a point) */
struct FineWheel: View {
  let model: TableModel
  let upright: Bool
  @State private var last: CGFloat = 0
  var body: some View {
    RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.14))
      .overlay {
        Canvas { ctx, size in
          let n = 14, off = CGFloat((model.aim * 400).truncatingRemainder(dividingBy: 1)) * (upright ? size.width : size.height) / CGFloat(n)
          for i in 0...n {
            var p = Path()
            if upright { let x = CGFloat(i) * size.width / CGFloat(n) + off; p.move(to: CGPoint(x: x, y: 10)); p.addLine(to: CGPoint(x: x, y: size.height - 10)) }
            else { let y = CGFloat(i) * size.height / CGFloat(n) + off; p.move(to: CGPoint(x: 10, y: y)); p.addLine(to: CGPoint(x: size.width - 10, y: y)) }
            ctx.stroke(p, with: .color(.white.opacity(0.25)), lineWidth: 1)
          }
        }
      }
      .frame(width: upright ? 80 : 64, height: upright ? 64 : 80)
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        let d = upright ? v.translation.width : v.translation.height
        if model.rolling == nil { model.aim += Double(d - last) * 0.15 * .pi / 180 }
        last = d
      }.onEnded { _ in last = 0 })
      .accessibilityLabel("Fine aim")
  }
}

/* english: where the tip meets the ball, top is follow, bottom draw, side either way */
struct SpinPad: View {
  let model: TableModel
  var body: some View {
    GeometryReader { g in
      let r = min(g.size.width, g.size.height) / 2
      ZStack {
        Circle().fill(Color(rgb: 247, 244, 234))
        Circle().fill(Color.red).frame(width: 10, height: 10)
          .offset(x: CGFloat(model.spin.x) * r * 0.8, y: -CGFloat(model.spin.y) * r * 0.8)
      }
      .contentShape(Circle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        let dx = (v.location.x - g.size.width / 2) / (r * 0.8), dy = -(v.location.y - g.size.height / 2) / (r * 0.8)
        model.spin = spinOf(x: Double(dx), y: Double(dy), e: nil)
      })
      .onTapGesture(count: 2) { model.spin = Spin() }
    }
    .frame(width: 56, height: 56)
    .accessibilityLabel("English")
    .accessibilityValue("side \(Int(model.spin.x * 100)), follow \(Int(model.spin.y * 100))")
  }
}

/* the only control that shoots: pull down (or toward the table's foot on its side), let go */
struct PowerBar: View {
  let model: TableModel
  let upright: Bool
  var body: some View {
    GeometryReader { g in
      let len = upright ? g.size.width : g.size.height
      ZStack(alignment: upright ? .leading : .top) {
        RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.14))
        RoundedRectangle(cornerRadius: 12)
          .fill(LinearGradient(colors: [Color(white: 0.85), Color(rgb: 230, 180, 60)], startPoint: .leading, endPoint: .trailing))
          .frame(width: upright ? len * CGFloat(model.power) : nil, height: upright ? nil : len * CGFloat(model.power))
        Text(model.power > 0 ? "\(Int(model.power * 100))%" : model.rolling != nil ? "Rolling" : "")
          .font(.footnote.weight(.semibold)).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        guard model.rolling == nil else { return }
        let d = upright ? v.translation.width : v.translation.height
        model.power = min(1, max(0, Double(d / len)))
      }.onEnded { _ in model.shoot() })
    }
    .frame(minWidth: upright ? 100 : 56, minHeight: upright ? 56 : 100)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Power")
    .accessibilityIdentifier("power")
    .accessibilityValue(model.rolling != nil ? "Rolling" : "\(Int(model.power * 100)) percent")
  }
}

/* over the table: the banner after a shot (flash), a choice the rules give (5c's option box), and the
   game over (showOver), each in the HIG's materials */
struct Overlays: View {
  let model: TableModel
  let back: () -> Void
  var body: some View {
    if let g = model.g, g.winner != nil, model.rolling == nil {
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
    } else if let b = model.banner {
      VStack(spacing: 4) {
        Text(b.title).font(.title3.weight(.semibold))
        if !b.sub.isEmpty { Text(b.sub).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
      }
      .padding(.horizontal, 20).padding(.vertical, 12)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
      .allowsHitTesting(false)
      .transition(.opacity)
    }
  }
  private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    VStack(spacing: 12, content: c)
      .padding(20).frame(maxWidth: 340)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
      .padding(24)
  }
}
