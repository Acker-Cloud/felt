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
  @State private var playing: Game?
  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(Game.allCases) { g in
            Button { playing = g } label: {
              VStack(alignment: .leading, spacing: 2) {
                Text(g.rawValue).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(g.line).font(.footnote).foregroundStyle(.secondary)
              }.frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("game-\(g.rawValue)")
          }
        } header: { Text("Practice") } footer: {
          Text("The web build's physics, bit for bit. Rules, the CPU and the career come next.")
        }
      }
      .navigationTitle("felt")
      .tint(.primary)
    }
    /* a test hook, like the page's window.felt: `-felt-game "9-Ball"` opens that table */
    .onAppear {
      let a = ProcessInfo.processInfo.arguments
      if let i = a.firstIndex(of: "-felt-game"), i + 1 < a.count { playing = Game(rawValue: a[i + 1]) }
    }
    .fullScreenCover(item: $playing) { g in TableScreen(model: TableModel(game: g)) }
  }
}

struct TableScreen: View {
  @State var model: TableModel
  @Environment(\.dismiss) private var dismiss
  @State private var aimDrag: Double?
  @State private var placing = false

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
          .contentShape(Rectangle())
          .gesture(DragGesture(minimumDistance: 0).onChanged { v in touch(v, tg.size, began: v.translation == .zero) }
            .onEnded { _ in placing = false })
          .accessibilityElement()
          .accessibilityLabel("Table")
          .accessibilityIdentifier("table")
        }
        Controls(model: model, upright: upright, back: { dismiss() })
          .frame(width: upright ? nil : 84, height: upright ? 96 : nil)
      }
      .padding(.horizontal, upright ? 0 : 8)
    }
    .background(Color(rgb: 9, 9, 10).ignoresSafeArea())
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
