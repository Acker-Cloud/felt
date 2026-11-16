/* felt, native. Home lists the tables; a table is aimed by touch, fine-tuned on the wheel, given
   english on the pad and shot from the power bar alone: pull it down, let go. */
import FeltSim
import QuartzCore
import SwiftUI
import UIKit

@main
struct FeltApp: App {
  init() { Prefs.boot() }
  var body: some Scene {
    WindowGroup {
      Home().preferredColorScheme(.dark).statusBarHidden()
        /* at a table, an edge swipe takes two (the first only lights the home bar): set at the window's root too, where
           UIKit asks; the bar stays shown (a hidden bar is not deferred) */
        .defersSystemGestures(on: Chrome.shared.atTable > 0 && !Chrome.noDefer ? .all : [])
    }
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
  @State private var career = CareerStore()
  @State private var showCareer = false
  @State private var setupGame: TableGame? = nil
  @State private var intro = IntroModel()
  @State private var titleRect = CGRect.zero
  @State private var statsPath: String? = nil
  /* a practice session's layout (startPractice) */
  @State private var practicing: PracticeGo? = nil
  @State private var tricking: PracticeGo? = nil
  @State private var drilling: PracticeGo? = nil
  @State private var tutoring: PracticeGo? = nil
  @State private var lessoning = false
  @State private var lessonOffer = false
  @State private var helpPath: String? = nil
  @State private var prefsOpen = false
  /* `-felt-mode tour|ex|party`: a mode's page open */
  @State private var modePath: String? = nil
  struct PracticeGo: Identifiable { let layout: String; var id: String { layout } }
  /* How to play's actions: the lesson, a game's tutorial, the drills, the career (More Modes: the home's Modes section) */
  private var helpActs: HelpActions {
    HelpActions(lesson: { lessoning = true }, tutorial: { tutoring = PracticeGo(layout: $0) }, modes: { helpPath = nil }, drills: { helpPath = "drills" }, career: { showCareer = true })
  }
  /* maybeOfferLesson: once the opening is over, on a first run (no test hook) */
  private func maybeOfferLesson(_ s: IntroModel.State) {
    guard s == .done, !LessonStore.rec.seen, !ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-felt-") && $0 != "-felt-intro" && $0 != "-felt-offer" }) else { return }
    lessonOffer = true
  }
  /* Solo: Learn to Play (the lesson), Practice (#pracSheet, 5s), Trick Shots, Daily Shot, Drills */
  private func soloSection(_ side: Bool) -> some View {
    let day = Rec.today(), st = DailyStore.streak(day), done = DailyStore.done(day), dt = dailyTrick(day)
    return VStack(spacing: 0) {
      Button { lessoning = true } label: { SoloRow(icon: "graduationcap", name: "Learn to Play", line: "A 30 second lesson", side: side) }
        .accessibilityIdentifier("solo-lesson")
      NavigationLink { PracticePicker { practicing = PracticeGo(layout: $0) } } label: { SoloRow(icon: "scope", name: "Practice", line: "Free play on any rack", side: side) }
        .accessibilityIdentifier("solo-practice")
      NavigationLink { DrillsList { drilling = PracticeGo(layout: $0) } } label: {
        SoloRow(icon: "chart.bar.fill", name: "Drills", line: "\(DRILL_LIB.count) drills, scored", acc: "\(DrillStore.medals) of \(DRILL_LIB.count * 3)", accIcon: "medal.fill", accTint: Color(rgb: 0xf2, 0xc9, 0x4c), side: side)
      }
      .accessibilityIdentifier("solo-drills")
      NavigationLink { TricksList { tricking = PracticeGo(layout: $0) } } label: {
        SoloRow(icon: "sparkles", name: "Trick Shots", line: "\(TRICKS.count) challenges", acc: "\(programTotal(TrickStore.score.pts)) of \(programMax())", accIcon: "star.fill", side: side)
      }
      .accessibilityIdentifier("solo-tricks")
      /* #dailyBtn: the day's number on a calendar leaf, today's shot, the streak (or Done today) */
      Button { tricking = PracticeGo(layout: "daily") } label: {
        SoloRow(icon: nil, day: Int(day.suffix(2)) ?? 1, name: "Daily Shot", line: dt.title, acc: done ? "Done today" : st > 0 ? "\(st)" : nil, accIcon: done ? "checkmark" : st > 0 ? "flame.fill" : nil, side: side)
      }
      .accessibilityLabel("Daily Shot, \(DrillStore.dayWords(day)): \(dt.title). " + (done ? "Played today, day streak \(st)." : st > 0 ? "Day streak \(st): play today to keep it." : "A new shot every day."))
      .accessibilityIdentifier("solo-daily")
    }
    .buttonStyle(RowPress())
    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
  }
  @State private var art = HomeArtStore()
  /* 6m: the cards' morphs into their pages */
  @State private var mo = Morph()
  private func face(_ g: TableGame) -> Morph.Face { Morph.Face(game: g, art: art.img[g.rawValue], scale: art.scale) }
  static let GLOW: [String: (Double, Double, Double)] = ["mode-career": (242, 201, 76), "mode-tourney": (242, 201, 76), "mode-exhibit": (246, 244, 236), "mode-party": (38, 150, 104)]
  /* a mode card: its page pushed under the morph */
  private func modeCard<L: View>(_ id: String, _ push: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
    Button { mo.zoom = Double(textSize) / 100; mo.open(id, Morph.Face(glow: Self.GLOW[id]!), push: push) } label: {
      label().onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mo.cards[id, default: .init()].rect = $0 }
    }
    .accessibilityIdentifier(id)
  }
  private func modeBack(_ id: String, _ pop: @escaping () -> Void) -> MorphBack { MorphBack { mo.close(id, Morph.Face(glow: Self.GLOW[id]!), pop: pop) } }
  /* #modeRow: the four modes, two to a row; rowMin, on its side, the height each row takes beside the solo list (each
     card its own shape at the row's top) */
  private func modesGrid(cols: [GridItem], gap: CGFloat, rowMin: CGFloat) -> some View {
    let ar = side ? cardAr : 1.7, row = rowMin > 0 ? rowMin : nil
    return LazyVGrid(columns: cols, spacing: gap) {
      modeCard("mode-career", { showCareer = true }) {
        ModeCard(name: "Career", line: career.loaded ? "\(career.E.S["profile"]?["name"]?.str ?? "Career"), season \(career.E.season)" : "Your player, 300 rivals", glow: Self.GLOW["mode-career"]!, ar: ar, cc: true) {
          Image(systemName: "person.crop.circle.fill").font(.system(size: 22)).foregroundStyle(Color(rgb: 0xf2, 0xc9, 0x4c))
        }
      }
      .frame(minHeight: row, alignment: .top)
      modeCard("mode-tourney", { modePath = "tour" }) {
        ModeCard(name: "Quick Tournament", line: store.tour.map { $0.done ? "Finished: \(TourneyView.placeWords($0.place ?? 0))" : "In progress, \(TourneyView.kindName($0.kind))" } ?? "Bracket of 4, 8 or 16", glow: Self.GLOW["mode-tourney"]!, ar: ar) {
          Image(systemName: "trophy.fill").font(.system(size: 19)).foregroundStyle(Color(rgb: 0xf2, 0xc9, 0x4c))
        }
      }
      .frame(minHeight: row, alignment: .top)
      modeCard("mode-exhibit", { modePath = "ex" }) {
        ModeCard(name: "AI Exhibition", line: "Watch two CPUs play", glow: Self.GLOW["mode-exhibit"]!, ar: ar) {
          ZStack { Circle().fill(Color(white: 0.96)).frame(width: 11, height: 11).offset(x: -4, y: 3); Circle().fill(Color(rgb: 0xf2, 0xc9, 0x4c)).frame(width: 9, height: 9).offset(x: 5, y: -4) }
        }
      }
      .frame(minHeight: row, alignment: .top)
      modeCard("mode-party", { modePath = "party" }) {
        ModeCard(name: "Party", line: "2 to 4 players", glow: Self.GLOW["mode-party"]!, ar: ar) {
          Image(systemName: "person.2.fill").font(.system(size: 16)).foregroundStyle(.white)
        }
      }
      .frame(minHeight: row, alignment: .top)
    }
    .buttonStyle(Press())
  }
  /* a .tile: the game's rack art under its name and line (bottom left); a tap opens its setup */
  private func gameCard(_ g: TableGame) -> some View {
    let id = "game-\(g.rawValue)", strip = side && g == .heyball
    return Button { mo.zoom = Double(textSize) / 100; mo.open(id, face(g)) { setupGame = g } } label: {
      Color.clear.aspectRatio(oneCol || strip ? nil : side ? cardAr : 1.7, contentMode: .fit)
        .frame(maxWidth: .infinity).frame(height: oneCol ? 84 : nil)
        .overlay {
          GeometryReader { geo in
            let narrow = geo.size.width <= 184
            /* on its side the ninth is a strip: its name and line on one row, in the middle of it */
            let words = strip ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            ZStack(alignment: strip ? .leading : .bottomLeading) {
              Color(rgb: 0x12, 0x12, 0x14)
              if let img = art.img[g.rawValue] { Image(decorative: img, scale: art.scale).resizable().transition(.opacity) }
              words {
                Text(g.rawValue).font(.system(size: narrow ? 16 : 17, weight: .semibold)).kerning(-0.2)
                  .opacity(mo.cardTitleHidden == id ? 0 : 1)
                  .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mo.cards[id, default: .init()].title = $0; mo.cards[id]?.narrow = narrow }
                  .layoutPriority(strip ? 1 : 0)
                Text(HomeArt.line(g)).font(.system(size: narrow ? 12 : 13)).foregroundStyle(.white.opacity(0.74))
                  .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mo.cards[id, default: .init()].line = $0 }
              }
              .lineLimit(1).foregroundStyle(.white)
              .padding(.horizontal, narrow ? 12 : 14).padding(.bottom, strip ? 0 : narrow ? 12 : 13)
            }
            /* every size the card takes, from the first (onChange(of: geo.size) missed the last one of a turn on its side:
               the art painted for a passing 87x70 and stretched over the 201x118 card), its words' height with it */
            .onGeometryChange(for: CGSize.self) { $0.size } action: { n in art.want(g, n.width, n.height, n.width <= 184 ? 48 : 52) }
          }
        }
        .frame(height: strip ? 48 : g == .heyball && !oneCol ? art.rowH : nil)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mo.cards[id, default: .init()].rect = $0 }
    }
    .buttonStyle(Press())
    .accessibilityLabel("\(g.rawValue), \(HomeArt.line(g))")
    .accessibilityIdentifier("game-\(g.rawValue)")
  }
  /* #leftNote: a game left by closing the app counted as a loss, once, until OK or LEFT_MS */
  @State private var leftNote = false
  @State private var booted = false
  @AppStorage("felt.settings.text") private var textSize = 100
  private var oneCol: Bool { HomeLayout.oneCol(textSize) }
  /* the window (points) and its safe area's top and foot: whether the home is on its side, and homeCards' foot */
  @State private var win = HomeLayout.window()?.bounds.size ?? .zero
  @State private var winTop: CGFloat = 0
  @State private var winFoot: CGFloat = 0
  @State private var safeL: CGFloat = 0
  @State private var safeR: CGFloat = 0
  private var side: Bool { HomeLayout.side(win) }
  /* --card-ar: every card's shape, wider than 1.7 only on its side where the screen is short (homeCards) */
  @State private var cardAr: CGFloat = 1.7
  @State private var gridW: CGFloat = 0
  @State private var stripY: CGFloat = 0
  /* the solo list's height: the modes' two rows share the rest of the height beside it (a grid's stretched auto rows) */
  @State private var soloH: CGFloat = 0
  private func readWin() {
    guard let w = HomeLayout.window() else { return }
    if win != w.bounds.size { win = w.bounds.size }
    if winTop != w.safeAreaInsets.top { winTop = w.safeAreaInsets.top }
    if winFoot != w.safeAreaInsets.bottom { winFoot = w.safeAreaInsets.bottom }
    if safeL != w.safeAreaInsets.left { safeL = w.safeAreaInsets.left }
    if safeR != w.safeAreaInsets.right { safeR = w.safeAreaInsets.right }
    homeCards()
  }
  /* homeCards(): on its side, where the cards at 1.7 would run the ninth's strip past the home indicator, every card,
     games and modes, takes one wider shape just short enough (half a point spare), never under --tile-min (62); the
     default text size only (Large and Larger scroll). From the layout as it stands: the strip's foot at 1.7 is its foot
     now plus the two rows' growth back to 1.7 */
  private func homeCards() {
    var ar: CGFloat = 1.7
    if side, textSize == 100, gridW > 0, stripY > 0 {
      let tw = (gridW - 30) / 4, h0 = tw / 1.7, bottom = winTop + stripY + 2 * (h0 - tw / cardAr), foot = win.height - winFoot
      if bottom > foot { ar = (tw / max(62, h0 - (bottom - foot + 0.5) / 2) * 1000).rounded(.up) / 1000 }
    }
    if abs(ar - cardAr) > 0.0005 { cardAr = ar }
  }
  struct PartyGo: Identifiable { let game: TableGame, names: [String], ruleset: String; var id: String { ruleset + names.joined() } }
  struct Exhibit: Identifiable { let game: TableGame, levels: [String]; var archs: [String] = ["allround", "allround"]; var id: String { game.rawValue + levels.joined() + archs.joined() } }
  var body: some View {
    NavigationStack {
      ScrollViewReader { sv in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          /* .brand: the wordmark, where the opening (6o) glides home, and three round glass buttons (.nav) */
          HStack(spacing: 12) {
            Wordmark().opacity(intro.state == .done ? 1 : 0)
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in
                titleRect = r
                if intro.state == .off, r.width > 0, let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
                  let i = w.safeAreaInsets
                  intro.boot(size: w.bounds.size, title: r, insets: EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right), scale: w.screen.scale)
                }
              }
              .accessibilityAddTraits(.isHeader).accessibilityLabel("felt")
            Spacer(minLength: 0)
            HStack(spacing: 10) {
              NavigationLink { StatsView() } label: { NavDot(icon: "chart.bar") }.accessibilityLabel("Stats").accessibilityIdentifier("stats")
              NavigationLink { SettingsView() } label: { NavDot(icon: "slider.horizontal.3") }.accessibilityLabel("Settings").accessibilityIdentifier("settings")
              NavigationLink { HelpView(acts: helpActs) } label: { NavDot(icon: "questionmark.circle") }.accessibilityLabel("How to Play").accessibilityIdentifier("help")
            }
            .buttonStyle(Press())
          }
          .frame(minHeight: 44).homeProbe("brand")
          HomeSect(title: "Games", top: side ? 12 : 18, side: side).homeProbe("labGames")
          /* #playRow: the nine games as cards with their rack art, two to a row, the ninth a row wide */
          /* text size Large on a phone 400 pt wide or less, Larger on one 500 pt or less, upright: one card to a row */
          /* on its side (landscape, 560 pt wide or more): four to a row, 10 apart, the ninth a 48 pt strip under them */
          let cols = side ? Array(repeating: GridItem(.flexible(), spacing: 10), count: 4) : oneCol ? [GridItem(.flexible(), spacing: 12)] : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
          LazyVGrid(columns: cols, spacing: side ? 10 : 12) {
            ForEach(HomeArt.ORDER.filter { $0 != .heyball }) { g in gameCard(g) }
          }
          .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridW = $0; homeCards() }
          gameCard(.heyball).padding(.top, side ? 10 : 12)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("homeC")).maxY } action: { stripY = $0; homeCards() }
          if side {
            /* the modes beside the solo list, 16 apart */
            HStack(alignment: .top, spacing: 16) {
              VStack(alignment: .leading, spacing: 0) {
                HomeSect(title: "Modes", top: 20, side: true).homeProbe("labModes")
                modesGrid(cols: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], gap: 10, rowMin: max(0, (soloH - 10) / 2))
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              VStack(alignment: .leading, spacing: 0) {
                HomeSect(title: "Solo", top: 20, side: true).homeProbe("labSolo")
                soloSection(true).id("homeEnd").homeProbe("solos")
                  .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { soloH = $0 }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          } else {
            HomeSect(title: "Modes", top: 26).homeProbe("labModes")
            modesGrid(cols: cols, gap: 12, rowMin: 0)
            HomeSect(title: "Solo", top: 26).homeProbe("labSolo")
            soloSection(false).id("homeEnd").homeProbe("solos")
          }
        }
        /* on its side: --gut 24 (or the safe area's inset, which the scroll view already gives), the header 22 under the
           top, at most 1100 wide */
        /* upright the gutter is #menu's 20, outside the Larger Text zoom (the page zooms .sheet.home inside it): 20 / z here */
        .padding(.horizontal, side ? 0 : 20 * 100 / CGFloat(textSize)).padding(.top, side ? 22 : 0).padding(.bottom, 24)
        .coordinateSpace(.named("homeC"))
        .frame(maxWidth: side ? 1100 : 560)
        .padding(.leading, side ? max(0, 24 - safeL) : 0).padding(.trailing, side ? max(0, 24 - safeR) : 0)
        .frame(maxWidth: .infinity)
      }
      .background(Color(rgb: 0x09, 0x09, 0x0a))
      .scrollIndicators(.hidden)
      .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in readWin() }
      /* `-felt-homeend`: the home scrolled to its end (a test hook) */
      .task { if ProcessInfo.processInfo.arguments.contains("-felt-homeend") { try? await Task.sleep(for: .milliseconds(300)); sv.scrollTo("homeEnd", anchor: .bottom) } }
      }
      .toolbar(.hidden, for: .navigationBar)
      .navigationTitle("").navigationBarTitleDisplayMode(.inline)
      .navigationDestination(isPresented: $showCareer) { CareerView(store: career).modifier(modeBack("mode-career") { showCareer = false }) }
      .navigationDestination(isPresented: $prefsOpen) { SettingsView() }
      .navigationDestination(item: $modePath) { m in
        if m == "ex" { ExhibitionSetup { exhibit = $0 }.modifier(modeBack("mode-exhibit") { modePath = nil }) }
        else if m == "party" { PartySetup { party = $0 }.modifier(modeBack("mode-party") { modePath = nil }) }
        else { TourneyView(store: store) { store.markLive(); playingTourney = true }.modifier(modeBack("mode-tourney") { modePath = nil }) }
      }
      .navigationDestination(item: $helpPath) { p in
        if p == "drills" { DrillsList { drilling = PracticeGo(layout: $0) } }
        else if p.hasPrefix("topic:"), let t = HelpTopic.all.first(where: { $0.id == String(p.dropFirst(6)) }) { HelpPage(t: t, acts: helpActs) }
        else { HelpView(acts: helpActs) }
      }
      .navigationDestination(item: $statsPath) { k in if k == "all" { StatsView() } else { StatsKindPage(kind: k, rec: Rec.load()) } }
      .navigationDestination(item: $setupGame) { g in
        let back = { mo.close("game-\(g.rawValue)", face(g)) { setupGame = nil } }
        GameSetup(game: g, go: { playing = g }, learn: { tutoring = PracticeGo(layout: $0) }, back: back)
          .modifier(MorphBack(bar: false, back: back))
      }
      .navigationDestination(isPresented: $showTourney) { TourneyView(store: store) { store.markLive(); playingTourney = true } }
      .tint(.primary)
    }
    .environment(mo)
    /* Text Size: Large and Larger zoom everything but the table (a cover of its own, outside this transform) */
    .modifier(Zoomed(z: CGFloat(textSize) / 100))
    .overlay { MorphLayer(mo: mo) }
    /* a test hook, like the page's window.felt: `-felt-game "9-Ball"` opens that table */
    .onAppear {
      let a = ProcessInfo.processInfo.arguments
      if let i = a.firstIndex(of: "-felt-game"), i + 1 < a.count { playing = TableGame(rawValue: a[i + 1]) }
      /* `-felt-tourney`: the golden's first tournament (9-ball, 8 players, seed 11), its screen open */
      /* `-felt-setup "8-Ball"`: that game's setup open */
      if let i = a.firstIndex(of: "-felt-setup"), i + 1 < a.count { setupGame = TableGame(rawValue: a[i + 1]) }
      /* `-felt-stats [kind]`: Stats open, or a game's page */
      if let i = a.firstIndex(of: "-felt-stats") { statsPath = i + 1 < a.count && !a[i + 1].hasPrefix("-") ? a[i + 1] : "all" }
      /* `-felt-practice 8|9|heyball|scatter|empty`: a practice session */
      if let i = a.firstIndex(of: "-felt-practice"), i + 1 < a.count { practicing = PracticeGo(layout: a[i + 1]) }
      /* `-felt-help [topic]`: How to play, or a topic's page */
      if let i = a.firstIndex(of: "-felt-help") { helpPath = i + 1 < a.count && !a[i + 1].hasPrefix("-") ? "topic:" + a[i + 1] : "help" }
      /* `-felt-prefs`: Settings open */
      if a.contains("-felt-prefs") { prefsOpen = true }
      if let i = a.firstIndex(of: "-felt-mode"), i + 1 < a.count { modePath = a[i + 1] }
      /* `-felt-lesson`: the lesson */
      if a.contains("-felt-lesson") { lessoning = true }


      /* `-felt-tutorial id`: that tutorial (`-felt-tutshow` plays each step's Show me) */
      if let i = a.firstIndex(of: "-felt-tutorial"), i + 1 < a.count { tutoring = PracticeGo(layout: a[i + 1]) }
      /* `-felt-drill id`: that drill (`-felt-drillshots` plays its solutions) */
      if let i = a.firstIndex(of: "-felt-drill"), i + 1 < a.count { drilling = PracticeGo(layout: a[i + 1]) }
      /* `-felt-trick id`: that trick shot (`-felt-elev` opens the elevation sheet) */
      if let i = a.firstIndex(of: "-felt-trick"), i + 1 < a.count { tricking = PracticeGo(layout: a[i + 1]) }
      /* `-felt-career`: the career's screen open */
      if a.contains("-felt-career") { showCareer = true }
      if a.contains("-felt-tourney") { store.start(Tourney.make(kind: "9", ruleset: nil, size: 8, fmt: "single", race: 3, field: "mixed", seed: 11)); showTourney = true }
      /* `-felt-tourney-done won|lost`: a 4-player tournament played out (each of my matches won 3-0, or the first lost 0-3) */
      if let i = a.firstIndex(of: "-felt-tourney-done"), i + 1 < a.count {
        store.start(Tourney.make(kind: "9", ruleset: nil, size: 4, fmt: "single", race: 3, field: "mixed", seed: 11))
        var guardN = 0
        while let t = store.tour, !t.done, let m = t.mine(), guardN < 8 { store.report(m, a[i + 1] == "won" ? 3 : 0, a[i + 1] == "won" ? 0 : 3, false); guardN += 1 }
        showTourney = true
      }
      if let i = a.firstIndex(of: "-felt-party"), i + 1 < a.count, let n = Int(a[i + 1]) { party = PartyGo(game: .nine, names: (1...n).map { "Player \($0)" }, ruleset: "9-ring") }
      if let i = a.firstIndex(of: "-felt-exhibit"), i + 1 < a.count, let g = TableGame(rawValue: a[i + 1]) { exhibit = Exhibit(game: g, levels: ["medium", "hard"]) }
      /* `-felt-landscape left|right`: the interface turned on its side (the simulator cannot be turned from a script) */
      if let i = a.firstIndex(of: "-felt-landscape"), i + 1 < a.count,
         let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: a[i + 1] == "left" ? .landscapeLeft : .landscapeRight))
      }
    }
    .overlay { if intro.state != .done { IntroOverlay(model: intro, title: titleRect) } }
    .onChange(of: playing) { _, g in if let g { Prefs.last = g.table.2 } }
    .overlay(alignment: .bottom) {
      if leftNote {
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Counted as a Loss").font(.headline)
            Text("Your last game against the CPU was left unfinished and counted as a loss.").font(.subheadline).foregroundStyle(.secondary)
          }
          Spacer(minLength: 8)
          Button("OK") { leftNote = false }.font(.headline).foregroundStyle(.primary).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("leftOk")
        }
        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 16).padding(.bottom, 12)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
        .task { try? await Task.sleep(for: .seconds(12)); leftNote = false }
      }
    }
    .task {
      guard HomeLayout.probeOn else { return }
      try? await Task.sleep(for: .seconds(8))
      let w = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
      let f = { (r: CGRect) in [r.minX, r.minY, r.width, r.height].map { String(format: "%.1f", $0) }.joined(separator: ",") }
      var out = ["window \(f(w?.bounds ?? .zero)) insets \(w.map { "\($0.safeAreaInsets)" } ?? "")"]
      for (k, r) in HomeLayout.probe.sorted(by: { $0.key < $1.key }) { out.append("\(k) \(f(r))") }
      for (k, c) in mo.cards.sorted(by: { $0.key < $1.key }) { out.append("\(k) \(f(c.rect)) title \(f(c.title)) line \(f(c.line))") }
      try? out.joined(separator: "\n").write(to: FileManager.default.temporaryDirectory.appending(path: "homelayout.txt"), atomically: true, encoding: .utf8)
    }
    .task {
      guard !booted else { return }
      booted = true
      if Rec.abandonedAtBoot() { leftNote = true }
    }
    .fullScreenCover(item: $playing) { g in TableScreen(model: TableModel(game: g, cpu: opponent == "two" ? nil : opponent)) }
    .fullScreenCover(item: $exhibit) { e in TableScreen(model: TableModel(game: e.game, exhib: e.levels, exhibArch: e.archs)) }
    .fullScreenCover(isPresented: $playingTourney) {
      if let t = store.tour, let g = TourneyView.game(t.kind) {
        TableScreen(model: { let m = TableModel(game: g, tourney: t); m.onReport = { store.report($0, $1, $2, $3) }; return m }())
      }
    }
    .fullScreenCover(isPresented: $lessoning) { TableScreen(model: TableModel(game: .eight, lesson: true)) }
    /* #lessonOffer: New to felt? on the first run, once the opening is over */
    .sheet(isPresented: $lessonOffer) {
      VStack(spacing: 14) {
        BallDot(n: 1).frame(width: 44, height: 44)
        Text("New to felt?").font(.title2.bold())
        Text("A 30 second lesson: aim, fine-tune, shoot. Three steps, no rules to learn.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        HStack(spacing: 10) {
          Button { lessonOffer = false; lessoning = true } label: { Text("Show Me").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("offerGo")
          Button { var r = LessonStore.rec; r.seen = true; LessonStore.rec = r; lessonOffer = false } label: { Text("Skip").frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(Color(white: 0.2))).foregroundStyle(.white).accessibilityIdentifier("offerSkip")
        }
      }
      .padding(24).presentationDetents([.height(300)])
    }
    .onChange(of: intro.state) { _, s in maybeOfferLesson(s) }
    .fullScreenCover(item: $tutoring) { t in TableScreen(model: TableModel(game: ["9": .nine, "bumper": .bumper, "carom": .carom, "snooker": .snooker, "heyball": .heyball][t.layout] ?? .eight, tutorial: t.layout)) }
    .fullScreenCover(item: $drilling) { d in TableScreen(model: TableModel(game: .nine, drill: d.layout)) }
    .fullScreenCover(item: $tricking) { t in TableScreen(model: TableModel(game: .eight, trick: t.layout)) }
    .fullScreenCover(item: $practicing) { p in TableScreen(model: TableModel(game: p.layout == "9" ? .nine : p.layout == "heyball" ? .heyball : .eight, practice: p.layout)) }
    .fullScreenCover(item: $party) { p in TableScreen(model: TableModel(game: p.game, party: (p.names, p.ruleset))) }
  }
}

struct TableScreen: View {
  @State var model: TableModel
  @Environment(\.dismiss) private var dismiss
  @State private var aimDrag: Double?
  /* the drag's working state: a plain object, not observed, so a touch event (120 a second) never rebuilds the screen */
  final class Touch { var placing = false, picking = false, eating = false, gest: AimGesture? = nil, pinch0: Double? = nil }
  @State private var tch = Touch()
  /* Table View changed in Settings mid-game (the pause menu's): applied at once, as the page's applyPrefs/v3Sync */
  @AppStorage("felt.settings.view") private var tableView = "top"
  /* a hardware keyboard (page 5's keydown): the table takes the keys while it is up */
  @FocusState private var keys: Bool
  @Environment(\.displayScale) private var scale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /* the window's interface orientation, read as the size changes (a turn) */
  private var interface: UIInterfaceOrientation { (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.effectiveGeometry.interfaceOrientation ?? .portrait }

  var body: some View {
    let _ = Bench.hit("TableScreen")
    GeometryReader { geo in
      let ins = geo.safeAreaInsets, W = geo.size.width + ins.leading + ins.trailing, H = geo.size.height + ins.top + ins.bottom
      /* sideRot (6b): a phone on its side (under 600 pt tall) shows the upright layout turned a quarter, so the table
         keeps the same footprint either way. The column stands on the side away from the island (the larger side
         inset): anticlockwise with the island on the left (the strip's foot to the right), clockwise with it on the
         right. The upright insets are modelled from the side ones: the island's inset is the upright top, the foot
         HOME_UP (34 pt) with a home indicator, else 4. A tablet or desktop on its side keeps the column. */
      let side = W > H && H < 600
      /* islandSide(): unequal insets, the larger; equal (as iOS gives them), the interface's orientation: landscape
         right has the island on the left (anticlockwise, the column right), landscape left on the right */
      let ccw = side && (ins.leading != ins.trailing ? ins.leading > ins.trailing : interface != .landscapeLeft)
      ZStack(alignment: .topLeading) {
        if side {
          /* upright a phone has no side insets: the sides' padding is the upright one's (2 pt) */
          let up = EdgeInsets(top: max(ins.leading, ins.trailing), leading: 0, bottom: ins.bottom > 0 ? 34 : 4, trailing: 0)
          screen(W: H, H: W, ins: up, upright: true)
            .frame(width: H, height: W)
            .rotationEffect(.degrees(ccw ? -90 : 90))
            .frame(width: W, height: H)
        } else {
          screen(W: W, H: H, ins: ins, upright: H > W)
            .frame(width: W, height: H)
        }
        /* the elevation sheet and its tip, placed in the window by the pad's frame (the call's menu is over everything:
           the last overlay) */
        PopLayer(model: model, W: W, H: H, turn: side ? (ccw ? -1 : 1) : 0, call: false)
      }
      .offset(x: -ins.leading, y: -ins.top)
    }
    .background(Color(rgb: 9, 9, 10).ignoresSafeArea())
    .onAppear { model.reduceMotion = reduceMotion || Prefs.reduceMotion }
    .onChange(of: reduceMotion) { _, v in model.reduceMotion = v || Prefs.reduceMotion }
    .overlay(alignment: .topTrailing) { if model.prac != nil && !model.paused { PracticeTools(model: model).padding(.top, 8).padding(.trailing, 12) } }
    .onChange(of: model.spinOk) { _, ok in if !ok { model.elevOpen = false; model.hideElevTip() } }
    .onChange(of: model.paused) { _, p in if p { model.hideElevTip(); model.callMenu = false } }
    .onChange(of: tableView) { _, v in model.syncView(v == "3d") }
    .overlay { Overlays(model: model, back: { model.abandonCpuGame(); dismiss() }) }
    .overlay(alignment: .top) { CalloutView(model: model).padding(.top, 0) }
    .overlay(alignment: .bottom) { ReplayPill(model: model).padding(.bottom, 92) }
    .overlay { if let r = model.trickRes, !model.paused { TrickResult(model: model, res: r, back: { dismiss() }) } }
    .overlay { if let r = model.drillRes, !model.paused { DrillResultView(model: model, res: r, back: { dismiss() }) } }
    .overlay(alignment: model.coachAtTop ? .top : .bottom) { if model.tut != nil, !model.tutDone, !model.paused { CoachCard(model: model).pageCap(320).padding(.horizontal, 12).padding(.vertical, model.coachAtTop ? 8 : 96) } }
    .overlay(alignment: model.coachAtTop ? .top : .bottom) { if let L = model.lesson, !model.lessonDone, !model.paused { LessonCard(s: L).pageCap(320).padding(.horizontal, 12).padding(.vertical, model.coachAtTop ? 8 : 96) } }
    .overlay { if model.lessonDone, !model.paused { LessonDoneView(home: { dismiss() }) } }
    .overlay { if model.tutDone, let t = tutById(model.tut!.id), !model.paused { TutDoneView(t: t, home: { dismiss() }) } }
    .onDisappear { model.abandonCpuGame(); Chrome.shared.atTable -= 1 }
    .onAppear {
      Chrome.shared.atTable += 1
      Task { try? await Task.sleep(for: .milliseconds(300)); Chrome.refresh() }
      /* `-felt-edges`: what UIKit is told about the screen edges, a second after the table opens */
      if ProcessInfo.processInfo.arguments.contains("-felt-edges") { Task { try? await Task.sleep(for: .seconds(1)); Chrome.printEdges() } }
    }
    .overlay { if let h = model.handoff, !model.paused { Handoff(model: model, p: h.p, first: h.first) } }
    /* the exhibition's bar: the speed (felt.speed), over the table's top */
    .overlay(alignment: .top) {
      if model.exhib != nil && !model.paused {
        Picker("Speed", selection: Binding(get: { model.speed }, set: { model.speed = $0 })) { Text("1x").tag(1.0); Text("2x").tag(2.0); Text("4x").tag(4.0) }
          .pickerStyle(.segmented).frame(width: 180).padding(.top, 54).accessibilityIdentifier("exhibit-speed")
      }
    }
    /* the call's menu (#callBar, a .seg.pop.open: z-index 60) over every other table overlay: the strip and the rail row,
       the tools, the coach card, the callout, the replay pill, the elevation sheet; placed in the window by the bar's frame */
    .overlay {
      GeometryReader { geo in
        let ins = geo.safeAreaInsets, W = geo.size.width + ins.leading + ins.trailing, H = geo.size.height + ins.top + ins.bottom
        let side = W > H && H < 600, ccw = side && (ins.leading != ins.trailing ? ins.leading > ins.trailing : interface != .landscapeLeft)
        PopLayer(model: model, W: W, H: H, turn: side ? (ccw ? -1 : 1) : 0, call: true)
          .offset(x: -ins.leading, y: -ins.top)
      }
    }
    .tint(.primary)
    .statusBarHidden()
    /* a swipe from an edge takes two at the table (the first only shows the home bar), as games do */
    .defersSystemGestures(on: Chrome.noDefer ? [] : .all)
    .focusable(!Chrome.noFocus).focusEffectDisabled().focused($keys)
    .onAppear { keys = true; PointerWatch.install(); PointerWatch.onSecondary = { [weak model] in model?.letGoAim() } }
    /* `-felt-keybench`: keys through model.key (10 right, 2 up, Space with keyShoot, then the result printed) */
    .task {
      guard ProcessInfo.processInfo.arguments.contains("-felt-keybench") else { return }
      try? await Task.sleep(for: .seconds(2))
      let a0 = model.aim, m0 = model.markPower
      for _ in 0..<10 { _ = model.key("right", shift: false, alt: false) }
      _ = model.key("right", shift: false, alt: true)
      for _ in 0..<2 { _ = model.key("up", shift: false, alt: false) }
      let a1 = model.aim, m1 = model.markPower
      UserDefaults.standard.set(false, forKey: "felt.settings.keyShoot"); _ = model.key("space", shift: false, alt: false)
      let off = model.keyMsg
      try? await Task.sleep(for: .milliseconds(300))
      UserDefaults.standard.set(true, forKey: "felt.settings.keyShoot"); _ = model.key("space", shift: false, alt: false)
      try? await Task.sleep(for: .milliseconds(1200))
      UserDefaults.standard.removeObject(forKey: "felt.settings.keyShoot")
      print(String(format: "felt-keybench aim %+.5f (expected %+.5f), mark %.2f -> %.2f, off: %@, rolling %d", a1 - a0, 10 * 0.004 + TableModel.FINE_STEP, m0, m1, off, model.rolling != nil ? 1 : 0))
    }
    .onKeyPress(phases: .down) { press in
      let k: String
      switch press.key {
      case .leftArrow: k = "left"
      case .rightArrow: k = "right"
      case .upArrow: k = "up"
      case .downArrow: k = "down"
      case .space: k = "space"
      case .return: k = "return"
      case .escape: k = "escape"
      default: k = press.characters.lowercased()
      }
      return model.key(k, shift: press.modifiers.contains(.shift), alt: press.modifiers.contains(.option) || press.modifiers.contains(.control)) ? .handled : .ignored
    }
    /* the keyboard's words (the page's status line): the drive, the mark, why Space does nothing */
    .overlay(alignment: .top) {
      if !model.keyMsg.isEmpty {
        Text(model.keyMsg).font(.system(size: 15)).padding(.horizontal, 14).padding(.vertical, 8)
          .background(.regularMaterial, in: Capsule()).padding(.top, 54).accessibilityAddTraits(.updatesFrequently)
          .task(id: model.keyMsg) { try? await Task.sleep(for: .seconds(4)); if !model.keyMsg.hasPrefix("The bar pulls") { model.keyMsg = "" } }
      }
    }
  }

  /* #ui: padding max(2, the insets), max(4) at the foot; upright the stage over one 56 pt strip (#ctl), 4 apart, the
     strip stood in from the sides by 0.35 of the foot's inset (the display's rounded corners); else a column */
  /* layout(): upright, the strip under the table or the side column where that is clearly bigger (a tablet: 1.04, a
     screen under 600 wide 1.12); in the column, --colx (the room beside a table bound by the height, up to 24 pt, given
     to the column) and --ctl-t/--ctl-b (the column flush with the table's footprint, top to bottom). Sizes as #ui's:
     the strip 56 tall, 4 apart, padding 2 (4 at the foot); a bigger screen (min-width 700, min-height 600) 60, 8 apart,
     padding 8; the column 64 wide, 8 from the stage, padding 8 */
  struct Fit { var strip: Bool, big: Bool, col = 64.0, t = 0.0, b = 0.0, k = 0.0, foot = CGRect.zero }
  private func fit(W: CGFloat, H: CGFloat, ins: EdgeInsets, upright: Bool) -> Fit {
    let big = W >= 700 && H >= 600, TL = model.sim.TL, TW = model.sim.TW
    let et = ins.top > 2 ? Double(ins.top) - 2 : 0
    func map(_ w: Double, _ h: Double, _ e: Mapper.Ext) -> Mapper { Mapper(size: CGSize(width: w + e.l, height: h + e.t), TL: TL, TW: TW, ext: e) }
    /* the footprint (the rail's outer edge, camRect) on the screen, the stage's safe corner at (x, y) */
    func foot(_ m: Mapper, _ x: Double, _ y: Double, _ e: Mapper.Ext) -> CGRect {
      let bw = m.upright ? TW : TL, bh = m.upright ? TL : TW
      return CGRect(x: x - e.l + m.ox - m.rail * m.k, y: y - e.t + m.oy - m.rail * m.k, width: (bw + 2 * m.rail) * m.k, height: (bh + 2 * m.rail) * m.k)
    }
    let ce = Mapper.Ext(t: et, l: ins.leading > 2 ? Double(ins.leading) - 2 : 0, r: 0)
    let cw = Double(W - max(8, ins.leading) - max(8, ins.trailing)) - 8 - 64, ch = Double(H - max(8, ins.top) - max(8, ins.bottom))
    var m = map(cw, ch, ce)
    if upright {
      let sp: CGFloat = big ? 8 : 2
      let sw = Double(W - max(sp, ins.leading) - max(sp, ins.trailing)), sh = Double(H - max(sp, ins.top) - max(big ? 8 : 4, ins.bottom)) - (big ? 68 : 60)
      let se = Mapper.Ext(t: et, l: 0, r: 0), s = map(sw, sh, se)
      if !(m.k > s.k * (W < 600 ? 1.12 : 1.04)) { return Fit(strip: true, big: big, k: s.k, foot: foot(s, Double(max(sp, ins.leading)), Double(max(sp, ins.top)), se)) }
    }
    var f = Fit(strip: false, big: big)
    let bx = m.upright ? TW : TL, lo = max(-ce.l, -m.rail * m.k), hi = min(cw - (bx + 2 * m.rail) * m.k, cw - (m.rail + bx) * m.k), spare = (hi - lo).rounded(.down)
    if spare >= 4 { f.col += min(24, spare); m = map(cw - min(24, spare), ch, ce) }
    let bh = m.upright ? TL : TW, ft = m.oy - m.rail * m.k - ce.t, fb = m.oy + (bh + m.rail) * m.k - ce.t
    f.t = max(0, ft.rounded()); f.b = max(0, (ch - fb).rounded())
    f.k = m.k; f.foot = foot(m, Double(max(8, ins.leading)), Double(max(8, ins.top)), ce)
    return f
  }
  /* `-felt-layout`: the fit printed once per size (a test hook: the table's footprint and the controls, against the page's) */
  nonisolated(unsafe) private static var layoutSig = ""
  private static func logFit(_ W: CGFloat, _ H: CGFloat, _ F: Fit) {
    guard ProcessInfo.processInfo.arguments.contains("-felt-layout") else { return }
    let r = F.foot, s = String(format: "felt-layout %.0fx%.0f %@ big %d k %.2f col %.0f ctl-t %.0f ctl-b %.0f foot %.1f %.1f %.1f %.1f", W, H, F.strip ? "strip" : "column", F.big ? 1 : 0, F.k, F.col, F.t, F.b, r.minX, r.minY, r.width, r.height)
    if s != layoutSig { layoutSig = s; print(s) }
  }
  @ViewBuilder private func screen(W: CGFloat, H: CGFloat, ins: EdgeInsets, upright: Bool) -> some View {
    let F = fit(W: W, H: H, ins: ins, upright: upright), strip = F.strip, pad: CGFloat = strip && !F.big ? 2 : 8
    let _ = Self.logFit(W, H, F)
    let layout = strip ? AnyLayout(VStackLayout(spacing: F.big ? 8 : 4)) : AnyLayout(HStackLayout(spacing: 8))
    /* tableExt: the rails may run under the top inset (the status bar or the island) and, beside a column, the leading
       one (the controls' column is trailing), 2 pt short of each; the stage's canvas reaches into them */
    let ext = Mapper.Ext(t: ins.top > 2 ? Double(ins.top) - 2 : 0, l: !strip && ins.leading > 2 ? Double(ins.leading) - 2 : 0, r: 0)
    let _ = { if Mapper.current != ext { Mapper.current = ext } }()
    layout {
      GeometryReader { tg in
        LinkTimeline(paused: model.paused) { tl in
          Group {
            if model.v3Live {
              /* the rail row pinned to the stage's foot (V3_PIN_B 26 up), off the projected pockets and sights */
              Table3DView(model: model).overlay {
                Canvas { ctx, size in
                  _ = tl.date
                  guard let (C, box) = model.v3Cam else { return }
                  let tc = TableCanvas(model: model, look: Look.of(model.dress, game: model.game)), m = Mapper(size: size, TL: model.sim.TL, TW: model.sim.TW)
                  let bp = model.ballPainter(upright: m.upright, scale: scale)
                  /* 6b3 in 3D: the potted windows on the long rails as projected, never on the row (railTop: 22 over its middle) */
                  tc.drawPotRail(&ctx, m, bp, live: (C, box, Double(size.height) - 26 - 22))
                  tc.drawRail(&ctx, m, bp, row: (Double(size.height) - 26, Double(size.width), C, box))
                }
                .allowsHitTesting(false)
              }
            } else { TableCanvas(model: model, look: Look.of(model.dress, game: model.game)) }
          }
            .onChange(of: tl.date) { _, d in model.tick(d.timeIntervalSinceReferenceDate) }
        }
        .overlay { FlashBanner(model: model, size: tg.size) }
        .onAppear { model.bake(tg.size, scale: scale) }
        .onChange(of: tg.size) { _, s in model.bake(s, scale: scale) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TableScreen.UI)) } action: { model.stageUI = $0 }
        .contentShape(Rectangle())
        /* v3Pinch: two fingers move the 3D camera in or out (its distance by their spread, kept). A UIKit pinch beside the
           drag, never delaying it: SwiftUI's MagnifyGesture waiting to begin held back every event of the table's drag to
           the lift (measured on POSEIDON, -felt-touchlog) */
        .gesture(PinchRecognizer(on: model.view3d) { st, scale in
          switch st {
          /* a second finger kills the drag in progress and puts the aim and the tilt back to the press's (the page's g.a0,
             g.p0); the rest of the drag is eaten (mode 'dead') */
          case .began:
            if let g = tch.gest, !tch.placing, !tch.picking, model.rolling == nil { model.aim = g.a0; model.v3Pitch = g.pitch0 }
            tch.pinch0 = model.v3Dist; tch.gest = nil; tch.eating = true
          case .changed: if let p0 = tch.pinch0 { model.v3Dist = min(V3.DIST[1], max(V3.DIST[0], p0 / Double(scale))); TouchLog.add(String(format: "pinch dist %.3f", model.v3Dist)) }
          default: tch.pinch0 = nil; UserDefaults.standard.set(model.v3Dist, forKey: "felt.settings.viewDist"); UserDefaults.standard.set(model.v3Pitch, forKey: "felt.settings.viewPitch"); TouchLog.flush()
          }
        })
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in TouchLog.add(String(format: "ev %.4f %.1f %.1f", v.time.timeIntervalSinceReferenceDate, v.location.x, v.location.y)); model.touching = true; if tch.pinch0 == nil { touch(v.location, v.time.timeIntervalSinceReferenceDate, tg.size, began: tch.gest == nil && !tch.eating && !tch.picking && !tch.placing) } }
          .onEnded { v in lift(v.location, v.time.timeIntervalSinceReferenceDate, tg.size) })
        /* a pointer (an iPad's mouse or trackpad) aims by hovering the bed (the model's hover); not a gesture, so it
           never holds the drag back */
        .overlay(alignment: .topLeading) {
          if TableModel.aimProbe {
            let _ = model.frame
            Text("probe").font(.system(size: 1)).opacity(0.02).allowsHitTesting(false)
              .accessibilityIdentifier("aim-probe").accessibilityValue(String(format: "%@ %.4f", model.aimHeld ? "held" : "free", model.aim))
            Text("probe").font(.system(size: 1)).opacity(0.02).allowsHitTesting(false)
              .accessibilityIdentifier("cpu-probe").accessibilityValue(model.lastThink)
          }
        }
        .onContinuousHover { phase in
          switch phase {
          case .active(let p): model.hover(p, CACurrentMediaTime() * 1000, Mapper(size: tg.size, TL: model.sim.TL, TW: model.sim.TW))
          case .ended: model.leaveBed()
          }
        }
        /* a test hook: `-felt-touchbench` sweeps a synthetic finger through touch() at 120 Hz (a press, an arc, a lift, every 2 s) */
        .task(id: tg.size) { if TableModel.touchBench { await touchBench(tg.size) }; if TableModel.pointerBench { await pointerBench(tg.size) } }
        .accessibilityElement()
        .accessibilityLabel("Table")
        .accessibilityIdentifier("table")
      }
      .padding(.top, -ext.t).padding(.leading, -ext.l)
      Controls(model: model, upright: strip, big: F.big, col: F.col)
        .frame(width: strip ? nil : F.col, height: strip ? (F.big ? 60 : 56) : nil)
        .padding(.horizontal, strip ? ins.bottom * 0.35 : 0)
        .padding(.top, F.t).padding(.bottom, F.b)
    }
    .padding(.top, max(pad, ins.top)).padding(.bottom, max(strip && !F.big ? 4 : 8, ins.bottom))
    .padding(.leading, max(pad, ins.leading)).padding(.trailing, max(pad, ins.trailing))
    .frame(width: W, height: H)
    .coordinateSpace(.named(TableScreen.UI))
  }
  static let UI = "feltUI"

  private func lift(_ at: CGPoint, _ time: TimeInterval, _ size: CGSize) {
    let tt0 = CACurrentMediaTime()
    defer { if TableModel.touchBench { let d = (CACurrentMediaTime() - tt0) * 1000; if d > 8 { print(String(format: "felt-bench slow lift %.1f ms", d)) } } }
    TouchLog.add("lift"); defer { TouchLog.flush() }
    if tch.eating { tch.eating = false } else { touchEnd(at, time, size) }
    tch.placing = false; tch.picking = false; tch.gest = nil; model.touching = false; model.placeEnd()
  }
  private func touchBench(_ size: CGSize) async {
    /* `-felt-touchbench-slow`: a press, 14 pt in 100 ms (still a possible tap), then still: the aim printed at 50, 250,
       320 and 600 ms (the wait's catch-up is due at TAP_MS) */
    if ProcessInfo.processInfo.arguments.contains("-felt-touchbench-slow") {
      try? await Task.sleep(for: .seconds(2))
      let t0 = Date.timeIntervalSinceReferenceDate, p0 = CGPoint(x: size.width * 0.3, y: size.height * 0.3)
      for k in 0...12 { touch(CGPoint(x: p0.x + 14 * CGFloat(k) / 12, y: p0.y), t0 + Double(k) / 120, size, began: k == 0); try? await Task.sleep(for: .milliseconds(8)) }
      var out: [String] = []
      for ms in [50, 250, 320, 600] {
        let wait = ms - Int((Date.timeIntervalSinceReferenceDate - t0) * 1000)
        if wait > 0 { try? await Task.sleep(for: .milliseconds(wait)) }
        out.append(String(format: "%d ms %.5f", ms, model.aim))
      }
      print("felt-touchbench-slow " + out.joined(separator: ", "))
      return
    }
    while !Task.isCancelled {
      let t0 = Date.timeIntervalSinceReferenceDate
      /* `-felt-touchbench-hand`: the press on the cue ball (in hand on the break), carried round a small circle */
      let hand = ProcessInfo.processInfo.arguments.contains("-felt-touchbench-hand")
      let m = Mapper(size: size, TL: model.sim.TL, TW: model.sim.TW), cp = model.cue.map { m.pt($0.x, $0.y) } ?? .zero
      let cx = hand ? cp.x : size.width / 2, cy = hand ? cp.y : size.height * 0.7, rx: CGFloat = hand ? 30 : 120, ry: CGFloat = hand ? 30 : 60
      var k = 0
      while k < 200 && !Task.isCancelled {
        let u = Double(k) / 200, p = CGPoint(x: cx + rx * (cos(u * 2 * .pi) - (hand ? 1 : 0)), y: cy + ry * sin(u * 2 * .pi))
        model.touching = true
        touch(p, t0 + Double(k) / 120, size, began: k == 0)
        k += 1
        try? await Task.sleep(for: .milliseconds(8))
      }
      lift(CGPoint(x: cx + rx * (hand ? 0 : 1), y: cy), t0 + 200 / 120, size)
      try? await Task.sleep(for: .milliseconds(300))
    }
  }
  /* `-felt-pointerbench`: a pointer through the model's hover and the table's own touch path (as PointerWatch marks a
     press): hover aims, a click holds, hovers leave it, Esc lets go, a right click lets go, a sweep let go holds, a
     finger's tap never holds; the first hover's tip. Prints each failure, then ok or the count */
  private func pointerBench(_ size: CGSize) async {
    try? await Task.sleep(for: .seconds(2))
    let m = Mapper(size: size, TL: model.sim.TL, TW: model.sim.TW)
    var fails: [String] = []
    func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: size.width * u, y: size.height * v) }
    func hover(_ u: CGFloat, _ v: CGFloat) async { model.hover(pt(u, v), CACurrentMediaTime() * 1000, m); try? await Task.sleep(for: .milliseconds(200)) }
    func press(_ from: CGPoint, _ to: CGPoint, pointer: Bool, secondary: Bool = false) async {
      PointerWatch.pointer = pointer; PointerWatch.secondary = secondary
      let t0 = Date.timeIntervalSinceReferenceDate, n = from == to ? 1 : 12
      for k in 0..<n {
        let u = CGFloat(k) / CGFloat(max(1, n - 1)), p = CGPoint(x: from.x + (to.x - from.x) * u, y: from.y + (to.y - from.y) * u)
        model.touching = true; touch(p, t0 + Double(k) / 120, size, began: k == 0); try? await Task.sleep(for: .milliseconds(8))
      }
      lift(to, t0 + Double(n) / 120 + 0.02, size)
      try? await Task.sleep(for: .milliseconds(200))
    }
    func check(_ ok: Bool, _ what: String) { if !ok { fails.append(what) } }
    await hover(0.3, 0.2); let a1 = model.aim
    check(model.mouseTipShows == 1, "the first hover shows the tip")
    await hover(0.75, 0.25); let a2 = model.aim
    check(!model.aimHeld && abs(a2 - a1) > 0.05, "hover aims")
    await press(pt(0.6, 0.15), pt(0.6, 0.15), pointer: true); let a3 = model.aim
    check(model.aimHeld && abs(a3 - a2) > 0.01, "a click aims and holds")
    await hover(0.2, 0.3); await hover(0.8, 0.2)
    check(model.aimHeld && model.aim == a3, "no hover moves a held aim")
    _ = model.key("left", shift: false, alt: false)
    check(model.aimHeld && model.aim != a3, "an arrow adjusts a held aim and it stays held")
    _ = model.key("escape", shift: false, alt: false)
    check(!model.aimHeld && !model.paused, "Esc lets go before it pauses")
    await hover(0.35, 0.2)
    check(abs(model.aim - a3) > 0.01, "hover aims again")
    await press(pt(0.7, 0.2), pt(0.7, 0.2), pointer: true)
    check(model.aimHeld, "a second click holds")
    PointerWatch.onSecondary?()
    check(!model.aimHeld, "a right click lets go")
    await press(pt(0.7, 0.2), pt(0.7, 0.2), pointer: true); await press(pt(0.7, 0.2), pt(0.7, 0.2), pointer: true, secondary: true)
    check(!model.aimHeld, "a right press on the table lets go")
    await press(pt(0.3, 0.2), pt(0.7, 0.25), pointer: true)
    check(model.aimHeld, "a pointer sweep let go holds")
    await press(pt(0.6, 0.2), pt(0.6, 0.2), pointer: false)
    check(!model.aimHeld, "a finger's tap never holds")
    await press(pt(0.3, 0.2), pt(0.7, 0.25), pointer: false)
    check(!model.aimHeld, "a finger's sweep never holds")
    await hover(0.4, 0.2)
    check(model.mouseTipShows == 1, "the tip shows once")
    /* left held, for a look at drawHeld */
    await press(pt(0.62, 0.2), pt(0.62, 0.2), pointer: true)
    PointerWatch.pointer = false
    for f in fails { print("felt-pointerbench FAIL " + f) }
    print(fails.isEmpty ? "felt-pointerbench ok (14 checks)" : "felt-pointerbench \(fails.count) failed"); fflush(stdout)
  }
  private func touch(_ at: CGPoint, _ time: TimeInterval, _ size: CGSize, began: Bool) {
    let tt0 = CACurrentMediaTime()
    defer { if TableModel.touchBench { let d = (CACurrentMediaTime() - tt0) * 1000; if d > 8 { print(String(format: "felt-bench slow touch %.1f ms began %d", d, began ? 1 : 0)) } } }
    /* during a replay nothing reaches the game: the first touch ends it and the rest of it is eaten; an offer goes on a touch */
    if began, model.rp != nil { model.endReplay(); tch.eating = true; return }
    if tch.eating { return }
    /* the rail's 3D switch: a 44 pt target round its glyph; the tap is the switch's, the rest of it eaten */
    if began, let c = model.railSwitch, abs(at.x - c.x) < 22, abs(at.y - c.y) < 22 { model.toggleView(); tch.eating = true; return }
    /* F8: a press on the CPU's turn hurries its think (cpuSkip) and is eaten whole: it never aims, tilts or picks (the
       page's pointerdown returns while !human()) */
    if began, model.cpuSkip() { tch.eating = true; TouchLog.add("cpuskip"); return }
    if began { model.hideOffer() }
    let s = model.sim, m = model.camView(Mapper(size: size, TL: s.TL, TW: s.TW)), tm = TouchMap(model, m)
    model.uprightView = m.upright
    let (x, y) = tm.table(at)
    /* bumper pool: a touch on one of the shooter's own balls strikes that one from now on (pickBall) */
    if began, model.game == .bumper, let g = model.g {
      /* ballAt: the shooter's striker nearest the touch within max(22, 1.5 ball radii); the current one aims instead */
      let reach = max(22, 1.5 * s.BALL_R * tm.k)
      var best: Int? = nil, bd = reach
      for n in model.engine.bumperStrikers(g) {
        guard let b = g.balls.first(where: { $0.n == n && $0.on }) else { continue }
        let p = tm.pt(b.x, b.y), d = JSMath.hypot(Double(p.x - at.x), Double(p.y - at.y))
        if d < bd { bd = d; best = n }
      }
      if let n = best, n != model.cueN, model.pickBall(n) { tch.picking = true; return }
    }
    if tch.picking { return }
    /* a call open: a touch on a pocket calls it (pocketAt: 26 pt, 1.6 ball radii or 1.3 of the hole as drawn round its
       centre), on a ball calls that ball (objectAt, and still aims) */
    if began, model.callOn {
      var best = -1, bd = Double.infinity
      for (k, p) in s.POCKETS.enumerated() {
        let q = tm.pt(p[0], p[1]), r = k < s.POCKET_R.count ? s.POCKET_R[k] : s.BALL_R, ex = tm.pt(p[0] + r, p[1]), ey = tm.pt(p[0], p[1] + r)
        let hole = max(JSMath.hypot(Double(ex.x - q.x), Double(ex.y - q.y)), JSMath.hypot(Double(ey.x - q.x), Double(ey.y - q.y)))
        let d = JSMath.hypot(Double(q.x - at.x), Double(q.y - at.y))
        if d < max(26, 1.6 * s.BALL_R * tm.k, 1.3 * (hole < 1e4 ? hole : 0)) && d < bd { bd = d; best = k }
      }
      if best >= 0 { model.pickPocket(best); tch.picking = true; return }
      if let b = tm.objectAt(at) { model.pickCallBall(b.n) }
    }
    let t = time * 1000, b = at
    if began {
      tch.gest = AimGesture(t0: t, p0: b, last: b, tLast: t, at: b, trail: [(t, model.aim, Double(b.x), Double(b.y))], a0: model.aim, pitch0: model.v3Pitch)
      /* ball in hand: a press within grabR (30 pt or 2.5 ball radii) moves it, relative to where it was */
      if model.inHand, let c = model.cue {
        let q = tm.pt(c.x, c.y)
        if JSMath.hypot(Double(q.x - b.x), Double(q.y - b.y)) < max(30, 2.5 * s.BALL_R * tm.k) { tch.placing = true; tch.gest?.grab = (c.x - x, c.y - y); TouchLog.add("grab") }
      }
    }
    guard var g = tch.gest else { return }
    if tm.cam != nil && !tch.placing { drag3d(&g, b, t); tch.gest = g; TouchLog.add(String(format: "aim3d %.5f", model.aim)); return }
    g.far = max(g.far, JSMath.hypot(Double(b.x - g.p0.x), Double(b.y - g.p0.y)))
    if tch.placing, let o = g.grab {
      if !g.moving && g.far > AimFeel.GRAB_SLOP { g.moving = true }
      if g.moving { model.place(x + o.dx, y + o.dy); TouchLog.add(String(format: "place %.4f %.4f", x + o.dx, y + o.dy)) }
      tch.gest = g; return
    }
    guard model.rolling == nil, let c = model.cue else { tch.gest = g; return }
    let dv = JSMath.hypot(Double(b.x - g.last.x), Double(b.y - g.last.y))
    if dv > 0 { g.v = AimFeel.fingerSpeed(g.v, dv, t - g.tLast); g.last = b; g.tLast = t }
    /* the line moves with the finger from its first move (Zac, on device: no wait while a let-go could still be a tap;
       the page waits TAP_MS); a let-go that is a tap still aims at the spot (touchEnd) */
    if !g.sweep && g.far > 0 { g.sweep = true }
    if t - g.t0 >= AimFeel.HOLD_MS && g.far > AimFeel.HOLD_SLOP { g.held = true }
    if g.sweep { if !g.shown { model.takeAim() }; g.shown = true; turnTo(&g, b, t, m, c) }
    tch.gest = g
    TouchLog.add(String(format: "aim %.5f sweep %d", model.aim, g.sweep ? 1 : 0))
  }
  /* v3Drag: across turns the aim (rate by finger speed, 0.02 to 0.3 deg a point), up and down tilts (0.25 deg a point) */
  private func drag3d(_ g: inout AimGesture, _ b: CGPoint, _ t: Double) {
    g.far = max(g.far, JSMath.hypot(Double(b.x - g.p0.x), Double(b.y - g.p0.y)))
    let dv = JSMath.hypot(Double(b.x - g.last.x), Double(b.y - g.last.y))
    if dv > 0 { g.v = AimFeel.fingerSpeed(g.v, dv, t - g.tLast); g.last = b; g.tLast = t }
    if !g.sweep && !g.held {
      if g.far <= AimFeel.TAP_SLOP { return }
      if abs(b.x - g.p0.x) >= abs(b.y - g.p0.y) { g.sweep = true } else { g.held = true }
      g.shown = true
    }
    if g.sweep, model.rolling == nil {
      let slow = 0.02 * Double.pi / 180, fast = 0.3 * Double.pi / 180
      model.aim += Double(b.x - g.at.x) * (slow + (fast - slow) * AimFeel.smooth01(((g.v ?? 0) - AimFeel.V_SLOW) / (AimFeel.V_FAST - AimFeel.V_SLOW)))
      AimFeel.push(&g.trail, t, model.aim, b)
    } else if g.held {
      model.v3Pitch = min(V3.PITCH[1], max(V3.PITCH[0], model.v3Pitch + Double(b.y - g.at.y) * 0.25))
      UserDefaults.standard.set(model.v3Pitch, forKey: "felt.settings.viewPitch")
    }
    g.at = b
  }
  /* the sweep from where it was last applied to b */
  private func turnTo(_ g: inout AimGesture, _ b: CGPoint, _ t: Double, _ m: Mapper, _ c: Ball) {
    if b != g.at {
      let R = max(60, AimFeel.SWEEP_R * min(model.sim.TL, model.sim.TW) * m.k)
      model.aim = AimFeel.wrap(model.aim + AimFeel.sweepTurn(m.pt(c.x, c.y), g.at, b, R: R, ballPx: model.sim.BALL_R * m.k) * AimFeel.sweepGain(g.v ?? 0))
      g.at = b
    }
    AimFeel.push(&g.trail, t, model.aim, b)
  }
  /* the let-go: a tap aims at the spot (an object ball's centre within tapReach), a sweep may restore its lift jitter */
  private func touchEnd(_ at: CGPoint, _ time: TimeInterval, _ size: CGSize) {
    guard var g = tch.gest, !tch.placing, !tch.picking, model.rolling == nil, let c = model.cue else { return }
    let s = model.sim, m = model.camView(Mapper(size: size, TL: s.TL, TW: s.TW)), tm = TouchMap(model, m), t = time * 1000
    /* the press's kind, as the window's watcher saw it begin: a pointer's click holds the aim it sets, a right click only
       lets a held aim go; a finger or a pen never holds */
    let mouse = PointerWatch.pointer
    if mouse && PointerWatch.secondary { model.letGoAim(); return }
    /* in 3D (v3Drag) a let-go that neither swept nor tilted is a tap, read through the camera (v3Table) */
    if tm.cam != nil ? (!g.sweep && !g.held) : (!g.sweep || (!g.held && g.far <= AimFeel.TAP_SLOP && t - g.t0 < AimFeel.TAP_MS)) {
      let p = g.p0, (x, y) = tm.table(p)
      /* free table editing (5s): a tap drops or takes off a ball */
      if model.prac?.edit == true { model.editAt(x, y); return }
      let best = tm.objectAt(p)
      /* in 3D on the cue ball itself (2 ball radii, unless nearer an object ball) there is no direction to take */
      if tm.cam != nil {
        let q = tm.pt(c.x, c.y), dc = JSMath.hypot(Double(p.x - q.x), Double(p.y - q.y))
        let od = best.map { o -> Double in let w = tm.pt(o.x, o.y); return JSMath.hypot(Double(w.x - p.x), Double(w.y - p.y)) }
        if dc <= 2 * s.BALL_R * tm.k && !(od.map { $0 < dc } ?? false) { return }
      }
      /* with a call open, a held click on a ball calls it (touch()) and leaves the aim as it is */
      if best != nil && mouse && model.aimLock == .held && model.callOn { return }
      if let o = best { model.takeAim(); model.aim = atan2(o.y - c.y, o.x - c.x) }
      else if JSMath.hypot(x - c.x, y - c.y) > s.BALL_R { model.takeAim(); model.aim = atan2(y - c.y, x - c.x) }
      else { return }
      if mouse { model.holdAim() } else { model.aimLock = .free; model.keepAim() }
      return
    }
    /* in 3D a tilt is kept as it went (drag3d); a sweep restores its lift jitter as top-down (the trail is drag3d's) */
    if tm.cam != nil { if g.held { return } } else { turnTo(&g, at, t, m, c) }
    /* the finger lifting off is not aiming: put back the aim it rested on (a pointer's let-go is still) */
    if !mouse, let r = AimFeel.liftAim(g.trail, t) { model.aim = r }
    if mouse { model.hov?.x = at.x; model.hov?.y = at.y; model.holdAim() } else { model.lockAim() }
  }
}

/* the input's toScreen and toTable, and view.k: the 2D Mapper, or while the 3D view is live (V3.live) its camera at a
   ball centre's height (v3Screen, v3Table) with the scale at the cue ball (V3.k), so every table hit test and placement
   lands where the ball is drawn */
@MainActor struct TouchMap {
  let m: Mapper, cam: (C: V3.Cam, box: V3.Box)?, R: Double, k: Double, model: TableModel
  init(_ model: TableModel, _ m: Mapper) {
    self.model = model; self.m = m; R = model.sim.BALL_R
    cam = model.v3Live ? model.v3Cam.map { (C: $0.0, box: $0.1) } : nil
    k = cam != nil ? model.v3K : m.k
  }
  func pt(_ x: Double, _ y: Double) -> CGPoint {
    guard let (C, box) = cam else { return m.pt(x, y) }
    let p = V3.screen(C, box, x, y, R); return CGPoint(x: p[0], y: p[1])
  }
  func table(_ p: CGPoint) -> (Double, Double) {
    guard let (C, box) = cam else { return m.table(p) }
    let q = V3.table(C, box, Double(p.x), Double(p.y), R); return (q[0], q[1])
  }
  /* objectAt: the object ball nearest p within tapReach (14 pt or 1.3 ball radii) */
  func objectAt(_ p: CGPoint) -> Ball? {
    var best: Ball? = nil, bd = max(14, 1.3 * R * k)
    for o in model.balls where o.on && o.n != model.cueN {
      let q = pt(o.x, o.y), d = JSMath.hypot(Double(q.x - p.x), Double(q.y - p.y))
      if d < bd { bd = d; best = o }
    }
    return best
  }
}

/* the pop-ups by their controls, in the window: the call's menu (callMenuPlace) and the elevation sheet (openElev). The
   controls' frames come in the screen's own space (TableScreen.UI) and turn with it on a phone on its side (turn -1
   anticlockwise, the column right; 1 clockwise, the column left). A tap anywhere else closes either */
struct PopLayer: View {
  let model: TableModel
  let W: CGFloat, H: CGFloat, turn: Int
  /* which: the call's menu (drawn over every other overlay), or the elevation sheet and its tip */
  let call: Bool
  @State private var menuH: CGFloat = 0
  @State private var elevSize = CGSize.zero
  @State private var tipSize = CGSize.zero
  /* `-felt-poplayout` (or `-felt-poplog` alone, for the tip on a jump trick): each pop-up's frame printed by its control's */
  static let log = ProcessInfo.processInfo.arguments.contains { $0 == "-felt-poplayout" || $0 == "-felt-poplog" }
  /* the strip's frames (upright, or a phone on its side) or the column's */
  private var up: Int { turn != 0 || H > W ? 1 : 0 }
  var body: some View {
    ZStack(alignment: .topLeading) {
      if !call && model.elevOpen && model.spinOk && !model.paused {
        Color.black.opacity(0.001).onTapGesture { model.elevOpen = false }
        let at = padAt(elevSize)
        ElevPop(model: model).fixedSize()
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
            elevSize = f.size
            if Self.log { print("felt-poplayout elev \(Self.box(f)) pad \(Self.box(win(model.padUI[up]))) W \(W) H \(H)"); fflush(stdout) }
          }
          .opacity(elevSize == .zero ? 0 : 1)
          .padding(.leading, at.x).padding(.top, at.y)
      }
      /* #elevTip: by the pad as the elevation sheet stands, 12 from it (placeElevTip), once ever */
      if !call && model.elevTip && !model.elevOpen && !model.paused {
        let at = padAt(tipSize, gap: 12)
        ElevTip(model: model).frame(width: min(300, W - 32))
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
            tipSize = f.size
            if Self.log { print("felt-poplayout tip \(Self.box(f)) pad \(Self.box(win(model.padUI[up]))) W \(W) H \(H)"); fflush(stdout) }
          }
          .opacity(tipSize == .zero ? 0 : 1)
          .padding(.leading, at.x).padding(.top, at.y)
      }
      /* never over the pause menu or the handoff (the page's hudCall closes it when the turn is not the player's to aim) */
      if call && model.callMenu && model.callMenuOffered && !model.paused && model.handoff == nil {
        Color.black.opacity(0.001).onTapGesture { model.callMenu = false }
        let at = menuAt()
        CallMenu(model: model, maxH: H - 16, natural: $menuH)
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
            if Self.log { print("felt-poplayout menu \(Self.box(f)) bar \(Self.box(win(model.barUI[up]))) railTop \(railTop()) W \(W) H \(H)"); fflush(stdout) }
          }
          .opacity(menuH == 0 ? 0 : 1)
          .padding(.leading, at.x).padding(.top, at.y)
      }
    }
    .frame(width: W, height: H, alignment: .topLeading)
  }
  static func box(_ r: CGRect) -> String { String(format: "[%.1f,%.1f,%.1f,%.1f]", r.minX, r.minY, r.width, r.height) }
  /* a frame in the screen's own space as the window has it: turned a quarter about the window's centre (the screen
     H wide and W tall before it) */
  func win(_ r: CGRect) -> CGRect {
    guard turn != 0 else { return r }
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      let dx = x - H / 2, dy = y - W / 2
      return turn < 0 ? CGPoint(x: W / 2 + dy, y: H / 2 - dx) : CGPoint(x: W / 2 - dy, y: H / 2 + dx)
    }
    let a = p(r.minX, r.minY), b = p(r.maxX, r.maxY)
    return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
  }
  /* railTop (placeRail): 22 over the rail row's middle, in the screen's own space: top-down the bottom rail's wood band
     (never under 22 from the stage's foot), in 3D the row pinned 26 up; none when the row is not drawn */
  func railTop() -> CGFloat {
    let st = model.stageUI, s = model.sim
    guard let g = model.g, g.winner == nil, (model.party?.names.count ?? 2) <= 2, st.height > 0 else { return .infinity }
    if model.view3d && !model.v3Top2d { return st.minY + st.height - 26 - 22 }
    let m = Mapper(size: st.size, TL: s.TL, TW: s.TW), band = model.potGeometry(m).railBand, mid = -(band.co + band.rail) / 2
    let p = m.upright ? m.pt(mid, s.TW / 2) : m.pt(s.TL / 2, s.TW - mid)
    return st.minY + min(p.y, st.height - 22) - 22
  }
  /* callMenuPlace: upright over the bar, its trailing edge on the bar's (under it when there is no room over); on its
     side beside the column, level with the bar; clear of the rail row; inside the window by 8, and a menu taller than
     the window less 16 scrolls */
  func menuAt() -> CGPoint {
    let r = win(model.barUI[up]), m: CGFloat = 8, gap: CGFloat = 8, w = CallMenu.W, h = menuH, side = r.height > r.width
    var x: CGFloat, y: CGFloat
    if side { x = r.minX - gap - w; if x < m { x = r.maxX + gap }; y = r.midY - h / 2 }
    else { x = r.maxX - w; y = r.minY - gap - h; if y < m { y = r.maxY + gap } }
    /* the rail row turns with the screen: upright it is under the menu, on its side beside the column */
    let rt = railTop()
    switch turn {
    case 0: if y + h > rt - 6 && rt - 6 - h >= m { y = rt - 6 - h }
    case -1: if x + w > rt - 6 && rt - 6 - w >= m { x = rt - 6 - w }
    default: if x < W - rt + 6 && W - rt + 6 + w <= W - m { x = W - rt + 6 }
    }
    return CGPoint(x: max(m, min(W - m - w, x)), y: max(m, min(H - m - min(h, H - 2 * m), y)))
  }
  /* openElev and placeElevTip: upright over the pad, centred on it; otherwise beside it, on the side towards the
     window's middle; gap from the pad (the sheet 8, the tip 12) */
  func padAt(_ s: CGSize, gap: CGFloat = 8) -> CGPoint {
    let r = win(model.padUI[up]), b = win(model.barUI[up]), w = s.width, h = s.height
    let x = b.width > b.height ? r.midX - w / 2 : r.midX > W / 2 ? r.minX - w - gap : r.maxX + gap
    let y = b.width > b.height ? r.minY - h - gap : r.midY - h / 2
    return CGPoint(x: max(8, min(max(8, W - w - 8), x)), y: max(8, min(max(8, H - h - 8), y)))
  }
}

/* 6b's strip, upright left to right: english (56), power (the biggest, flex), the fine-aim wheel (72-96) and pause
   (44 x 56); on its side the same as a column */
struct Controls: View {
  let model: TableModel
  let upright: Bool
  /* a bigger screen (min-width 700, min-height 600): the strip 60 tall, 10 apart, the pad 60; the column's width (--col) */
  var big = false
  var col: CGFloat = 64
  /* settings.hand and settings.bar (Settings > Controls > Layout): left-handed reverses the strip (row-reverse); at the
     edge puts the power bar at the strip's end (order 6), on a column after the wheel (orders 1 and 2) */
  @AppStorage("felt.settings.hand") private var hand = "right"
  @AppStorage("felt.settings.bar") private var bar = "mid"
  var body: some View {
    let _ = Bench.hit("Controls")
    if upright {
      /* the strip's flex, as the CSS resolves it: power `flex: 1` (basis 0, at least 150, 136 under 390 pt), the wheel
         `flex: 1 1 72px` up to 96: the space past their bases shared evenly, the wheel's share capped */
      GeometryReader { g in
        let pad: CGFloat = big ? 60 : 56, gap: CGFloat = big ? 10 : 4
        let avail = g.size.width - pad - 44 - 3 * gap, minP: CGFloat = g.size.width + 4 < 390 ? 136 : 150
        let wheel = max(44, min(96, 72 + (avail - 72) / 2, avail - minP))
        let base = bar == "edge" ? ["spin", "wheel", "pause", "power"] : ["spin", "power", "wheel", "pause"]
        HStack(spacing: gap) {
          ForEach(hand == "left" ? base.reversed() : base, id: \.self) { id in
            switch id {
            case "spin": SpinPad(model: model, size: pad)
            case "power": PowerBar(model: model, upright: true).frame(width: avail - wheel).overlay { LessonRing(on: model.lesson?.step == 3 && !model.lessonDone) }
            case "wheel": FineWheel(model: model, upright: true).frame(width: wheel).overlay { LessonRing(on: model.lesson?.step == 2 && !model.lessonDone) }
            default: pause
            }
          }
        }
      }
    } else {
      /* the column (a tablet): #ctl's order, pause, the pad (col x col), then power and the wheel (at the edge the wheel
         first), from the top (flex-start: the room left over at the foot) */
      VStack(spacing: 10) {
        pause
        SpinPad(model: model, size: col, upright: false)
        if bar == "edge" { wheelCol; powerCol } else { powerCol; wheelCol }
      }
      .frame(maxHeight: .infinity, alignment: .top)
    }
  }
  private var powerCol: some View { PowerBar(model: model, upright: false).overlay { LessonRing(on: model.lesson?.step == 3 && !model.lessonDone) } }
  /* the column's wheel: 200 tall on a bigger screen */
  private var wheelCol: some View {
    FineWheel(model: model, upright: false).frame(height: big ? 200 : nil).overlay { LessonRing(on: model.lesson?.step == 2 && !model.lessonDone) }
  }
  private var pause: some View {
    Button { model.paused = true } label: {
      Canvas { ctx, size in
        let o = CGPoint(x: size.width / 2 - 11, y: size.height / 2 - 11), k = 22.0 / 24
        for x in [6.0, 14.0] { ctx.fill(Path(roundedRect: CGRect(x: o.x + x * k, y: o.y + 5 * k, width: 4 * k, height: 14 * k), cornerRadius: 1.2 * k), with: .color(Color(rgb: 0xec, 0xec, 0xee))) }
      }
      .frame(width: upright ? 44 : col, height: upright ? (big ? 60 : 56) : (big ? 48 : 44))
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
  @State private var wv: Double? = nil
  @State private var wt = 0.0
  @State private var trail: AimFeel.Trail = []
  var body: some View {
    let _ = Bench.hit("FineWheel")
    let stops: [Gradient.Stop] = [.init(color: Color(rgb: 0x14, 0x14, 0x16), location: 0), .init(color: Color(rgb: 0x50, 0x50, 0x5a), location: 0.24),
      .init(color: Color(rgb: 0x6e, 0x6e, 0x78), location: 0.5), .init(color: Color(rgb: 0x50, 0x50, 0x5a), location: 0.76), .init(color: Color(rgb: 0x14, 0x14, 0x16), location: 1)]
    /* upright the wheel turns across (left and right), on its side along its column */
    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(stops: stops, startPoint: upright ? .leading : .top, endPoint: upright ? .trailing : .bottom))
      .overlay {
        Canvas { ctx, size in
          /* .ridges: inset 8 across, every 4 pt a dark line and a light one under it, moved by --roll */
          let len = upright ? size.width : size.height
          var y = roll.truncatingRemainder(dividingBy: 4) - 4
          while y < len {
            if upright {
              ctx.fill(Path(CGRect(x: y, y: 8, width: 1, height: size.height - 16)), with: .color(.black.opacity(0.6)))
              ctx.fill(Path(CGRect(x: y + 1, y: 8, width: 1, height: size.height - 16)), with: .color(Color(rgb: 240, 240, 244).opacity(0.62)))
            } else {
              ctx.fill(Path(CGRect(x: 8, y: y, width: size.width - 16, height: 1)), with: .color(.black.opacity(0.6)))
              ctx.fill(Path(CGRect(x: 8, y: y + 1, width: size.width - 16, height: 1)), with: .color(Color(rgb: 240, 240, 244).opacity(0.62)))
            }
            y += 4
          }
          let sh: [Gradient.Stop] = [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.3), .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.55), location: 1)]
          ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(stops: sh), startPoint: .zero, endPoint: upright ? CGPoint(x: size.width, y: 0) : CGPoint(x: 0, y: size.height)))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(live ? Color(rgb: 0xec, 0xec, 0xee) : Color(rgb: 0x6b, 0x6b, 0x74), lineWidth: 1))
      .opacity(model.rolling != nil ? 0.5 : 1)
      .frame(minWidth: upright ? 44 : 64, maxWidth: upright ? 96 : .infinity, minHeight: upright ? 56 : 112, maxHeight: upright ? .infinity : 200)
      .layoutPriority(upright ? 0 : 1)
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        let t = v.time.timeIntervalSinceReferenceDate * 1000
        if !live { live = true; model.fineAim = true; model.lessonWheel(); model.takeAim(); wv = nil; wt = t; trail = [(t, model.aim, Double(v.location.x), Double(v.location.y))] }
        let d = upright ? v.translation.width : v.translation.height, dy = Double(d - last)
        guard dy != 0 else { return }
        /* wheelRate by the finger's smoothed speed; right (upright) or down (on its side) turns the cue clockwise on screen */
        if model.rolling == nil {
          wv = AimFeel.fingerSpeed(wv, abs(dy), t - wt)
          model.aim += dy * AimFeel.wheelRate(wv ?? 0); roll += d - last
          AimFeel.push(&trail, t, model.aim, v.location)
        }
        last = d; wt = t
      }.onEnded { v in
        if model.rolling == nil, let r = AimFeel.liftAim(trail, v.time.timeIntervalSinceReferenceDate * 1000) { model.aim = r }
        last = 0; live = false; trail = []; model.fineAim = false
        /* lock wherever the pointer next shows up on the table, not where it left it */
        model.pendLock()
      })
      .accessibilityLabel("Fine aim")
  }
}

/* english (#spinPad): the cue ball, where the tip meets it: top is follow, bottom draw, side either way; the dashed
   ring is |spin| = 1 (inset 19%), the crosshair 62% long, the tip a chalk-blue dot ringed in white */
struct SpinPad: View {
  let model: TableModel
  /* #spinPad: 56; 60 in a bigger screen's strip, the column's width in a column */
  var size: CGFloat = 56
  /* in the strip (upright) or the column: which frame it reports (PopLayer) */
  var upright = true
  /* the press: when and where it began, how far it has gone, the tip before it (a hold puts it back) */
  @State private var down: (t: Date, p: CGPoint, far: CGFloat, before: Spin)? = nil
  @State private var hold: Task<Void, Never>? = nil
  static let ELEV_HOLD_MS = 450
  var body: some View {
    let _ = Bench.hit("SpinPad")
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
      /* #elevTag: the cue's elevation, in the pad's corner, while it is raised */
      .overlay(alignment: .bottomTrailing) {
        if model.elevDeg > 0 {
          Text("\(model.elevDeg)\u{00b0}").font(.system(size: 11, weight: .bold)).monospacedDigit().foregroundStyle(.white)
            .padding(.horizontal, 4).frame(height: 14).background(RoundedRectangle(cornerRadius: 8).fill(Color(rgb: 0x1f, 0x1f, 0x24)))
            .offset(x: 4, y: 4).allowsHitTesting(false)
        }
      }
      .contentShape(Circle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        guard model.spinOk else { return }
        if down == nil {
          down = (v.time, v.startLocation, 0, model.spin)
          hold?.cancel()
          /* a hold (ELEV_HOLD_MS, still) leaves the tip where it was and opens the elevation sheet */
          hold = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(SpinPad.ELEV_HOLD_MS))
            guard !Task.isCancelled, let dn = down, dn.far < 8, model.spinOk else { return }
            model.spin = dn.before; down = (dn.t, dn.p, .infinity, dn.before); model.elevOpen = true
          }
        }
        guard var dn = down, dn.far.isFinite else { return }
        dn.far = max(dn.far, hypot(v.location.x - dn.p.x, v.location.y - dn.p.y)); down = dn
        /* spinAt: inside the safe circle, the centre snaps; the elevation kept */
        var x = Double((v.location.x - d / 2) / R), y = -Double((v.location.y - d / 2) / R)
        let L = hypot(x, y)
        if L > 1 { x /= L; y /= L }
        if L < 0.08 { x = 0; y = 0 }
        model.spin = spinOf(x: x, y: y, e: model.spin.e)
      }.onEnded { _ in hold?.cancel(); down = nil })
      .onTapGesture(count: 2) { if model.spinOk { model.spin = spinOf(x: 0, y: 0, e: model.spin.e) } }
    }
    .frame(width: size, height: size)
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TableScreen.UI)) } action: { model.padUI[upright ? 1 : 0] = $0 }
    .accessibilityLabel("English")
    .accessibilityValue("side \(Int(model.spin.x * 100)), follow \(Int(model.spin.y * 100))" + (model.elevDeg > 0 ? ", cue up \(model.elevDeg) degrees" : ""))
    .accessibilityAction(named: "Cue Elevation") { if model.spinOk { model.elevOpen = true } }
  }
}

/* #elevPop: the cue's elevation, 0 to 60 degrees in whole degrees: the value, a slider that fills from the bed up with
   the cue drawn at its angle (drag or tap it; swipe up or down with VoiceOver for 5 degrees), Level. Closed by a tap
   anywhere else or once the turn is not the player's to aim; every shot starts level */
struct ElevPop: View {
  let model: TableModel
  var body: some View {
    let deg = model.elevDeg
    VStack(spacing: 8) {
      Text(deg > 0 ? "\(deg)\u{00b0}" : "Level").font(.system(size: 13, weight: .bold)).monospacedDigit()
      GeometryReader { g in
        ZStack(alignment: .bottom) {
          Rectangle().fill(Color(rgb: 91, 149, 208).opacity(0.55)).frame(height: g.size.height * CGFloat(deg) / 60)
          RoundedRectangle(cornerRadius: 2).fill(Color(rgb: 0xe9, 0xd9, 0xb0)).frame(width: 3, height: 70)
            .rotationEffect(.degrees(Double(90 - deg)), anchor: .bottom).padding(.bottom, 10)
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
          if model.spinOk { model.setElev(60 * min(1, max(0, Double((g.size.height - v.location.y) / g.size.height)))) }
        })
      }
      .frame(width: 48, height: 150)
      .background(Color(rgb: 0x2c, 0x2c, 0x2e))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(rgb: 0x6b, 0x6b, 0x74), lineWidth: 1))
      .accessibilityElement()
      .accessibilityLabel("Cue elevation: raise the cue and side spin curves the ball; raised steeply and struck firmly, the ball jumps.")
      .accessibilityValue(deg > 0 ? "cue up \(deg) degrees" : "level")
      .accessibilityAdjustableAction { d in model.setElev(Double(deg) + (d == .increment ? 5 : -5)) }
      Button { if model.spinOk { model.setElev(0) }; model.elevOpen = false } label: {
        Text("Level").font(.system(size: 13, weight: .bold)).frame(minWidth: 64, minHeight: 44)
          .background(RoundedRectangle(cornerRadius: 12).fill(Color(rgb: 0x2c, 0x2c, 0x2e)))
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
      }
      .foregroundStyle(.white).accessibilityIdentifier("elevLevel")
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 16).fill(Color(rgb: 0x1c, 0x1c, 0x1e)))
    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    .accessibilityAddTraits(.isModal)
    .accessibilityLabel("Cue elevation")
  }
}

/* #elevTip: the coach card's look (rgba(22, 22, 24, .95), the line's border, 16 pt corners), at most 300 pt wide: Raise the
   Cue, how, and Got It (a white 44 pt capsule) */
struct ElevTip: View {
  let model: TableModel
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(TableModel.ELEV_TIP_HEAD).font(.system(size: 12, weight: .semibold)).kerning(0.12).foregroundStyle(Color(rgb: 0xf2, 0xc9, 0x4c)).padding(.bottom, 2)
      Text(TableModel.ELEV_TIP_TEXT).font(.system(size: 15)).lineSpacing(15 * 0.35 - 3).fixedSize(horizontal: false, vertical: true).padding(.bottom, 8)
      Button { model.hideElevTip() } label: {
        Text("Got It").font(.system(size: 15, weight: .bold)).padding(.horizontal, 16).frame(minWidth: 88, minHeight: 44)
          .background(Capsule().fill(.white)).foregroundStyle(Color(rgb: 0x14, 0x14, 0x14))
      }
      .accessibilityIdentifier("elevTipOk")
    }
    .foregroundStyle(.white)
    .padding(EdgeInsets(top: 10, leading: 14, bottom: 12, trailing: 14))
    .frame(maxWidth: 300, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 16).fill(Color(rgb: 22, 22, 24).opacity(0.95)))
    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
    .shadow(color: .black.opacity(0.5), radius: 20, y: 12)
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityElement(children: .contain).accessibilityIdentifier("elevTip")
  }
}

/* the only control that shoots (#powerBar): pull along it (upright to the right, on its side down), let go. Idle it
   shows only the chevrons pointing the way to pull, a slow shimmer running along them; pulled, the fill (cream, the
   signal red past 85%) and the percentage */
struct PowerBar: View {
  let model: TableModel
  let upright: Bool
  /* pullFull: a thumb's reach, clamp(0.42 min(width, height), 150, 300) of the screen */
  @MainActor static var pullFull: Double { let s = UIScreen.main.bounds.size; return min(300, max(150, 0.42 * Double(min(s.width, s.height)))) }
  @State private var t0: Date? = nil
  @State private var fullOnce = false
  @Environment(\.accessibilityReduceMotion) private var sysStill
  private var still: Bool { sysStill || Prefs.bool("reduceMotion", false) }
  var body: some View {
    let _ = Bench.hit("PowerBar")
    GeometryReader { g in
      let len = upright ? g.size.width : g.size.height, p = CGFloat(model.power), live = p > 0
      let fill: [Gradient.Stop] = p > 0.85 ? [.init(color: Color(rgb: 0xcf, 0xc6, 0xb2), location: 0), .init(color: Color(rgb: 0xec, 0xe4, 0xd2), location: 0.6), .init(color: Color(rgb: 0xc0, 0x39, 0x2b), location: 1)]
        : [.init(color: Color(rgb: 0xcf, 0xc6, 0xb2), location: 0), .init(color: Color(rgb: 0xec, 0xe4, 0xd2), location: 1)]
      ZStack(alignment: upright ? .leading : .top) {
        RoundedRectangle(cornerRadius: 14).fill(Color(rgb: 0x26, 0x26, 0x2a))
        Rectangle().fill(LinearGradient(stops: fill, startPoint: upright ? .leading : .top, endPoint: upright ? .trailing : .bottom))
          .frame(width: upright ? len * p : nil, height: upright ? nil : len * p)
        /* #powerMark: the marked power (the shot a Space press would play), a 2 pt tick 9 pt long at each edge of the bar */
        let mk = len * CGFloat(model.markPower) - 1, tick = Color(rgb: 0xec, 0xec, 0xee).opacity(0.6)
        Group {
          if upright {
            VStack { tick.frame(width: 2, height: 9); Spacer(minLength: 0); tick.frame(width: 2, height: 9) }.offset(x: mk)
          } else {
            HStack { tick.frame(width: 9, height: 2); Spacer(minLength: 0); tick.frame(width: 9, height: 2) }.offset(y: mk)
          }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
        if live {
          Text("\(Int((p * 100).rounded()))%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(Color(rgb: 0xec, 0xec, 0xee))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: upright ? .trailing : .bottom).padding(upright ? .trailing : .bottom, 10)
        } else if model.rolling == nil, !model.cpuTurn, let lab = model.callLab(upright: upright) ?? (model.callReady ? nil : "Call your shot") {
          /* the call is the bar's own label (callLab): "10 · Top Left", "Safety", "Push Out", or Call your shot */
          HStack(spacing: 6) {
            Text(lab).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.tail)
              .foregroundStyle(model.callReady ? Color(rgb: 0xec, 0xec, 0xee) : Color(rgb: 0xff, 0xd5, 0x8a))
          }
          .padding(.leading, 12).padding(.trailing, model.callMenuOffered ? 26 : 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if model.rolling != nil || model.rp != nil {
          Text(model.rp != nil ? "Replay" : "Rolling").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa)).frame(maxWidth: .infinity, maxHeight: .infinity)
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
      /* #callGlyph: chevron.up.chevron.down at the bar's trailing end (on its side, its foot) while the call's menu is
         offered and the bar is not pulled (#powerBar.calls:not(.live)) */
      .overlay(alignment: upright ? .trailing : .bottom) {
        if model.callMenuOffered && !live && model.rolling == nil {
          Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(rgb: 0xec, 0xec, 0xee)).opacity(0.8)
            .padding(upright ? .trailing : .bottom, 10).accessibilityHidden(true).allowsHitTesting(false)
        }
      }
      .contentShape(Rectangle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { v in
        /* a press on the bar ends a replay and is the bar's own: the pull goes on to arm and shoot */
        if model.rp != nil { model.endReplay() }
        model.hideOffer()
        guard model.rolling == nil else { return }
        if t0 == nil { t0 = Date() }
        let d = Double(upright ? v.translation.width : v.translation.height)
        /* the pull's span: from the press to the bar's far end, at least half the bar, x 0.92; it arms past armPx
           (max(28, 0.08 pullFull), a fifth of the span at most), full power at the span's end */
        let s0 = Double(upright ? v.startLocation.x : v.startLocation.y), span = max(Double(len) - s0, Double(len) * 0.5) * 0.92
        let arm = min(max(28, 0.08 * PowerBar.pullFull), span * 0.2)
        /* the bar does not arm without a needed call */
        let was = model.power
        model.power = model.callReady ? min(1, max(0, (d - arm) / (span - arm))) : 0
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
    .frame(minWidth: upright ? 136 : 64, maxWidth: .infinity, minHeight: upright ? 56 : 96, maxHeight: upright ? .infinity : 440)
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TableScreen.UI)) } action: { model.barUI[upright ? 1 : 0] = $0 }
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
/* MD_PAGES.tsetup: the new tournament page: Game, Rules (where the game has more than one) with the ruleset's note
   (`name (source). description`), Players, Format, the race, Opponents, the note, Start Tournament pinned */
struct TourneySetup: View {
  @Bindable var store: TourneyStore
  @State private var kind = "9"
  @State private var ruleset = "9-house"
  @State private var size = 8
  @State private var fmt = "single"
  @State private var race = 3
  @State private var field = "mixed"
  /* rulesetsFor(kind) for the tournament's games (RULESETS: id, name, source, description) */
  static let SETS: [String: [(String, String, String, String)]] = [
    "8": [("8-house", "8-ball, house rules", "felt house rule", "Hit one of your group first, pot it to carry on. No calls unless your settings ask for them. An 8 on the break is spotted and the breaker carries on."),
          ("8-wpa", "8-ball, WPA", "WPA world standardized rules", "Call every shot that is not obvious, and the 8 always with its pocket. A legal break pots a ball or drives four to the cushions. An 8 on the break: spot it or re-rack. A ball off the table on the break: the table as it lies, or ball in hand behind the head string.")],
    "9": [("9-house", "9-ball, house rules", "felt house rule", "Lowest ball first. A legal 9 wins, early or on the break. Three fouls in a row lose."),
          ("9-wpa", "9-ball, WPA", "WPA world standardized rules", "Lowest ball first, any legal 9 wins. Push out on the shot after the break; your opponent may hand it back. A legal break pots a ball or drives four to the cushions, and three must drop or lie past the head string, or your opponent may hand it back and any 9 is spotted. Three fouls lose.")],
    "10": [("10-wpa", "10-ball, WPA", "WPA world standardized rules", "Lowest ball first, and call your shots; an obvious one is called from your aim, and there is no safety. The 10 wins only when called as the last ball; on the break or early it is spotted. Push out after the break. Three fouls lose.")],
    "straight": [("straight-wpa", "Straight pool (14.1), WPA", "WPA world standardized rules", "Any ball, called with its pocket: a point each. With one ball left the other 14 are racked again. A foul costs a point, three in a row 15 more and a new break.")],
    "rotation": [("rotation", "Rotation (61)", "felt house rule, after the BCA game", "Lowest ball first; every ball potted on a legal shot scores its number. 61 wins. Balls potted on a foul are spotted.")],
    "heyball": [("heyball", "Chinese 8-ball", "WPA Rules of Heyball, effective 2025-08-16", "Balls potted on the break leave the table open: the first legal pot after it chooses your group, the group of the ball you hit first. A legal break pots a ball or drives four to the cushions. A foul on the break: ball in hand behind the head string, or a re-rack. Any other foul: ball in hand anywhere. The 8 last, in any pocket: nothing is called.")],
    "snooker": [("snooker", "Snooker", "WPBSA rules, simplified", "A red, then a colour, until the reds are gone; then the colours in order.")],
    "carom": [("carom", "Three-cushion", "UMB rules, simplified", "Your cue ball meets both others, with three cushions before the second. A point each.")],
  ]
  /* ruleWord: the part of the name after the comma, title-cased */
  static func ruleWord(_ name: String) -> String {
    let w = name.components(separatedBy: ", ").dropFirst().first ?? name
    return w.split(separator: " ").map { $0 == "WPA" ? String($0) : $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
  }
  var body: some View {
    let sets = Self.SETS[kind] ?? [], R = sets.first { $0.0 == ruleset } ?? sets.first
    ModeForm(kicker: "Quick Tournament", title: "New Tournament", action: "Start Tournament", actionID: "tourney-start", go: {
      store.start(Tourney.make(kind: kind, ruleset: R?.0, size: size, fmt: fmt, race: race, field: field, seed: Int.random(in: 1...0x7fffffff)))
    }) {
      ModeField("Game") { ModePop(selection: $kind, items: Tourney.KINDS.map { ($0, TourneyView.kindName($0)) }) }
      if sets.count > 1 { ModeField("Rules") { ModePop(selection: $ruleset, items: sets.map { ($0.0, Self.ruleWord($0.1)) }) } }
      if let R { ModeNote("\(R.1) (\(R.2)). \(R.3)") }
      ModeField("Players") { Picker("Players", selection: $size) { ForEach(Tourney.SIZES, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented).labelsHidden() }
      ModeField("Format") { ModePop(selection: $fmt, items: [("single", "Single Elimination"), ("double", "Double Elimination")]) }
      ModeField(Tourney.points(kind) ? "Race to (Points, One Game a Match)" : kind == "snooker" ? "Race to (Frames)" : "Race to (Racks)") {
        Picker("Race", selection: $race) { ForEach(Tourney.races(kind), id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented).labelsHidden()
      }
      ModeField("Opponents") {
        Picker("Opponents", selection: $field) { Text("Mixed").tag("mixed"); Text("Easy").tag("easy"); Text("Medium").tag("medium"); Text("Hard").tag("hard") }.pickerStyle(.segmented).labelsHidden()
      }
      ModeNote("Your matches are played on the table. Every other match is settled by the career's match model from the players' strengths, and shown as simulated.")
      if let t = store.tour, !t.done { ModeNote("Starting a new tournament ends the one under way.") }
    }
    .onChange(of: kind) { _, k in
      ruleset = DEFAULT_RULESET[k] ?? (Self.SETS[k]?.first?.0 ?? "")
      if !Tourney.races(k).contains(race) { race = ["straight": 50, "snooker": 2, "carom": 10][k] ?? 3 }
    }
  }
}

/* MD_PAGES.tour, under way: the kicker (`9-ball, 8 players, race to 3 racks`) over Quick Tournament; Your Next Match: the
   round and a race tag, the opponent's avatar (initials on their colour), name, and style and level ("Shotmaker, hard
   CPU"), Play Match; the bracket round by round (tMatchRow: the winner in bold, You in the accent, the score with
   "simulated" or "forfeit" under it, else vs; Bye, To come); End Tournament, two taps */
struct TourneyRun: View {
  @Bindable var store: TourneyStore
  let t: Tourney
  let play: () -> Void
  @State private var ending = false
  static func unitWords(_ kind: String, _ n: Int) -> String {
    kind == "straight" || kind == "carom" ? "\(n) points" : kind == "snooker" ? "\(n) frame\(n == 1 ? "" : "s")" : "\(n) rack\(n == 1 ? "" : "s")"
  }
  static let KIND_LINE = ["8": "8-ball", "9": "9-ball", "10": "10-ball", "straight": "Straight pool", "rotation": "Rotation", "heyball": "Chinese 8-ball", "snooker": "Snooker", "carom": "Three-cushion"]
  static let LEVEL = ["easy": "easy", "medium": "medium", "hard": "hard"]
  var body: some View {
    let c = t.ctx(), T = t.bracket
    let order = T.M.indices.reduce(into: [String]()) { acc, m in if CareerLib.outcome(c, m).st != "skip" { let r = t.round(m); if !acc.contains(r) { acc.append(r) } } }
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(Self.KIND_LINE[t.kind] ?? t.kind), \(t.size) players, race to \(Self.unitWords(t.kind, t.race))").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
          Text("Quick Tournament").font(.system(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
        }
        if !t.msg.isEmpty { Text(t.msg).font(.system(size: 15)) }
        if let m = t.mine() {
          let foe = t.foe(m)
          ModeField("Your Next Match") {
            VStack(alignment: .leading, spacing: 10) {
              HStack {
                Text(t.round(m)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
                Spacer()
                Text("Race to \(Self.unitWords(t.kind, t.race))").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                  .background(Capsule().fill(Color.white.opacity(0.1)))
              }
              HStack(spacing: 12) {
                Text(foe.ini ?? CareerWords.avIni(foe.name)).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).frame(width: 46, height: 46)
                  .background(Circle().fill(css(foe.col ?? CareerWords.avCol(foe.name))))
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                  Text(foe.name).font(.system(size: 17, weight: .semibold))
                  Text("\(ExhibitionSetup.STYLES.first { $0.0 == (foe.arch ?? "allround") }?.1 ?? "All-Round"), \(Self.LEVEL[foe.level ?? "medium"] ?? "medium") CPU")
                    .font(.system(size: 15)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
                }
              }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
          }
          Button(action: play) { Text("Play Match").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("tourney-play")
        } else {
          ModeNote("Your next opponent is not known yet.")
        }
        ForEach(order, id: \.self) { r in
          ModeField(titleCaseWords(r)) {
            VStack(spacing: 0) {
              let ms = T.M.indices.filter { t.round($0) == r && CareerLib.outcome(c, $0).st != "skip" }
              ForEach(Array(ms.enumerated()), id: \.element) { i, m in
                row(c, m)
                if i < ms.count - 1 { Divider().padding(.leading, 16) }
              }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
          }
        }
        Button {
          if ending { store.tour = nil; store.save() } else { ending = true; Task { try? await Task.sleep(for: .seconds(4)); ending = false } }
        } label: {
          Text(ending ? "Tap again to end it" : "End Tournament").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(ending ? Color.white : Color(rgb: 0xff, 0x8a, 0x7a))
            .background(Capsule().fill(ending ? Color(rgb: 0xc0, 0x39, 0x2b) : Color(rgb: 0x2c, 0x2c, 0x30)))
        }
        .accessibilityIdentifier("tourney-end")
      }
      .padding(.horizontal, 16).padding(.bottom, 24).pageCap()
    }
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
  /* tMatchRow: a side's name (Bye, To come; the winner bold; You in the accent), the middle the score and how it was
     settled, else bye or vs */
  @ViewBuilder private func row(_ c: CareerLib.Ctx, _ m: Int) -> some View {
    let o = CareerLib.outcome(c, m), done = o.st == "done"
    let side = { (p: Int?, trail: Bool) -> AnyView in
      let name = p == nil ? "To come" : p! < 0 ? "Bye" : p! == 0 ? "You" : t.field[p!].name
      let win = done && p != nil && o.w == p
      return AnyView(Text(name).font(.system(size: 15, weight: win ? .bold : .regular))
        .foregroundStyle(p == 0 ? Color(rgb: 0x3d, 0xdc, 0x84) : win ? Color.white : Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.75))
        .lineLimit(1).frame(maxWidth: .infinity, alignment: trail ? .trailing : .leading))
    }
    HStack(spacing: 8) {
      side(o.a, false)
      VStack(spacing: 0) {
        if done, let s = t.res[m] {
          Text("\(s[0])-\(s[1])").font(.system(size: 15, weight: .bold)).monospacedDigit()
          if t.sim[m] || t.ff[m] { Text(t.ff[m] ? "forfeit" : "simulated").font(.system(size: 11)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)) }
        } else {
          Text(o.st == "bye" ? "bye" : "vs").font(.system(size: 15, weight: .bold))
        }
      }
      .frame(width: 76)
      side(o.b, true)
    }
    .padding(.horizontal, 16).frame(minHeight: 44)
  }
}

/* MD_PAGES.tour, over: the winner's screen. Tournament Over: a card with the champion's avatar (You when it is you)
   and "You are the champion" or "<name> wins it" over its line; Final Places, the top eight by rank (and You after
   them when further down); New Tournament and Home */
struct TourneyDone: View {
  @Bindable var store: TourneyStore
  let t: Tourney
  let home: () -> Void
  @State private var fresh = false
  /* placeWords: champion, runner-up, else the ordinal */
  static func placeWords(_ p: Int) -> String {
    if p == 1 { return "champion" }; if p == 2 { return "runner-up" }
    let s = p % 100 >= 11 && p % 100 <= 13 ? "th" : [1: "st", 2: "nd", 3: "rd"][p % 10] ?? "th"
    return "\(p)\(s)"
  }
  var body: some View {
    let pl = t.place ?? t.size, places = t.places ?? [], champ = places.first { $0[1] == 1 }.map { t.field[$0[0]] }
    let kind = TourneyRun.KIND_LINE[t.kind] ?? t.kind
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(kind), \(t.size) players, race to \(TourneyRun.unitWords(t.kind, t.race))").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
          Text("Quick Tournament").font(.system(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
        }
        if !t.msg.isEmpty { Text(t.msg).font(.system(size: 15)) }
        ModeField("Tournament Over") {
          HStack(spacing: 12) {
            let name = pl == 1 ? "You" : champ?.name ?? "", av = pl == 1 ? nil : champ
            Text(av?.ini ?? CareerWords.avIni(name)).font(.system(size: 17, weight: .bold)).foregroundStyle(.white).frame(width: 46, height: 46)
              .background(Circle().fill(css(av?.col ?? CareerWords.avCol(name))))
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
              Text(pl == 1 ? "You are the champion" : "\(champ?.name ?? "") wins it").font(.system(size: 17, weight: .semibold))
              Text(pl == 1 ? "\(kind), \(t.size) players: the title is yours." : "You finished \(Self.placeWords(pl)) of \(t.size).")
                .font(.system(size: 15)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
            }
          }
          .padding(14).frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
        }
        ModeField("Final Places") {
          VStack(spacing: 0) {
            let rows = Array(places.prefix(8)) + (pl > 8 ? [[0, pl]] : [])
            ForEach(Array(rows.enumerated()), id: \.offset) { i, p in
              HStack(spacing: 12) {
                Text("\(p[1])").font(.system(size: 15, weight: .bold)).monospacedDigit().frame(width: 28)
                Text(p[0] == 0 ? "You" : t.field[p[0]].name).font(.system(size: 17, weight: p[0] == 0 ? .bold : .regular))
                Spacer()
              }
              .padding(.horizontal, 16).frame(minHeight: 44)
              if i < rows.count - 1 { Divider().padding(.leading, 56) }
            }
          }
          .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
        }
        HStack(spacing: 8) {
          Button { fresh = true } label: { Text("New Tournament").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("tourney-new")
          Button(action: home) { Text("Home").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(Color(rgb: 0x2c, 0x2c, 0x30))).foregroundStyle(.white)
        }
      }
      .padding(.horizontal, 16).padding(.bottom, 24).pageCap()
    }
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $fresh) { TourneySetup(store: store) }
  }
}

struct TourneyView: View {
  @Bindable var store: TourneyStore
  let play: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var kind = "9"
  @State private var size = 8
  @State private var fmt = "single"
  @State private var race = 3
  @State private var field = "mixed"
  static func kindName(_ k: String) -> String { ["8": "8-Ball", "9": "9-Ball", "10": "10-Ball", "straight": "Straight Pool", "rotation": "Rotation", "heyball": "Chinese 8-Ball", "snooker": "Snooker", "carom": "Three-Cushion"][k] ?? k }
  static func game(_ k: String) -> TableGame? { ["8": .eight, "9": .nine, "10": .ten, "straight": .straight, "rotation": .rotation, "heyball": .heyball, "snooker": .snooker, "carom": .carom][k] }
  static func placeWords(_ p: Int) -> String { p == 1 ? "Champion" : p == 2 ? "Runner-up" : "Place \(p)" }
  var body: some View {
    if store.tour == nil { TourneySetup(store: store) }
    else if let t = store.tour, !t.done { TourneyRun(store: store, t: t, play: play) }
    else if let t = store.tour { TourneyDone(store: store, t: t, home: { dismiss() }) }
    else { list }
  }
  private var list: some View {
    CapList {
      if let t = store.tour, !t.done { running(t) } else if let t = store.tour, t.done {
        results(t)
        Section { NavigationLink { TourneySetup(store: store) } label: { Text("New Tournament").font(.headline) } }
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
  /* the ring rulesets (rulesetsFor: ring: true), with RULESETS' descriptions */
  static let SETS: [(String, String, TableGame, String)] = [
    ("9-ring", "9-Ball Ring", .nine, "Two to four players in turn. Lowest ball first; a foul gives the next player ball in hand. Whoever pots the 9 legally wins the rack."),
    ("rotation-ring", "Rotation Ring", .rotation, "Two to four players in turn. Lowest ball first; balls potted on a legal shot score their numbers. The race wins, or the most points when the table is clear."),
    ("straight-ring", "Around the Table", .straight, "Straight pool for two to four in turn: any ball, called, a point each, fourteen down and the rack again. A foul costs a point. First to the race wins.")]
  static let ORD = ["1st", "2nd", "3rd", "4th"]
  var body: some View {
    let set = Self.SETS.first { $0.0 == ruleset }!
    ModeForm(kicker: "Party", title: "Party", action: "Start", actionID: "party-start", go: {
      let nm = (0..<count).map { i in names[i].trimmingCharacters(in: .whitespaces).isEmpty ? "Player \(i + 1)" : String(names[i].prefix(16)) }
      start(Home.PartyGo(game: set.2, names: nm, ruleset: ruleset))
    }) {
      ModeField("Game") { ModePop(selection: $ruleset, items: Self.SETS.map { ($0.0, $0.1) }) }
      ModeNote(set.3)
      ModeField("Players") {
        Picker("Players", selection: $count) { Text("2").tag(2); Text("3").tag(3); Text("4").tag(4) }.pickerStyle(.segmented).labelsHidden()
      }
      ModeField("Names, in Turn Order") {
        VStack(spacing: 0) {
          ForEach(0..<count, id: \.self) { i in
            HStack {
              Text("\(Self.ORD[i]) to shoot").font(.system(size: 15, weight: .semibold))
              TextField("Player \(i + 1)", text: $names[i]).multilineTextAlignment(.trailing).textInputAutocapitalization(.words).autocorrectionDisabled()
                .font(.system(size: 15)).accessibilityLabel("\(Self.ORD[i]) to shoot")
            }
            .padding(.horizontal, 14).frame(minHeight: 44)
            if i < count - 1 { Divider().padding(.leading, 14) }
          }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
      }
      ModeNote("The device goes round the table: whenever the turn passes, it asks for the next player. 8-ball, snooker, bumper pool and three-cushion are two-player games, played from the home screen.")
    }
  }
}

/* the modes' setup pages (6f, cvForm): a small kicker over the title, each field's label in Footnote above its control,
   notes in Footnote, the action pinned at the foot on the bar's material (cvPin) */
struct ModeForm<C: View>: View {
  let kicker: String, title: String, action: String, actionID: String
  let go: () -> Void
  @ViewBuilder let content: () -> C
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 2) {
          Text(kicker).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
          Text(title).font(.system(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
        }
        content()
      }
      .padding(.horizontal, 16).padding(.bottom, 24).pageCap()
    }
    .safeAreaInset(edge: .bottom) {
      Button(action: go) { Text(action).font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
        .background(Capsule().fill(.white)).foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.black.opacity(0.92)).accessibilityIdentifier(actionID)
    }
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    .tint(.primary)
  }
}
struct ModeField<C: View>: View {
  let label: String
  @ViewBuilder let control: () -> C
  init(_ label: String, @ViewBuilder control: @escaping () -> C) { self.label = label; self.control = control }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
      control()
    }
  }
}
struct ModeNote: View {
  let text: String
  init(_ t: String) { text = t }
  var body: some View { Text(text).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)).fixedSize(horizontal: false, vertical: true) }
}
/* a pop-up button the width of the form (6p's .popBtn): its value, the chevrons */
struct ModePop<T: Hashable>: View {
  @Binding var selection: T
  let items: [(T, String)]
  var body: some View {
    Menu {
      Picker("", selection: $selection) { ForEach(items, id: \.0) { Text($0.1).tag($0.0) } }
    } label: {
      HStack {
        Text(items.first { $0.0 == selection }?.1 ?? "").font(.system(size: 17)).foregroundStyle(.white)
        Spacer()
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa))
      }
      .padding(.horizontal, 14).frame(minHeight: 44)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
    }
  }
}

/* numRoll (6m): a score that goes up rolls up to it (ROLL_MS, an ease-out) in the rail's seats, snooker's break and the
   party's handoff. A number that falls, or the first one shown, is set at once; so is every number under Reduce Motion.
   numMem keeps each key's final number and text; text(key, s) is what to show now, asked every frame with the final
   text: a new one starts its roll from the last. The boards between racks (boardOf) are not ported. */
@MainActor enum NumRoll {
  static let ROLL_MS = 0.250
  private struct Mem { var v: Int?; var s: String; var roll: (from: Int, was: String, suf: String, t0: Double)? }
  private static var numMem: [String: Mem] = [:]
  private(set) static var rolls = 0
  static func text(_ key: String, _ s: String, now: Double = CACurrentMediaTime()) -> String {
    if var m = numMem[key], m.s == s {
      guard let r = m.roll, let v = m.v else { return s }
      let u = Swift.min(1, (now - r.t0) / ROLL_MS), n = Int((Double(r.from) + Double(v - r.from) * (1 - pow(1 - u, 3))).rounded())
      if u >= 1 { m.roll = nil; numMem[key] = m; return s }
      return n == r.from ? r.was : "\(n)\(r.suf)"
    }
    /* /^(\d+)(\D.*)?$/: the leading figures and what follows them */
    let d = s.prefix { $0.isASCII && $0.isNumber }, v = d.isEmpty ? nil : Int(d), was = numMem[key]
    var m = Mem(v: v, s: s, roll: nil)
    if let v, let w = was, let wv = w.v, v > wv, !Prefs.reduceMotion {
      m.roll = (wv, w.s, String(s.dropFirst(d.count)), now)
      rolls += 1
    }
    numMem[key] = m
    return m.roll != nil ? m.roll!.was : s
  }
  /* whether key's number is rolling now (a view's timeline runs only then) */
  static func live(_ key: String) -> Bool { numMem[key]?.roll != nil }
}
/* a number shown through numRoll, its own timeline running while it rolls */
struct RollText: View {
  let key: String, text: String
  var body: some View {
    let _ = NumRoll.text(key, text)
    TimelineView(.animation(minimumInterval: nil, paused: !NumRoll.live(key))) { _ in Text(NumRoll.text(key, text)) }
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
              RollText(key: "ho\(i)", text: model.partyScore(i)).monospacedDigit().fontWeight(.bold)
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
  @State private var game: TableGame = .nine
  @State private var a = "medium"
  @State private var b = "medium"
  @State private var archA = "potter"
  @State private var archB = "defender"
  /* ARCH_WORDS: the career's archetypes as styles */
  static let STYLES = [("allround", "All-Round"), ("potter", "Potter"), ("shotmaker", "Shotmaker"), ("defender", "Defender"), ("positional", "Positional"),
                       ("breaker", "Breaker"), ("banker", "Banker"), ("grinder", "Grinder"), ("clutch", "Clutch")]
  var body: some View {
    ModeForm(kicker: "AI Exhibition", title: "Watch the CPU", action: "Watch", actionID: "exhibit-start", go: {
      start(Home.Exhibit(game: game, levels: [a, b], archs: [archA, archB]))
    }) {
      ModeField("Table") { ModePop(selection: $game, items: TableGame.allCases.map { ($0, $0.rawValue) }) }
      ForEach(0..<2, id: \.self) { i in
        ModeField("Player \(i + 1)") {
          VStack(spacing: 10) {
            Picker("Level", selection: i == 0 ? $a : $b) { Text("Easy").tag("easy"); Text("Medium").tag("medium"); Text("Hard").tag("hard") }.pickerStyle(.segmented).labelsHidden()
            ModePop(selection: i == 0 ? $archA : $archB, items: Self.STYLES)
          }
        }
      }
      ModeNote("Both players are the CPU, each with the style you pick, through the same physics and rules as any game. The bar under the table pauses and sets the speed: 1x, 2x or 4x. Tap Replay after a shot to see it again.")
    }
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
  /* the most the window gives it (callMenuPlace's max-height), and its whole height, for placing it (PopLayer) */
  let maxH: CGFloat
  @Binding var natural: CGFloat
  /* #callBar.open's min-width */
  static let W: CGFloat = 220
  var body: some View {
    let c = model.humanCall(), gm = model.g!, need = model.engine.callNeed(gm)
    let open = model.callOn, push = model.pushOffer
    let change = open && !model.callSafe && !(model.callPushOn && push) && c?.ball != nil && !model.callLocked
    let showPk = open && !model.callSafe && !(model.callPushOn && push) && !model.callLocked && need?.pocket == true
    let flags = need?.flags == true && !model.callSafe && !(model.callPushOn && push)
    /* a short screen (a phone on its side, the pockets listed): it scrolls in what the window leaves */
    ScrollView {
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
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { natural = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(width: Self.W, height: max(1, min(natural, maxH)))
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .accessibilityElement(children: .contain).accessibilityIdentifier("callMenu")
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
  /* the pockets laid out as the table is seen (pocketCell: each in its cell of a 3 x 3 grid by its words, the empty row or
     column closed up): top-down from the screen, in 3D from the player's camera */
  private func pockets(_ c: ShotCall?) -> some View {
    let s = model.sim, up = model.uprightView
    let cells: [(Int, Int, Int)] = s.POCKET_AIM.indices.map { k in let q = model.pocketCell(k, upright: up); return (k, q[0], q[1]) }
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
  /* the pause menu's Settings and How to Play (#pPrefsBtn, #pHelpBtn), and Concede Frame's arming (armOrAct, ARM_MS 4 s) */
  @State private var sheet: String? = nil
  @State private var armed = false
  var body: some View {
    if model.paused {
      /* the pause menu (6): what game this is, the latest word (#menuMsg), Resume, Restart, Quit to Home */
      card {
        if let solo = soloNow { soloPanel(solo) } else {
        /* .kicker: 12 pt bold capitals, tracked, muted, at the card's leading edge */
        Text(("Paused, \(model.game.rawValue)" + (model.cpuLevel != nil ? " vs \(model.cardName(1).replacingOccurrences(of: " (CPU)", with: ""))" : "")).uppercased())
          .font(.system(size: 12, weight: .bold)).kerning(1.08).foregroundStyle(Color(rgb: 0xa3, 0xa3, 0xaa)).frame(maxWidth: .infinity, alignment: .leading)
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
        }
        Button { model.paused = false } label: { Label("Resume", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("resume")
        /* #pauseActs: two to a row: Restart and Quit to Home, Settings and How to Play; Concede Frame across */
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
          GridRow {
            act("Restart", "arrow.counterclockwise") { model.paused = false; model.rerack() }
            act(model.tmatch != nil ? "Forfeit Match" : "Quit to Home", "house") { model.paused = false; model.tourneyAbandon(); back() }
          }
          GridRow {
            act("Settings", "slider.horizontal.3") { sheet = "prefs" }.accessibilityIdentifier("pPrefsBtn")
            act("How to Play", "questionmark.circle") { sheet = "help" }.accessibilityIdentifier("pHelpBtn")
          }
          /* #concedeBtn: snooker's Concede Frame, two taps (armOrAct) */
          if let g = model.g, g.kind == "snooker", g.mode == nil, model.tut == nil, g.winner == nil {
            act(armed ? "Tap again to concede" : "Concede Frame", "flag", warn: true, armed: armed) {
              if armed { armed = false; model.paused = false; model.concedeFrame() }
              else { armed = true; Task { try? await Task.sleep(for: .seconds(4)); armed = false } }
            }
            .gridCellColumns(2).accessibilityIdentifier("concedeBtn")
          }
        }
      }
      .sheet(item: Binding(get: { sheet.map { SheetID(id: $0) } }, set: { sheet = $0?.id })) { s in
        NavigationStack {
          Group { if s.id == "prefs" { SettingsView() } else { HelpView(acts: HelpActions(lesson: {}, tutorial: { _ in }, modes: {}, drills: {}, career: {})) } }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { sheet = nil }.foregroundStyle(.primary) } }
        }
      }
    } else if let g = model.g, g.winner != nil, model.rolling == nil, model.tut == nil {
      GeometryReader { geo in
        /* a short screen (max-height 520, min-width 600): the words, the chips and the buttons on the left, the numbers on
           the right, in a card up to 800 wide */
        let i = geo.safeAreaInsets, two = geo.size.height + i.top + i.bottom <= 520 && geo.size.width + i.leading + i.trailing >= 600
        card(maxW: two ? 800 : 440, short: two) {
          if two {
            HStack(alignment: .top, spacing: 22) {
              VStack(alignment: .leading, spacing: 12) {
                OverHead(model: model, g: g, part: .head)
                Spacer(minLength: 2)
                overActs
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              OverHead(model: model, g: g, part: .stats).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
          } else {
            OverHead(model: model, g: g)
            overActs
          }
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
  struct SheetID: Identifiable { let id: String }
  /* soloNow: the session in play when it is solo: its kicker, title, goal and numbers */
  var soloNow: (kind: String, title: String, goal: String, cells: [(String, String)])? {
    let m = model
    if let L = m.lesson { return ("Lesson, step \(L.step) of 3", "Learn to Play", TableModel.LESSON_STEPS[L.step - 1].1, []) }
    if let T = m.tut, let t = tutById(T.id) { let st = t.steps[T.step]; return ("\(t.name) tutorial, step \(T.step + 1) of \(t.steps.count)", titleCaseWords(st.head), st.text(T.ctx ?? "solids"), []) }
    if let P = m.prac {
      return ("Practice", TableModel.PRACTICE_NAMES[P.layout] ?? "", P.edit ? "Editing: tap the cloth to drop a ball, tap a ball to take it off." : "",
              [("Shots", "\(P.shots)"), ("Pots", "\(P.pots)"), ("Pot %", P.shots > 0 ? "\(Int((100 * Double(P.potting) / Double(P.shots)).rounded()))%" : "-")])
    }
    if let D = m.drill, let d = drillById(D.id) {
      let best = DrillStore.all[d.id]
      return ("Drill, shot \(min(D.i + 1, d.shots)) of \(d.shots)", d.name, D.S?.say ?? d.goal, [("Shots", "\(D.js.count)/\(d.shots)"), ("Points", "\(D.js.reduce(0) { $0 + $1.s })"), ("Best", best.map { "\($0.best)" } ?? "-")])
    }
    if let T = m.trick, let c = trickById(T.id) {
      let i = TRICKS.firstIndex { $0.id == c.id } ?? 0, val = T.daily == nil ? trickVal(c.id) : 0, sc = TrickStore.score
      let cells: [(String, String)] = val > 0 ? [("Attempt", "\((sc.run[c.id] ?? 0) + 1) of \(TRICK_RUN)"), ("Best", "\(sc.pts[c.id] ?? 0) of \(val)"), ("Program", "\(programTotal(sc.pts))/\(programMax())")]
        : [("Tries", "\(T.attempts)"), ("Best", "\(TrickStore.best[c.id] ?? 0) of 3"), ("All Stars", "\(TrickStore.best.values.reduce(0, +))/\(TRICKS.count * 3)")]
      return (T.daily.map { "Daily shot, \(DrillStore.dayWords($0.day))" } ?? "Trick shot \(i + 1) of \(TRICKS.count)", c.title, c.goal + (trickHint(c).isEmpty ? "" : " " + trickHint(c)), cells)
    }
    return nil
  }
  @ViewBuilder private func soloPanel(_ s: (kind: String, title: String, goal: String, cells: [(String, String)])) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(s.kind).font(.footnote).foregroundStyle(.secondary)
      Text(s.title).font(.title3.bold())
      if !s.goal.isEmpty { Text(s.goal).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
      if !s.cells.isEmpty {
        HStack(spacing: 0) {
          ForEach(Array(s.cells.enumerated()), id: \.offset) { _, c in
            VStack(spacing: 2) { Text(c.0).font(.caption).foregroundStyle(.secondary); Text(c.1).font(.headline).monospacedDigit() }.frame(maxWidth: .infinity)
          }
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  /* .overlay .sheet: the panel (#1b1b1d, a #3a3a41 hairline, 22 pt corners, at most 440 wide) over a plain dim
     (rgba(8,8,9,.74), no blur: the table behind stays sharp) */
  /* the game over's actions: a tournament match's racks and the next rack or back to the bracket, else Play Again and Home */
  @ViewBuilder private var overActs: some View {
    if let t = model.tmatch {
      Text("You \(t.score[0]), \(t.foe) \(t.score[1]), race to \(t.need)").font(.subheadline).foregroundStyle(.secondary)
      if t.done {
        Button(action: back) { Text(model.tmatch?.career == true ? "Back to Career" : "Back to Tournament").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
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
  /* maxW: the game over is 800 wide on a short screen, its padding 18 by 20 (short); a card taller than the screen scrolls */
  private func card<C: View>(maxW: CGFloat = 440, short: Bool = false, @ViewBuilder _ c: () -> C) -> some View {
    ZStack {
      Color(.sRGB, red: 8 / 255, green: 8 / 255, blue: 9 / 255, opacity: 0.74).ignoresSafeArea()
      let inner = VStack(spacing: 12, content: c).padding(.horizontal, 20).padding(.top, short ? 18 : 22).padding(.bottom, short ? 18 : 20)
      ViewThatFits(in: .vertical) { inner; ScrollView { inner }.scrollBounceBehavior(.basedOnSize) }
        .frame(maxWidth: maxW)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(rgb: 0x1b, 0x1b, 0x1d)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 40, y: 24)
        .padding(16)
    }
  }
  /* .act: a 50 pt capsule on the secondary fill, its icon (19 pt, muted) before 15 pt semibold words */
  private func act(_ title: String, _ icon: String, warn: Bool = false, armed: Bool = false, _ f: @escaping () -> Void) -> some View {
    Button(action: f) {
      HStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(armed ? .white : warn ? Color(rgb: 0xff, 0x8a, 0x7a) : Color(rgb: 0xa3, 0xa3, 0xaa))
        Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(armed ? 2 : 1).minimumScaleFactor(0.8)
      }
      .foregroundStyle(armed ? .white : warn ? Color(rgb: 0xff, 0x8a, 0x7a) : Color(rgb: 0xf5, 0xf5, 0xf7))
      .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 50)
      .background(Capsule().fill(armed ? Color(rgb: 0xc0, 0x39, 0x2b) : Color(rgb: 0x2c, 0x2c, 0x30)))
    }
  }
}

/* the game setup (6, the setup sheet): the hero at its top (4m), the game's name in Large Title over its line (KINDS'
   sub), an inset grouped list (Opponent: Two Players or the CPU's three, each a ball, a name and its level; then the
   game's table and rules rows: Table and Pockets on the pool tables, bumper pool's shape, carom's race and cushions,
   snooker's table and frames, 8 and 9-ball's rules, 14.1's race, Stalemate at 8 and 9-ball), Break pinned at the foot.
   Every choice is a setting, so the setup opens on the last ones. */
struct GameSetup: View {
  let game: TableGame
  let go: () -> Void
  /* a tutorial for the game: the setup's link, and the offer on the first Break (maybeOfferTut) */
  var learn: ((String) -> Void)? = nil
  /* #setupBack: the hero's own back button (in the card on a tablet, on the panel on its side, over the hero upright) */
  var back: (() -> Void)? = nil
  @State private var offer = false
  var tutKind: String? { tutById(game.table.2) != nil ? game.table.2 : nil }
  @AppStorage("felt.opponent") private var opponent = "medium"
  @AppStorage("felt.settings.table") private var table = "7"
  @AppStorage("felt.settings.pockets") private var pockets = "regulation"
  @AppStorage("felt.settings.bumperTable") private var bumperTable = "octagon"
  @AppStorage("felt.settings.caromRace") private var caromRace = 10
  @AppStorage("felt.settings.caromCush") private var caromCush = 3
  @AppStorage("felt.settings.snookerTable") private var snookerTable = "compact"
  @AppStorage("felt.settings.snookerFrames") private var snookerFrames = 1
  @AppStorage("felt.settings.rules8") private var rules8 = DEFAULT_RULESET["8"]!
  @AppStorage("felt.settings.rules9") private var rules9 = DEFAULT_RULESET["9"]!
  @AppStorage("felt.settings.race141") private var race141 = 50
  @AppStorage("felt.settings.stalemate") private var stalemate = false
  /* setupRoom's measures: each list's content (one, or the two columns), Break's bar and the hero's words; fit is the
     data-fit step (fitSetupRows) */
  @State private var colH = [0.0, 0.0]
  @State private var footH = 70.0
  @State private var txtH = 70.0
  @State private var fit = 0
  static let FIT_STEPS = 4, HERO_MIN = 0.2, HERO_MAX = 0.5, CARD_HERO = 262.0
  static let fitLog = ProcessInfo.processInfo.arguments.contains("-felt-setupfit")
  @State private var names = Prefs.names
  @State private var showRules = false
  /* the home card's morph (6m), when a card opened this setup */
  @Environment(Morph.self) private var mo: Morph?
  /* #rulesPop: its title, the ruleset's name, the words; following the choices live */
  var rulesPop: some View {
    let I = RulesInfo.of(kind, title: game.rawValue)
    return VStack(alignment: .leading, spacing: 8) {
      HStack { Text(I.title).font(.headline); Spacer(); Button("Done") { showRules = false }.font(.body.weight(.semibold)).foregroundStyle(.primary) }
      Text(I.src).font(.footnote).foregroundStyle(.secondary)
      ForEach(I.ps, id: \.self) { Text($0).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
    }
    .padding(16).frame(width: 320)
  }
  static let SUB: [TableGame: String] = [
    .eight: "Solids and stripes. Clear your group, then pot the 8.", .nine: "Lowest ball first. A legal 9 wins, whenever it drops.",
    .bumper: "Red against white, five each, round the posts to the far cup.", .carom: "No pockets. Your cue ball meets both others, three cushions before the second.",
    .snooker: "A red, then a colour, and again. Most points wins the frame.", .ten: "Lowest ball first, and call your shots. The 10 wins, called, when it is the last ball.",
    .straight: "14.1 continuous: any ball, called, a point each. Fourteen down, rack again.", .rotation: "Lowest ball first; every ball scores its number. 61 wins.",
    .heyball: "Snooker pockets, pool balls. Clear your group, then the 8 in any pocket."]
  /* FOES: the CPU opponents, one per level, each with its ball (1, 5, 8) */
  /* GAMES' setup balls (#setupBall): b8, b9, b10, b14, b15; bumper's red, carom's yellow, snooker's red */
  static let NUM: [TableGame: Int] = [.eight: 8, .nine: 9, .ten: 10, .straight: 14, .rotation: 15, .heyball: 8]
  static let BALL: [TableGame: String] = [.bumper: "bb", .carom: "bc", .snooker: "bsnk"]
  /* a row's insets: 16 pt in from the group's sides, none above or below (the row is its own 44 pt) */
  static let ROW = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
  static let FOES: [(id: String, name: String, level: String, n: Int)] = [("easy", "Rookie", "Easy", 1), ("medium", "Regular", "Medium", 5), ("hard", "Hustler", "Hard", 8)]
  var kind: String { game.table.2 }
  var pool: Bool { ["8", "9", "10", "straight", "rotation"].contains(kind) }
  var body: some View {
    GeometryReader { g in
      let ins = g.safeAreaInsets, W = g.size.width, S = g.size.height, H = S + ins.bottom
      /* a phone (max-width 600 or max-height 500) has the whole screen, on its side (max-height 500) the hero a 32% panel
         down the leading side and the form in two columns over Break; anything bigger a card of at most 480, 860 with
         two columns on a short wide window (min-width 700, max-height 620) */
      let phone = W <= 600 || H <= 500, side = W > H && H <= 500, wide = !phone && W > H && W >= 700 && H <= 620
      let cols = side || wide ? 2 : 1, content = cols == 2 ? max(colH[0], colH[1]) : colH[0]
      /* heroFit (portrait phone): the room the form leaves, from its floor (HERO_MIN of the sheet, or its words and the
         back button's room if more) up to HERO_MAX */
      let floor = max(Self.HERO_MIN * S, ins.top + (fit >= 1 ? 58 : 64) + txtH + 8), spare = S - footH - content
      let cardMax = H - max(16, ins.top) - max(16, ins.bottom), cardWant = Self.CARD_HERO + content + footH
      /* setupRoom's fits: the form and Break with the hero at its floor or more; on its side or in a card, the form in its own box */
      let fits = side ? content <= S - footH + 1 : phone ? spare >= floor - 0.5 : cardWant <= cardMax + 1
      Group {
        if side {
          HStack(spacing: 0) {
            hero(top: 0, lead: max(16, ins.leading)).frame(width: W * 0.32)
            VStack(spacing: 0) { form(2); foot }.padding(.trailing, ins.trailing)
          }
        } else if phone {
          VStack(spacing: 0) {
            hero(top: ins.top, lead: 16).frame(height: content > 0 ? min(max(spare, floor), Self.HERO_MAX * S) : Self.HERO_MAX * S)
            form(1)
            foot
          }
        } else {
          VStack(spacing: 0) {
            hero(top: 0, lead: 16).frame(height: Self.CARD_HERO)
            form(cols)
            foot
          }
          /* as tall as its form (the room it may take until the list has measured), at most the screen less its margins */
          .frame(width: min(wide ? 860 : 480, W - 32), height: content > 0 ? min(cardWant, cardMax) : cardMax)
          .background(Color.black)
          .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
          .shadow(color: .black.opacity(0.55), radius: 40, y: 24)
          .frame(width: W, height: S)
          .background(Color(rgb: 8, 8, 9))
        }
      }
      /* fitSetupRows: the spacing gives in steps (fit 1 to FIT_STEPS), each only as needed; a new size or form starts over */
      .task(id: "\(fitKey(W, H))|\(fit)|\(Int(content))|\(Int(footH))|\(Int(txtH))") {
        try? await Task.sleep(for: .milliseconds(30))
        if Task.isCancelled { return }
        if !fits && fit < Self.FIT_STEPS { fit += 1 }
        if Self.fitLog { print(String(format: "felt-setupfit %@ %.0fx%.0f fit %d content %.1f foot %.1f spare %.1f floor %.1f fits %d", side ? "side" : phone ? "phone" : "card", W, H, fit, content, footH, spare, floor, fits ? 1 : 0)); fflush(stdout) }
      }
      .onChange(of: fitKey(W, H)) { fit = 0 }
    }
    .background(Color.black)
    .ignoresSafeArea(edges: [.top, .horizontal])
    /* #tutOffer: the first Break of a game whose tutorial is neither done nor turned down */
    .sheet(isPresented: $offer) {
      let k = tutKind ?? "8"
      VStack(spacing: 14) {
        Text("First time playing \(TutStore.WORD[k] ?? k)?").font(.title2.bold()).multilineTextAlignment(.center)
        Text("A one minute tutorial: the rules, played. Or skip it and break.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        HStack(spacing: 10) {
          Button { offer = false; learn?(k) } label: { Text("Show Me").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("tutOfferGo")
          Button { var r = TutStore.rec; r.skipped.insert(k); TutStore.rec = r; offer = false; go() } label: { Text("Skip").frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(Color(white: 0.2))).foregroundStyle(.white)
        }
        Button("Don't Ask Again") { var r = TutStore.rec; r.never = true; TutStore.rec = r; offer = false; go() }.foregroundStyle(.secondary).frame(minHeight: 44)
      }
      .padding(24).presentationDetents([.height(300)])
    }
    /* `-felt-rules`: the (i) popover open (with -felt-setup) */
    .task { if ProcessInfo.processInfo.arguments.contains("-felt-rules") { try? await Task.sleep(for: .seconds(1)); showRules = true } }
  }
  /* the hero is rebuilt when the table changes */
  /* .wl: the record against that CPU, after the level ("Medium · 3 won, 1 lost") */
  func wl(_ lv: String) -> String { let r = Rec.load().kinds[kind]?.cpu[lv] ?? RecLevel(); return r.w + r.l > 0 ? " \u{00b7} \(r.w) won, \(r.l) lost" : "" }
  var setupKey: String { [table, pockets, bumperTable, snookerTable].joined(separator: "|") }
  /* what the fit steps start over on: the size, and the rows (Opponent's, the tutorial's link) */
  func fitKey(_ W: CGFloat, _ H: CGFloat) -> String { "\(Int(W))x\(Int(H))|\(opponent == "two")|\(tutKind.map { TutStore.rec.done.contains($0) } ?? true)" }
  /* the hero (4m): the game's table, the Large Title with its (i) and the game's line on its lower edge (one line from
     fit 2), the game's ball at its top right; top is the status bar's room over it, lead the words' leading inset */
  func hero(top: CGFloat, lead: CGFloat) -> some View {
    /* the home's morph (Morph): the hero built under the flight, its frame and the title's reported for the landing */
    HeroView(game: game, txt: 104, hold: mo?.heroHold ?? false, under: mo?.under, underScale: mo?.underScale ?? 3, onFrame: mo.map { m in { m.heroFrame = $0 } })
      .opacity(mo?.hideHero == true ? 0 : 1)
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mo?.heroRect = $0 }
      .overlay(alignment: .bottomLeading) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .center) {
            Text(game.rawValue).font(.largeTitle.bold()).foregroundStyle(.white)
              .opacity(mo?.hideTitle == true ? 0 : 1)
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mo?.titleRect = $0 }
            Spacer()
            /* #rulesInfo: the (i) at the title's trailing end, the rules' words in a popover */
            Button { showRules = true } label: { Image(systemName: "info.circle").font(.title2).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)).frame(width: 44, height: 44) }
              .accessibilityLabel("About \(game.rawValue) Rules").accessibilityIdentifier("rulesInfo")
              .popover(isPresented: $showRules, arrowEdge: .top) { rulesPop.presentationCompactAdaptation(.popover) }
          }
          Text(Self.SUB[game] ?? game.line).font(.subheadline).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)).lineLimit(fit >= 2 ? 1 : 2)
        }
        .onGeometryChange(for: Double.self) { $0.size.height } action: { txtH = $0 }
        .padding(.leading, lead).padding(.trailing, 16).padding(.bottom, 8)
      }
      .overlay(alignment: .topLeading) {
        /* #setupBack (.back): a 44 pt circle, #2c2c2e with a .5 pt light edge, chevron.left; the status bar's room and
           10 pt down, at the words' leading inset */
        if let back {
          Button(action: back) {
            Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 44)
              .background(Circle().fill(Color(rgb: 0x2c, 0x2c, 0x2e))).overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
          }
          .buttonStyle(.plain).padding(.top, top + 10).padding(.leading, lead)
          .accessibilityLabel("Back to home").accessibilityIdentifier("back")
        }
      }
      .overlay(alignment: .topTrailing) {
        /* #setupBall: the game's ball, 40 pt, top right of the hero */
        Group { if let st = Self.BALL[game] { BallDot(style: st) } else { BallDot(n: Self.NUM[game] ?? 8) } }
          .frame(width: 40, height: 40).padding(.top, top + 12).padding(.trailing, 16).accessibilityHidden(true)
      }
      .clipped()
      .id(setupKey)
      .onChange(of: setupKey) { _, _ in mo?.under = nil }
  }
  /* .setFoot: Break, pinned under the form */
  var foot: some View {
    Button { if let k = tutKind, learn != nil, TutStore.offer(k) { offer = true } else { go() } } label: { Text("Break").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
      .background(Capsule().fill(.white)).foregroundStyle(.black).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
      .accessibilityIdentifier("break")
      .onGeometryChange(for: Double.self) { $0.size.height } action: { footH = $0 }
  }
  /* the form: one inset grouped list, or on its side two (who plays on the left, the table and rules on the right) */
  @ViewBuilder func form(_ cols: Int) -> some View {
    if cols == 2 {
      HStack(alignment: .top, spacing: 0) { styled(List { colA }, 0); styled(List { colB }, 1) }
    } else { styled(List { colA; colB }, 0) }
  }
  func styled(_ list: some View, _ i: Int) -> some View {
    list
      .pickerStyle(.menu)
      .tint(.primary)
      .font(.system(size: 17))
      .environment(\.defaultMinListRowHeight, 44)
      .listSectionSpacing(16)
      .contentMargins(.top, fit >= 1 ? 0 : 12, for: .scrollContent)
      .contentMargins(.bottom, 0, for: .scrollContent)
      .scrollBounceBehavior(.basedOnSize)
      .onScrollGeometryChange(for: Double.self) { $0.contentSize.height + $0.contentInsets.top } action: { _, h in colH[i] = h }
  }
  /* who plays: the tutorial's link, Opponent and the CPU's three (one line each from fit 3) or the two names */
  @ViewBuilder var colA: some View {
    /* #tutLink: Learn 8-Ball, until that tutorial is done */
    if let k = tutKind, let learn, !TutStore.rec.done.contains(k) {
      Section {
        Button { learn(k) } label: {
          HStack(spacing: 12) {
            Image(systemName: "graduationcap").foregroundStyle(Color(rgb: 0x3d, 0xdc, 0x84)).accessibilityHidden(true)
            Text(titleCaseWords("Learn \(game.rawValue)")).foregroundStyle(.primary)
            Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
          }
        }
        .accessibilityIdentifier("tutLink").frame(minHeight: 44).listRowInsets(Self.ROW)
      }
    }
    Section {
      Picker("Opponent", selection: Binding(get: { opponent == "two" ? "two" : "cpu" }, set: { opponent = $0 == "two" ? "two" : (opponent == "two" ? "medium" : opponent) })) {
        Text("Two Players").tag("two"); Text("CPU").tag("cpu")
      }
      .pickerStyle(.segmented).accessibilityIdentifier("opponent").frame(minHeight: 44).listRowInsets(Self.ROW)
      /* #nameRow: the two players' names, two fields (36 pt, the fill, Player 1 and Player 2 until given) */
      if opponent == "two" {
        HStack(spacing: 12) {
          Text("Names")
          HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { i in
              TextField("Player \(i + 1)", text: Binding(get: { names[i] }, set: { v in names[i] = String(v.prefix(12)); Prefs.names = names }))
                .textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
                .padding(.horizontal, 10).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.46, opacity: 0.24)))
                .accessibilityLabel("Player \(i + 1)").accessibilityIdentifier("name\(i + 1)")
            }
          }
        }
        .frame(minHeight: 44).listRowInsets(Self.ROW)
      }
      if opponent != "two" {
        ForEach(Self.FOES, id: \.id) { f in
          Button { opponent = f.id } label: {
            /* .foe: ball, the name over its level and record (fit 3: on one line, the level as the row's value), a
               checkmark in the accent */
            HStack(spacing: 12) {
              BallDot(n: f.n).frame(width: 28, height: 28)
              if fit >= 3 {
                Text(f.name).font(.system(size: 17)).foregroundStyle(.primary).fixedSize()
                Text(f.level + wl(f.id)).font(.system(size: 17)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)).lineLimit(1)
                  .frame(maxWidth: .infinity, alignment: .trailing)
              } else {
                VStack(alignment: .leading, spacing: 0) {
                  Text(f.name).font(.system(size: 17)).foregroundStyle(.primary)
                  Text(f.level + wl(f.id)).font(.system(size: 15)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)).lineLimit(1)
                }
                Spacer()
              }
              if opponent == f.id { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(rgb: 0x3d, 0xdc, 0x84)) }
            }
            .frame(minHeight: fit >= 3 ? 44 : 54)
          }
          .accessibilityAddTraits(opponent == f.id ? .isSelected : []).accessibilityIdentifier("foe-" + f.id)
          .listRowInsets(Self.ROW)
        }
      }
    }
  }
  /* the game's table and rules: two groups, one from fit 4 */
  @ViewBuilder var colB: some View {
    if fit >= 4 { Section { tableRows; rulesRows } } else { Section { tableRows }; Section { rulesRows } }
  }
  @ViewBuilder var tableRows: some View {
    if pool {
      Picker("Table", selection: $table) { Text("7 ft Bar").tag("7"); Text("9 ft Pro").tag("9") }.listRowInsets(Self.ROW)
      Picker("Pockets", selection: $pockets) { Text("Regulation").tag("regulation"); Text("Generous").tag("generous") }.listRowInsets(Self.ROW)
    }
    if kind == "bumper" { Picker("Table", selection: $bumperTable) { Text("Octagon").tag("octagon"); Text("Rectangle").tag("rect") }.listRowInsets(Self.ROW) }
    if kind == "carom" {
      Picker("Race To", selection: $caromRace) { Text("5").tag(5); Text("10").tag(10); Text("15").tag(15) }.listRowInsets(Self.ROW)
      Picker("Cushions", selection: $caromCush) { Text("Three").tag(3); Text("1-Cushion (Easier)").tag(1) }.listRowInsets(Self.ROW)
    }
    if kind == "snooker" {
      Picker("Table", selection: $snookerTable) { Text("Compact 10 ft").tag("compact"); Text("Full 12 ft").tag("full") }.listRowInsets(Self.ROW)
      Picker("Frames", selection: $snookerFrames) { Text("One Frame").tag(1); Text("Best of 3").tag(3) }.listRowInsets(Self.ROW)
    }
}
  /* the rules' group, apart from the table's */
  @ViewBuilder var rulesRows: some View {
        if kind == "8" { Picker("Rules", selection: $rules8) { Text("House Rules").tag("8-house"); Text("WPA").tag("8-wpa") }.listRowInsets(Self.ROW) }
    if kind == "9" { Picker("Rules", selection: $rules9) { Text("House Rules").tag("9-house"); Text("WPA, Push Out").tag("9-wpa") }.listRowInsets(Self.ROW) }
    if kind == "straight" { Picker("Race To", selection: $race141) { ForEach([25, 50, 100, 150], id: \.self) { Text("\($0)").tag($0) } }.listRowInsets(Self.ROW) }
    if kind == "8" || kind == "9" { Picker("Stalemate", selection: $stalemate) { Text("Play On").tag(false); Text("Re-Rack (House)").tag(true) }.listRowInsets(Self.ROW) }
}
}

/* a little ball for a row (the page's .ball classes: .b1, .b5, .b8 solids; .b9, .b10, .b14, .b15 stripes; "bb" bumper
   pool's red with its spot, "bc" carom's yellow, "bsblk" snooker's black): a lit sphere with the inset shade, the ivory
   circle to 30%, its number */
struct BallDot: View {
  var n: Int = 0
  var style: String? = nil
  var body: some View {
    GeometryReader { g in
      let d = min(g.size.width, g.size.height)
      ZStack {
        switch style {
        case "bb":
          Circle().fill(RadialGradient(colors: [Color(rgb: 0xe0, 0x47, 0x3f), Color(rgb: 0x8e, 0x1a, 0x1d)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.72))
          Circle().fill(Color(rgb: 0xf6, 0xf4, 0xec)).frame(width: d * 0.34, height: d * 0.34)
        case "bc": Circle().fill(RadialGradient(colors: [Color(rgb: 0xff, 0xe4, 0x8a), Color(rgb: 0xc9, 0x95, 0x12)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.72))
        case "bsblk": Circle().fill(RadialGradient(colors: [Color(rgb: 0x55, 0x55, 0x5a), Color(rgb: 0x16, 0x16, 0x18)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.7))
        case "bsnk": Circle().fill(RadialGradient(colors: [Color(rgb: 0xe8, 0x50, 0x4a), Color(rgb: 0x8a, 0x12, 0x18)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.72))
        default:
          if let band = [9: Color(rgb: 0xf2, 0xbe, 0x28), 10: Color(rgb: 0x1c, 0x48, 0xb8), 14: Color(rgb: 0x16, 0x78, 0x42), 15: Color(rgb: 0x7a, 0x1e, 0x20)][n] {
            ZStack { Color(rgb: 0xf6, 0xf4, 0xec); band.frame(height: d * 0.56) }.clipShape(Circle())
          } else {
            let c: (Color, Color) = n == 1 ? (Color(rgb: 0xff, 0xd8, 0x66), Color(rgb: 0xd2, 0x9a, 0x0e)) : n == 5 ? (Color(rgb: 0xff, 0x9e, 0x57), Color(rgb: 0xc4, 0x52, 0x0c)) : (Color(rgb: 0x4a, 0x4a, 0x4e), Color(rgb: 0x16, 0x16, 0x18))
            Circle().fill(RadialGradient(colors: [c.0, c.1], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.72))
          }
          Circle().fill(Color(rgb: 0xf6, 0xf4, 0xec)).frame(width: d * 0.6, height: d * 0.6)
          Text("\(n)").font(.system(size: d * (n >= 10 ? 0.3 : 0.36), weight: .heavy)).foregroundStyle(Color(rgb: 0x14, 0x14, 0x14))
        }
        /* the inset shade (box-shadow: inset -4px -5px 8px rgba(0,0,0,.35)) */
        Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.35)], center: UnitPoint(x: 0.38, y: 0.35), startRadius: d * 0.3, endRadius: d * 0.62))
      }
      .frame(width: d, height: d)
    }
    .accessibilityHidden(true)
  }
}

/* #pracSheet: the practice racks, each a session of its own */
struct PracticePicker: View {
  let go: (String) -> Void
  static let ROWS: [(String, String, String, Int?, String?)] = [("8", "8-Ball Rack", "Break and run", 8, nil), ("9", "9-Ball Rack", "The diamond", 9, nil),
    ("heyball", "Chinese 8-Ball Rack", "Its own table, snooker's pockets", 8, nil), ("scatter", "Free Table", "Seven balls, scattered", nil, "scatter"), ("empty", "Empty Table", "Tap the cloth to drop balls", nil, "cue")]
  var body: some View {
    List {
      Section {
        ForEach(Self.ROWS, id: \.0) { r in
          Button { go(r.0) } label: {
            HStack(spacing: 12) {
              if let n = r.3 { BallDot(n: n).frame(width: 30, height: 30) }
              else if r.4 == "cue" { Circle().fill(Color(rgb: 0xf6, 0xf4, 0xec)).frame(width: 30, height: 30).accessibilityHidden(true) }
              else { HStack(spacing: 2) { ForEach([1, 5, 9], id: \.self) { BallDot(n: $0).frame(width: 12, height: 12) } }.frame(width: 30, height: 30) }
              VStack(alignment: .leading, spacing: 2) {
                Text(r.1).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(r.2).font(.footnote).foregroundStyle(.secondary)
              }
            }.frame(minHeight: 44, alignment: .leading)
          }
          .accessibilityIdentifier("prac-" + r.0)
        }
      } footer: { Text("No opponent and no fouls: it is always your shot. Undo any shot, take ball in hand when you like.") }
    }
    .navigationTitle("Practice")
  }
}

/* #soloCtl and #tools: Undo (dimmed with nothing to undo), the tools button (lit while ball in hand or editing) and its
   strip (Ball in Hand, Reset Rack, Add / Remove Balls on a free table), Done Editing while editing */
struct PracticeTools: View {
  let model: TableModel
  var body: some View {
    let P = model.prac!, hand = model.g?.hand ?? false, aiming = model.rolling == nil && model.stroke == nil
    VStack(alignment: .trailing, spacing: 8) {
      HStack(spacing: 8) {
        Button { model.undo() } label: { icon("arrow.uturn.backward") }
          .opacity(P.undo.isEmpty ? 0.5 : 1).accessibilityLabel("Undo the last shot").accessibilityIdentifier("undo")
        Button { model.prac?.tools.toggle() } label: { icon("slider.horizontal.3", on: P.edit || hand) }
          .accessibilityLabel("Practice tools: ball in hand, reset, edit").accessibilityValue(P.tools ? "expanded" : "collapsed").accessibilityIdentifier("tools")
      }
      if P.tools && aiming {
        VStack(alignment: .trailing, spacing: 6) {
          tool("Ball in Hand", on: hand) { model.toggleHand(); model.prac?.tools = false }
          tool("Reset Rack") { model.resetRack() }
          if model.freeTable { tool("Add / Remove Balls", on: P.edit) { model.setEdit(!P.edit) } }
        }
      }
      if P.edit && aiming { tool("Done Editing") { model.setEdit(false) } }
    }
    .disabled(!aiming)
  }
  func icon(_ name: String, on: Bool = false) -> some View {
    Image(systemName: name).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
      .foregroundStyle(on ? Color.black : Color(rgb: 0xec, 0xec, 0xee))
      .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color(rgb: 0xec, 0xec, 0xee) : Color(rgb: 0x1b, 0x1b, 0x1d).opacity(0.9)))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
  }
  func tool(_ t: String, on: Bool = false, _ act: @escaping () -> Void) -> some View {
    Button(action: act) {
      Text(t).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44)
        .foregroundStyle(on ? Color.black : Color(rgb: 0xec, 0xec, 0xee))
        .background(Capsule().fill(on ? Color(rgb: 0xec, 0xec, 0xee) : Color(rgb: 0x1b, 0x1b, 0x1d).opacity(0.92)))
        .overlay(Capsule().strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
    }
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/* #tricks: the program's disciplines (each "Draw, 12 of 21") and Extra Shots, a card per shot: its difficulty and points
   ("Difficulty 7", "6 of 7"), or its number, level and stars */
struct TricksList: View {
  let go: (String) -> Void
  var body: some View {
    let sc = TrickStore.score, best = TrickStore.best
    let secs: [(String, [String])] = TRICK_PROGRAM.map { ("\($0.title), \(discTotal(sc.pts, $0.slots)) of \(discMax($0.slots))", $0.slots.compactMap { $0 }) }
      + [("Extra Shots", TRICKS.filter { trickVal($0.id) == 0 }.map(\.id))]
    List {
      Section {} footer: { Text("\(programTotal(sc.pts)) of \(programMax()) points. Three attempts a run: full value on the first, minus 1, minus 2. A shot keeps its best, and a new run can always beat it.") }
      ForEach(secs.filter { !$0.1.isEmpty }, id: \.0) { sec in
        Section(sec.0) {
          ForEach(sec.1, id: \.self) { id in
            let c = trickById(id)!, i = TRICKS.firstIndex { $0.id == id }!, val = trickVal(id)
            Button { go(id) } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(c.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                  Text(val > 0 ? "Difficulty \(val)" : "\(i + 1)" + (c.level.map { " \u{00b7} " + ($0.prefix(1).uppercased() + $0.dropFirst()) } ?? "")).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if val > 0 { Text("\(sc.pts[id] ?? 0) of \(val)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.primary) }
                else { let s = best[id] ?? 0; Text(String(repeating: "★", count: s) + String(repeating: "☆", count: 3 - s)).foregroundStyle(.primary).accessibilityLabel("\(s) of 3 stars") }
              }
              .frame(minHeight: 44)
            }
            .accessibilityHint(c.goal + (trickHint(c).isEmpty ? "" : " " + trickHint(c)))
            .accessibilityIdentifier("trick-" + id)
          }
        }
      }
    }
    .navigationTitle("Trick Shots")
  }
}

/* #trickRes: the shot's line, Made it or Not quite (Like that, Close for Show me), the words, the points or stars, then
   Try Again, Show Me (when a solution is stored) and Next (First after the last); Back to Trick Shots */
struct TrickResult: View {
  let model: TableModel
  let res: TableModel.TrickRes
  let back: () -> Void
  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      VStack(alignment: .leading, spacing: 10) {
        Text(res.kind).font(.footnote).foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline) {
          Text(res.head).font(.title2.bold())
          Spacer()
          if !res.pts.isEmpty { Text(res.pts).font(.title3.weight(.semibold)).monospacedDigit() }
        }
        Text(res.why).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        /* .btns: four to a row above 600 pt wide (min-width 600); a phone keeps its rows */
        let btns = Prefs.phone ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        btns {
          let retry = Button { model.startTrick(TRICKS[res.i].id) } label: { Text("Try Again").frame(maxWidth: .infinity, minHeight: 44) }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2))).accessibilityIdentifier("trickRetry")
          let show = Button { model.showMe() } label: { Text("Show Me").frame(maxWidth: .infinity, minHeight: 44) }
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.2))).accessibilityIdentifier("trickShow")
          let solved = model.engine.trickSol(TRICKS[res.i]) != nil
          if Prefs.phone {
            HStack(spacing: 10) { retry; if solved { show } }
          } else { retry; if solved { show } }
          Button { if res.daily { back() } else { model.startTrick(TRICKS[(res.i + 1) % TRICKS.count].id) } } label: { Text(res.daily ? "Home" : res.i == TRICKS.count - 1 ? "First" : "Next").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("trickNext")
          Button("Back to Trick Shots", action: back).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.primary)
        }
      }
      .foregroundStyle(.primary)
      .padding(20)
      .background(RoundedRectangle(cornerRadius: 24).fill(Color(rgb: 0x1c, 0x1c, 0x1e)))
      /* #trickRes .sheet: 600 at most above 600 pt wide */
      .pageCap(600)
      .padding(.horizontal, 12).padding(.bottom, 12)
    }
    .accessibilityElement(children: .contain)
  }
}

/* the drills sheet: the list (every drill with its medal and best, the medals won of all) and a page per drill (its goal,
   scoring, medals, best, the last scores, Start pinned at the foot) */
struct DrillsList: View {
  let go: (String) -> Void
  var body: some View {
    let all = DrillStore.all
    CapList {
      Section {
        ForEach(Array(DRILL_LIB.enumerated()), id: \.offset) { i, d in
          let r = all[d.id], t = r.map { drillTier(d, $0.best) } ?? 0
          NavigationLink { DrillPage(d: d, go: go) } label: {
            HStack(spacing: 12) {
              Medal(n: i + 1, tier: t)
              VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.body.weight(.semibold))
                Text(r.map { "Best \($0.best)\(t > 0 ? ", \(DRILL_TIERS[t].lowercased())" : ""). \($0.n) played" } ?? d.sub).font(.footnote).foregroundStyle(.secondary)
              }
            }.frame(minHeight: 44)
          }
          .accessibilityLabel("\(d.name): \(r.map { "best \($0.best)\(t > 0 ? ", \(DRILL_TIERS[t])" : "")" } ?? "not played yet")")
          .accessibilityIdentifier("drillRow-" + d.id)
        }
      } header: { Text("\(DRILL_LIB.count) drills, each a few shots scored from what the balls really did. Bronze, silver and gold by score: \(DrillStore.medals) of \(DRILL_LIB.count * 3) medals.").textCase(nil) }
    }
    .navigationTitle("Drills")
  }
}
/* .dmedal: the drill's number in a disc, its medal's colour once won */
struct Medal: View {
  let n: Int, tier: Int
  var body: some View {
    let c: Color = [Color(white: 0.24), Color(rgb: 0xc8, 0x84, 0x52), Color(rgb: 0xc6, 0xc8, 0xcc), Color(rgb: 0xe8, 0xc1, 0x4a)][tier]
    Text("\(n)").font(.system(size: 13, weight: .bold)).monospacedDigit().frame(width: 30, height: 30)
      .background(Circle().fill(c)).foregroundStyle(tier > 0 ? Color.black : Color.white).accessibilityHidden(true)
  }
}
struct DrillPage: View {
  let d: Drill
  let go: (String) -> Void
  var body: some View {
    let r = DrillStore.all[d.id], hist = Array((r?.hist ?? []).reversed().prefix(10))
    CapList {
      Section {
        rule("Goal", d.goal)
        rule("Scoring, \(d.shots) Shots", d.how + (d.hasOwnTotal ? "" : " Your score is the mean of the shots."))
        rule("Medals", "Bronze at \(d.tiers[0]), silver at \(d.tiers[1]), gold at \(d.tiers[2]).")
        rule("Your Best", r.map { "\($0.best) of 100\(drillTier(d, $0.best) > 0 ? ", \(DRILL_TIERS[drillTier(d, $0.best)].lowercased())" : ""), \($0.n) played." } ?? "Not played yet.")
      }
      if !hist.isEmpty {
        Section("Last Scores") {
          ForEach(Array(hist.enumerated()), id: \.offset) { _, h in
            HStack { Text("\(h.0)\(drillTier(d, h.0) > 0 ? ", \(DRILL_TIERS[drillTier(d, h.0)].lowercased())" : "")").font(.body.weight(.semibold)); Spacer(); Text(DrillStore.dayWords(h.1)).foregroundStyle(.secondary) }
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      Button { go(d.id) } label: { Text(titleCaseWords("Start \(d.name)")).font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
        .background(Capsule().fill(.white)).foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
        .accessibilityIdentifier("drillGo")
    }
    .navigationTitle(d.name)
  }
  func rule(_ h: String, _ p: String) -> some View {
    VStack(alignment: .leading, spacing: 3) { Text(h).font(.subheadline.weight(.semibold)); Text(p).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }.padding(.vertical, 2)
  }
}
/* #drillRes: "Drill: Cut Ladder", "80 of 100, silver", the best and the next medal, each shot's score, Again and Back */
struct DrillResultView: View {
  let model: TableModel
  let res: TableModel.DrillResult
  let back: () -> Void
  var body: some View {
    let d = drillById(model.drill!.id)!, js = model.drill!.js, nextT = d.tiers.first { $0 > res.total }
    VStack(spacing: 0) {
      Spacer()
      VStack(alignment: .leading, spacing: 10) {
        Text("Drill: \(d.name)").font(.footnote).foregroundStyle(.secondary)
        Text("\(res.total) of 100" + (res.tier > 0 ? ", \(DRILL_TIERS[res.tier].lowercased())" : "")).font(.title2.bold())
        Text((res.was == nil ? "Your first score on this drill." : res.total > res.was! ? "A new best, up from \(res.was!)." : "Best: \(res.was!).")
             + (nextT.map { " \(DRILL_TIERS[drillTier(d, $0)]) at \($0)." } ?? " Gold, the top medal.")).font(.subheadline).foregroundStyle(.secondary)
        /* #drillCareer */
        if let c = res.career { Text(c).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("drillCareer") }
        HStack(spacing: 6) {
          ForEach(0..<d.shots, id: \.self) { i in
            let s = i < js.count ? js[i].s : nil
            Text(s.map(String.init) ?? "-").font(.subheadline.weight(.semibold)).monospacedDigit().frame(minWidth: 36, minHeight: 30)
              .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: (s ?? 0) > 0 ? 0.26 : 0.16)))
              .foregroundStyle((s ?? 0) > 0 ? Color.primary : Color.secondary)
              .accessibilityLabel("Shot \(i + 1): \(s.map(String.init) ?? "not played")")
          }
        }
        Button { model.startDrill(d.id) } label: { Text("Again").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("drillAgain")
        Button(model.onDrillDone != nil ? "Back to Career" : "Back to Drills", action: back).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.primary)
      }
      .padding(20)
      .background(RoundedRectangle(cornerRadius: 24).fill(Color(rgb: 0x1c, 0x1c, 0x1e)))
      .pageCap(600).padding(.horizontal, 12).padding(.bottom, 12)
    }
  }
}

/* #coach: the step ("8-ball, step 2 of 4: Your group first", or "Close. Try again."), its words (a miss's why first), and
   its one button, Show Me (Next after a result shown) */
struct CoachCard: View {
  let model: TableModel
  var body: some View {
    let T = model.tut!, t = tutById(T.id)!, st = t.steps[T.step]
    VStack(alignment: .leading, spacing: 6) {
      Text(T.again ? "Close. Try again." : "\(t.name), step \(T.step + 1) of \(t.steps.count): \(st.head)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
      Text(T.then ? (st.then?.text() ?? "") : (T.again && !T.why.isEmpty ? T.why + " " : "") + st.text(T.ctx ?? "solids")).font(.subheadline).fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button { model.tutShowMe() } label: { Text(T.then ? "Next" : "Show Me").font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).disabled(model.rolling != nil || model.stroke != nil).accessibilityIdentifier("coachBtn")
      }
    }
    .foregroundStyle(.white)
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(rgb: 0x1c, 0x1c, 0x1e).opacity(0.94)))
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
    .accessibilityElement(children: .contain)
  }
}
/* #tutDone: Tutorial complete, "That's 8-ball.", the recap, Play 8-Ball, Home */
struct TutDoneView: View {
  let t: Tutorial
  let home: () -> Void
  @State private var play = false
  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      VStack(alignment: .leading, spacing: 10) {
        Text("Tutorial complete").font(.footnote).foregroundStyle(.secondary)
        Text("That's \(t.name).").font(.title2.bold())
        Text(TutStore.RECAP[t.id] ?? "").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          Button { play = true } label: { Text(titleCaseWords("Play \(t.name)")).font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("tutPlay")
          Button("Home", action: home).frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Color(white: 0.2))).foregroundStyle(.white)
        }
      }
      .foregroundStyle(.white)
      .padding(20)
      .background(RoundedRectangle(cornerRadius: 24).fill(Color(rgb: 0x1c, 0x1c, 0x1e)))
      .pageCap(440).padding(.horizontal, 12).padding(.bottom, 12)
    }
    .fullScreenCover(isPresented: $play) {
      TableScreen(model: TableModel(game: ["9": .nine, "bumper": .bumper, "carom": .carom, "snooker": .snooker, "heyball": .heyball][t.id] ?? .eight, cpu: UserDefaults.standard.string(forKey: "felt.opponent").flatMap { $0 == "two" ? nil : $0 } ?? "medium"))
    }
  }
}

/* the lesson's coach card: "Step 2 of 3: Fine-tune" (or "Close. Try again."), its sentence; no button */
struct LessonCard: View {
  let s: TableModel.LessonSession
  var body: some View {
    let st = TableModel.LESSON_STEPS[s.step - 1]
    VStack(alignment: .leading, spacing: 6) {
      Text(s.again ? "Close. Try again." : "Step \(s.step) of 3: \(st.0)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
      Text(st.1).font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(.white)
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 18).fill(Color(rgb: 0x1c, 0x1c, 0x1e).opacity(0.94)))
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(rgb: 0x3a, 0x3a, 0x41), lineWidth: 1))
    .accessibilityElement(children: .combine)
  }
}
/* the lesson's gold ring round the control to use (#coachRing) */
struct LessonRing: View {
  let on: Bool
  var body: some View {
    if on { RoundedRectangle(cornerRadius: 14).strokeBorder(Color(rgb: 0xf2, 0xc9, 0x4c), lineWidth: 2.5).padding(-4).allowsHitTesting(false) }
  }
}
/* #lessonDone: Lesson complete, You're ready., Play 8-Ball, Home */
struct LessonDoneView: View {
  let home: () -> Void
  @State private var play = false
  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      VStack(alignment: .leading, spacing: 10) {
        Text("Lesson complete").font(.footnote).foregroundStyle(.secondary)
        Text("You're ready.").font(.title2.bold())
        Text("That is the whole stroke: aim, fine-tune, pull. The rules of each game are in How to play.").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          Button { play = true } label: { Text("Play 8-Ball").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
            .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("donePlay")
          Button("Home", action: home).frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(Color(white: 0.2))).foregroundStyle(.white)
        }
      }
      .foregroundStyle(.white)
      .padding(20)
      .background(RoundedRectangle(cornerRadius: 24).fill(Color(rgb: 0x1c, 0x1c, 0x1e)))
      .pageCap(440).padding(.horizontal, 12).padding(.bottom, 12)
    }
    .fullScreenCover(isPresented: $play) { NavigationStack { GameSetup(game: .eight, go: {}) } }
  }
}

/* #callout: a pill with the moment's dot (green; on a red cloth the coral) and its name, popping in over the top of the
   cloth (12% down the stage), held, then gone: callIn's 1.25 s */
struct CalloutView: View {
  let model: TableModel
  var body: some View {
    TimelineView(.animation(paused: model.callout == nil)) { tl in
      let t = model.callout.map { tl.date.timeIntervalSinceReferenceDate - $0.at } ?? 9
      let u = t / 1.25, on = model.callout != nil && u >= 0 && u < 1
      let o = u < 0.14 ? u / 0.14 : u < 0.76 ? 1 : max(0, 1 - (u - 0.76) / 0.24)
      let sc = u < 0.14 ? 0.86 + (1.035 - 0.86) * u / 0.14 : u < 0.26 ? 1.035 - 0.035 * (u - 0.14) / 0.12 : 1
      let red = model.dress.cloth == "red"
      GeometryReader { g in
        if on, let c = model.callout {
          HStack(spacing: 8) {
            Circle().fill(red ? Color(rgb: 0xff, 0x8a, 0x7a) : Color(rgb: 0x3d, 0xdc, 0x84)).frame(width: 8, height: 8)
              .overlay(Circle().stroke((red ? Color(rgb: 0xff, 0x8a, 0x7a) : Color(rgb: 0x3d, 0xdc, 0x84)).opacity(0.26), lineWidth: 6))
            Text(c.text).font(.system(size: 16, weight: .semibold)).kerning(-0.19).foregroundStyle(Color(rgb: 0xf5, 0xf5, 0xf7)).lineLimit(1)
          }
          .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 7.5)
          .background(Capsule().fill(Color(rgb: 18, 18, 20).opacity(0.9)))
          .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
          .shadow(color: .black.opacity(0.35), radius: 15, y: 10)
          .scaleEffect(sc).opacity(o)
          .position(x: g.size.width / 2, y: g.size.height * 0.12)
          .accessibilityLabel(c.text)
        }
      }
    }
    .allowsHitTesting(false)
  }
}

/* #replayBtn and #replayBadge: the offer (an arrow and Replay, brass for a notable shot), then while one plays its badge
   (Replay, Slow motion round a moment) and Skip */
struct ReplayPill: View {
  let model: TableModel
  var body: some View {
    let brass = Color(rgb: 0xd9, 0xb2, 0x5e)
    Group {
      if model.rp != nil {
        HStack(spacing: 10) {
          HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .bold))
            Text("Replay").font(.system(size: 14, weight: .semibold))
            if model.replaySlow { Text("Slow motion").font(.system(size: 12)).foregroundStyle(.secondary) }
          }
          .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Color(rgb: 18, 18, 20).opacity(0.9)))
          Button { model.endReplay() } label: { Text("Skip").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44) }
            .background(Capsule().fill(Color(rgb: 18, 18, 20).opacity(0.9)).frame(height: 32)).accessibilityLabel("Skip the replay").accessibilityIdentifier("replaySkip")
        }
        .foregroundStyle(.white)
      } else if let o = model.offer {
        Button { model.startReplay() } label: {
          HStack(spacing: 6) {
            Image(systemName: "arrow.counterclockwise").font(.system(size: 13, weight: .bold))
            Text("Replay").font(.system(size: 14, weight: .semibold))
          }
          .padding(.horizontal, 14).frame(minHeight: 44)
          .foregroundStyle(o.notable != nil ? Color.black : Color.white)
          .background(Capsule().fill(o.notable != nil ? brass : Color(rgb: 18, 18, 20).opacity(0.9)).frame(height: 32))
        }
        .accessibilityLabel(o.notable.map { "Replay the \(momentWord($0, model.g?.kind ?? "8").lowercased())" } ?? "Replay the last shot")
        .accessibilityIdentifier("replayBtn")
      }
    }
  }
}

/* #over (showOver): the kicker ("8-ball vs Regular, 34 shots"), who won, the closing line, the winning shot's moments as
   chips (the best in the accent), and the table of numbers: snooker's score, high breaks and frames; carom's points,
   innings, average and high run; else the balls potted, the best run, accuracy, fouls and shots of note */
struct OverHead: View {
  let model: TableModel
  let g: Game
  /* a short screen lays the card out in two columns (#over .sheet's grid): the words and chips (head) apart from the numbers (stats) */
  enum Part { case all, head, stats }
  var part = Part.all
  static let NOTE_WORDS = ["bank": "Bank", "kick": "Kick", "combo": "Combo", "long": "Long pot", "double": "Double", "triple": "Triple", "cleanBreak": "Clean break", "point": "Point",
    "golden": "Golden break", "runOut": "Run out", "breakRun": "Break and run"]
  var body: some View {
    let st = model.stats, w = g.winner ?? 0, n = st.shots.reduce(0, +), np = model.party?.names.count ?? 2, P = Array(0..<np)
    let kind = g.kind == "bumper" ? "Bumper pool" : g.kind == "snooker" ? "Snooker" : g.kind == "carom" ? (g.need == 1 ? "One-cushion" : "Three-cushion") : StatWords.NAME[g.kind] ?? g.kind
    let foe = model.cpuLevel.flatMap { Rec.FOES[$0] }
    let top = st.lastP == w && g.verdict?.why != "forced" ? st.last : []
    VStack(alignment: .leading, spacing: 10) {
      if part != .stats {
        Text(kind + (foe.map { " vs \($0)" } ?? (model.exhib != nil ? ", exhibition" : "")) + ", \(n) shot\(n == 1 ? "" : "s")").font(.footnote).foregroundStyle(.secondary)
        HStack(spacing: 12) {
          /* overBallOf: the game ball for the celebration (the 8, the 9, the winner's colour at bumper pool, snooker's black,
             the winner's own cue ball at carom) */
          ballIcon(overBall(w), 40).frame(width: 40, height: 40).accessibilityHidden(true)
          Text(model.cpuLevel != nil ? (w == 0 ? "You win" : "The CPU wins") : "\(Words.nameOf(w)) wins").font(.title2.bold())
        }
        Text(Words.overLine(g)).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        if !top.isEmpty {
          HStack(spacing: 6) {
            ForEach(Array(top.enumerated()), id: \.offset) { i, k in
              Text(momentWord(k, g.kind)).font(.footnote.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(i == 0 ? Color(rgb: 0x3d, 0xdc, 0x84).opacity(0.22) : Color(white: 0.2)))
                .overlay(Capsule().strokeBorder(i == 0 ? Color(rgb: 0x3d, 0xdc, 0x84).opacity(0.7) : .clear, lineWidth: 1))
            }
          }
          .accessibilityElement(children: .combine).accessibilityLabel("Shots of the game: " + top.map { momentWord($0, g.kind) }.joined(separator: ", "))
        }
      }
      if part != .head {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
          GridRow { Text(""); ForEach(P, id: \.self) { p in Text(Words.nameOf(p)).font(.footnote.weight(p == w ? .bold : .semibold)).foregroundStyle(p == w ? .primary : .secondary) } }
          ForEach(rows(st, P), id: \.0) { r in
            GridRow {
              Text(r.0).font(.footnote).foregroundStyle(.secondary)
              ForEach(P, id: \.self) { p in
                /* the potted balls as little balls (dotEl), wrapping */
                if r.0 == "Potted", r.1[p] != "None" {
                  let ns = r.1[p].split(separator: " ").compactMap { Int($0) }
                  LazyVGrid(columns: [GridItem(.adaptive(minimum: 17), spacing: 3)], alignment: .leading, spacing: 3) {
                    ForEach(ns, id: \.self) { n in ballIcon(n, 16).frame(width: 16, height: 16) }
                  }
                  .frame(minWidth: 60, maxWidth: 120, alignment: .leading)
                  .accessibilityElement().accessibilityLabel(ns.map(String.init).joined(separator: ", "))
                } else {
                  Text(r.1[p]).font(.footnote).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                }
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  func ballIcon(_ n: Int, _ d: Double) -> Image { let (img, sc) = model.ballIcon(n, d); return Image(decorative: img, scale: sc) }
  func overBall(_ w: Int) -> Int {
    switch g.kind {
    case "bumper": w == 1 ? 31 : 21
    case "snooker": 62
    case "carom": w == 1 ? 71 : 70
    case "9": 9
    case "10": 10
    case "straight": 14
    case "rotation": 15
    default: 8
    }
  }
  func rows(_ st: TableModel.GStats, _ P: [Int]) -> [(String, [String])] {
    if g.kind == "carom", let sc = g.score, let inn = g.innings, let hi = g.high {
      return [("Points", sc.map(String.init)), ("Innings", inn.map(String.init)), ("Average", P.map { String(format: "%.2f", Double(sc[$0]) / Double(max(1, inn[$0]))) }), ("High run", hi.map(String.init))]
    }
    let acc = P.map { st.shots[$0] > 0 ? "\(Int((100 * min(1, Double(st.pots[$0]) / Double(st.shots[$0]))).rounded()))%" : "0%" }
    let fouls = ("Fouls", P.map { String(st.fouls[$0]) }), accuracy = ("Accuracy", acc)
    var notes: [String] = []
    for p in P {
      var items = MOMENTS.filter { st.notes[p][$0] != nil }.map { k in ((g.kind == "snooker" ? SNOOKER_WORDS[k] : nil) ?? OverHead.NOTE_WORDS[k] ?? k) + (st.notes[p][k]! > 1 ? " \u{00d7}\(st.notes[p][k]!)" : "") }
      if let b = st.brk, b.p == p, !b.foul, b.down == 1, st.notes[p]["golden"] == nil { items.append("1 on the break") }
      /* each item whole on its line: "Bank \u{00d7}2" never breaks */
      notes.append(items.isEmpty ? "None" : items.map { $0.replacingOccurrences(of: " ", with: "\u{00a0}") }.joined(separator: ", "))
    }
    if g.kind == "snooker" {
      let sc = g.verdict?.snk?.frameOver?.score ?? g.score ?? [0, 0]
      return [("Score", sc.map(String.init)), ("High break", (g.high ?? [0, 0]).map(String.init))] + ((g.snk?.frames ?? 1) > 1 ? [("Frames", (g.snk?.won ?? [0, 0]).map(String.init))] : []) + [accuracy, fouls] + (P.count > 2 ? [] : [("Shots of note", notes)])
    }
    let down = P.map { p -> String in
      let l = g.kind == "bumper" ? g.balls.filter { !$0.on && bOwner($0.n) == p }.map(\.n).sorted() : model.pottedBy[p]
      return l.isEmpty ? "None" : l.map(String.init).joined(separator: " ")
    }
    return [("Potted", down), ("Best run", P.map { String(st.best[$0]) })] + (model.party.map { pt in [("Racks won", pt.wins.map(String.init))] } ?? []) + [accuracy, fouls] + (P.count > 2 ? [] : [("Shots of note", notes)])
  }
}

/* the home's art: each card's picture made off the main thread for its size, once (HomeArt) */
@MainActor @Observable final class HomeArtStore {
  var img: [String: CGImage] = [:]
  var scale: CGFloat = 3
  /* the cards' height: the ninth card is a row wide and as tall as the row */
  var rowH: CGFloat? = nil
  @ObservationIgnored private var keys: [String: String] = [:]
  func want(_ g: TableGame, _ w: CGFloat, _ h: CGFloat, _ low: Double) {
    guard w > 1, h > 1 else { return }
    if g != .heyball, rowH != h { rowH = h }
    let d = Double(UIScreen.main.scale), dress = Prefs.dress(g.table.2), spec = TableModel.spec(for: g)
    let key = "\(w)x\(h) \(low) \(d) \(dress) \(spec)"
    guard keys[g.rawValue] != key else { return }
    keys[g.rawValue] = key; scale = CGFloat(d)
    Task.detached(priority: .userInitiated) {
      let im = HomeArt.paint(g, Double(w), Double(h), low: low, d: d)
      await MainActor.run { if self.keys[g.rawValue] == key, let im { withAnimation(.easeOut(duration: 0.2)) { self.img[g.rawValue] = im } } }
    }
  }
}
/* a section's title on the home (.newgame .sect) */
struct HomeSect: View {
  let title: String, top: CGFloat
  /* on its side: 20 pt, 8 under it */
  var side = false
  var body: some View { Text(title).font(.system(size: side ? 20 : 22, weight: .bold)).kerning(side ? -0.32 : -0.35).foregroundStyle(.white).padding(.top, top).padding(.bottom, side ? 8 : 10).accessibilityAddTraits(.isHeader) }
}
/* .nav: a 44 pt round glass button */
struct NavDot: View {
  let icon: String
  var body: some View {
    Image(systemName: icon).font(.system(size: 19, weight: .regular)).foregroundStyle(.white).frame(width: 44, height: 44)
      .background(Circle().fill(Color(rgb: 0x1c, 0x1c, 0x1f))).overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
  }
}
/* press: a small give and a spring back (.tile:active) */
struct Press: ButtonStyle {
  func makeBody(configuration c: Configuration) -> some View {
    c.label.scaleEffect(c.isPressed ? 0.97 : 1).animation(c.isPressed ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.55), value: c.isPressed)
  }
}
struct RowPress: ButtonStyle {
  func makeBody(configuration c: Configuration) -> some View { c.label.background(Color.white.opacity(c.isPressed ? 0.09 : 0)) }
}
/* .mode: a quiet dark card, a glow of its own colour in the corner, its mark top left, the name and line at the foot */
struct ModeCard<Mark: View>: View {
  let name: String, line: String, glow: (Double, Double, Double)
  /* --card-ar (homeCards on its side) */
  var ar: CGFloat = 1.7
  /* the career's card (the page's .cc): its container is inside its 14 pt padding, so it steps down at 212 pt */
  var cc = false
  @ViewBuilder let mark: () -> Mark
  /* the card's width: at 184 pt or less the words a size down (the page's @container (max-width: 184px)); a .mode
     keeps 12 pt round them then, the .cc its padding */
  @State private var w: CGFloat = 0
  var body: some View {
    let narrow = w > 0 && w <= (cc ? 212 : 184)
    VStack(alignment: .leading, spacing: 0) {
      mark().frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.08)))
        .padding(.top, 10).padding(.leading, 12).accessibilityHidden(true)
      Spacer(minLength: 4)
      VStack(alignment: .leading, spacing: 2) {
        Text(name).font(.system(size: narrow ? 16 : 17, weight: .semibold)).kerning(-0.2)
        Text(line).font(.system(size: narrow ? 12 : 13)).foregroundStyle(.white.opacity(0.74))
      }
      .lineLimit(1).padding(.horizontal, narrow && !cc ? 12 : 14).padding(.bottom, 12)
    }
    .foregroundStyle(.white)
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { w = $0 }
    /* one card to a row: no fixed aspect, the card its minimum (--cc-min) */
    .modifier(CardAspect(on: !HomeLayout.oneCol(), ar: ar))
    .background { ModeFace(glow: glow) }
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5))
    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}
/* a .mode card's face without its words: the ground and the glow (the morph's window carries it, 6m) */
struct ModeFace: View {
  let glow: (Double, Double, Double)
  var body: some View {
    let c = Color(red: glow.0 / 255, green: glow.1 / 255, blue: glow.2 / 255)
    GeometryReader { g in
      ZStack {
        Color(rgb: 0x17, 0x17, 0x1a)
        EllipticalGradient(colors: [c.opacity(0.15), c.opacity(0)], center: UnitPoint(x: 0.85, y: 0), startRadiusFraction: 0, endRadiusFraction: 0.6)
          .frame(width: g.size.width * 1.2 * 2, height: g.size.height * 0.9 * 2).position(x: g.size.width * 0.85, y: 0)
      }
    }
  }
}
/* .solo: a row of the Solo list: its icon (or the daily's calendar leaf), name and line, a count, a chevron; hairlines
   inset to the words */
struct SoloRow: View {
  var icon: String?, day: Int? = nil
  let name: String, line: String
  var acc: String? = nil, accIcon: String? = nil, accTint = Color(rgb: 0x3d, 0xdc, 0x84)
  /* on its side the rows are tighter: 52 pt, 12 apart, the words 16 and 12 */
  var side = false
  init(icon: String?, day: Int? = nil, name: String, line: String, acc: String? = nil, accIcon: String? = nil, accTint: Color = Color(rgb: 0x3d, 0xdc, 0x84), side: Bool = false) {
    self.icon = icon; self.day = day; self.name = name; self.line = line; self.acc = acc; self.accIcon = accIcon; self.accTint = accTint; self.side = side
  }
  var body: some View {
    HStack(spacing: side ? 12 : 14) {
      Group {
        if let day {
          VStack(spacing: 0) {
            Color(rgb: 0x3d, 0xdc, 0x84).frame(height: 8)
            Text("\(day)").font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(.white).frame(maxHeight: .infinity)
          }
          .background(Color(white: 0.17)).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if let icon {
          Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Color(rgb: 0x3d, 0xdc, 0x84))
            .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
        }
      }
      .frame(width: 32, height: 32).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(name).font(.system(size: side ? 16 : 17, weight: .medium)).foregroundStyle(.white)
        Text(line).font(.system(size: side ? 12 : 13)).foregroundStyle(Color(white: 0.92).opacity(0.66))
      }
      /* Large and Larger text: the words wrap rather than cut off (.solo :is(b, small) white-space: normal); the count
         beside them keeps to one line */
      .lineLimit(Prefs.int("text", 100) > 100 ? nil : 1)
      .fixedSize(horizontal: false, vertical: Prefs.int("text", 100) > 100)
      /* .tt flex: 1 in a 14 px gap: the words fill the row (a Spacer between was a second 14 pt gap) */
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)
      if let acc {
        HStack(spacing: 5) {
          if let accIcon { Image(systemName: accIcon).font(.system(size: 13)).foregroundStyle(accTint) }
          Text(acc).monospacedDigit().lineLimit(1).fixedSize()
        }
        .font(.system(size: 15)).foregroundStyle(Color(white: 0.92).opacity(0.66))
      }
      Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.92).opacity(0.3))
    }
    .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, side ? 6 : 8)
    .frame(maxWidth: .infinity, minHeight: side ? 52 : 60, alignment: .leading)
    .contentShape(Rectangle())
    .overlay(alignment: .top) { Color.white.opacity(0.16).frame(height: 0.5).padding(.leading, side ? 60 : 62) }
  }
}

/* the page's CSS zoom on the sheets (data-text 115, 130): laid out at the size over z, then scaled by z from the top
   left, so words, rows and gaps all grow and the content still fills the screen; 1 is the view itself */
struct Zoomed: ViewModifier {
  let z: CGFloat
  func body(content: Content) -> some View {
    if z == 1 { content }
    else {
      GeometryReader { g in
        content.frame(width: g.size.width / z, height: g.size.height / z).scaleEffect(z, anchor: .topLeading)
      }
    }
  }
}

/* the home's media rules for the text size: Large on a phone 400 pt wide or less, Larger on one 500 pt or less, upright:
   one card to a row, no fixed aspect (game cards 84 pt, modes --cc-min 92 pt) */
enum HomeLayout {
  @MainActor static func oneCol(_ text: Int = Prefs.int("text", 100)) -> Bool {
    let b = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds ?? .zero
    return b.height > b.width && ((text == 115 && b.width <= 400) || (text == 130 && b.width <= 500))
  }
  /* @media (orientation: landscape) and (min-width: 560px): the home on its side, from the window's size in points */
  static func side(_ s: CGSize) -> Bool { s.width > s.height && s.width >= 560 }
  @MainActor static func window() -> UIWindow? { UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first }
  /* `-felt-homelayout`: the home's frames printed once it has settled (a test hook, the page's getBoundingClientRect) */
  static let probeOn = ProcessInfo.processInfo.arguments.contains("-felt-homelayout")
  @MainActor static var probe: [String: CGRect] = [:]
}
extension View {
  func homeProbe(_ k: String) -> some View {
    onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { r in if HomeLayout.probeOn { HomeLayout.probe[k] = r } }
  }
}
struct CardAspect: ViewModifier {
  let on: Bool
  var ar: CGFloat = 1.7
  func body(content: Content) -> some View { if on { content.aspectRatio(ar, contentMode: .fit) } else { content.frame(height: 92) } }
}

/* the table's frame clock: a CADisplayLink asking for the display's full rate (120 Hz on ProMotion; SwiftUI's
   TimelineView(.animation) held the table at 60 on the phone), the date read as TimelineView's context gives it */
struct LinkTick { let date: Date }
@MainActor @Observable final class FrameClock {
  var t = Date.timeIntervalSinceReferenceDate
  @ObservationIgnored private var link: CADisplayLink?
  @ObservationIgnored private lazy var proxy = Proxy(self)
  private final class Proxy: NSObject {
    weak var c: FrameClock?
    init(_ c: FrameClock) { self.c = c }
    @MainActor @objc func step(_ l: CADisplayLink) { c?.t = Date.timeIntervalSinceReferenceDate }
  }
  func run(_ on: Bool) {
    if on, link == nil {
      let l = CADisplayLink(target: proxy, selector: #selector(Proxy.step(_:)))
      l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
      l.add(to: .main, forMode: .common); link = l
    } else if !on { link?.invalidate(); link = nil }
  }
}
struct LinkTimeline<Content: View>: View {
  let paused: Bool
  @ViewBuilder let content: (LinkTick) -> Content
  @State private var clock = FrameClock()
  var body: some View {
    content(LinkTick(date: Date(timeIntervalSinceReferenceDate: clock.t)))
      .onAppear { clock.run(!paused) }
      .onChange(of: paused) { _, p in clock.run(!p) }
      .onDisappear { clock.run(false) }
  }
}

/* the window's chrome while a table is open (TableScreen counts itself in and out) */
/* the pointer's presses (an iPad's mouse or trackpad; UIApplicationSupportsIndirectInputEvents makes them indirectPointer
   touches): a watcher on the window notes each press's kind as it begins and then fails at once, so it never delays,
   cancels or competes with the table's DragGesture (a gesture waiting to begin held back every drag event to the lift,
   2026-11-15); a secondary click (a right click) is a tap of its own, the table's letGoAim */
@MainActor final class PointerWatch: UIGestureRecognizer, UIGestureRecognizerDelegate {
  static var pointer = false, secondary = false
  static var onSecondary: (() -> Void)?
  static func install() {
    guard let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
          !(w.gestureRecognizers ?? []).contains(where: { $0 is PointerWatch }) else { return }
    let p = PointerWatch(target: nil, action: nil)
    p.cancelsTouchesInView = false; p.delaysTouchesBegan = false; p.delaysTouchesEnded = false; p.delegate = p
    w.addGestureRecognizer(p)
    let r = UITapGestureRecognizer(target: p, action: #selector(rightClick))
    r.buttonMaskRequired = .secondary; r.cancelsTouchesInView = false; r.delaysTouchesEnded = false; r.delegate = p
    w.addGestureRecognizer(r)
  }
  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    PointerWatch.pointer = touches.contains { $0.type == .indirectPointer }
    PointerWatch.secondary = PointerWatch.pointer && event.buttonMask.contains(.secondary)
    state = .failed
  }
  @objc private func rightClick() { PointerWatch.onSecondary?() }
  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}

@MainActor @Observable final class Chrome {
  static let shared = Chrome()
  var atTable = 0
  static let noFocus = ProcessInfo.processInfo.arguments.contains("-felt-nofocus")
  static let noDefer = ProcessInfo.processInfo.arguments.contains("-felt-nodefer")
  /* UIKit re-reads the edges only when told: tell every controller from the root to the table's cover */
  static func refresh() {
    guard var vc = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
    while true {
      vc.setNeedsUpdateOfScreenEdgesDeferringSystemGestures(); vc.setNeedsUpdateOfHomeIndicatorAutoHidden()
      guard let p = vc.presentedViewController else { break }
      vc = p
    }
  }
  static func printEdges() {
    guard let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first, var vc = w.rootViewController else { print("felt-edges no window"); return }
    var out = ["root \(vc.preferredScreenEdgesDeferringSystemGestures.rawValue) hidden \(vc.prefersHomeIndicatorAutoHidden)"]
    while let p = vc.presentedViewController { vc = p; out.append("presented \(type(of: p)) \(p.preferredScreenEdgesDeferringSystemGestures.rawValue) hidden \(p.prefersHomeIndicatorAutoHidden)") }
    print("felt-edges " + out.joined(separator: "; "))
  }
}

/* a test hook: `-felt-touchlog` writes the real gesture's events, the aim after each, and each drawn frame's aim and
   cue ball to tmp/touchlog.txt (read back by the UI tests) */
@MainActor enum TouchLog {
  static let on = ProcessInfo.processInfo.arguments.contains("-felt-touchlog")
  static var lines: [String] = []
  static func add(_ l: @autoclosure () -> String) {
    guard on else { return }
    lines.append(String(format: "%.4f ", Date.timeIntervalSinceReferenceDate) + l())
    if lines.count % 50 == 0 { flush() }
  }
  static func flush() {
    guard on else { return }
    try? lines.joined(separator: "\n").write(to: FileManager.default.temporaryDirectory.appendingPathComponent("touchlog.txt"), atomically: true, encoding: .utf8)
  }
}

/* the 3D camera's pinch as a UIKit recognizer: recognised beside every other gesture, touches never delayed or cancelled */
struct PinchRecognizer: UIGestureRecognizerRepresentable {
  let on: Bool
  let act: (UIGestureRecognizer.State, CGFloat) -> Void
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
  }
  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
  func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
    let g = UIPinchGestureRecognizer()
    g.cancelsTouchesInView = false; g.delaysTouchesBegan = false; g.delaysTouchesEnded = false
    g.delegate = context.coordinator
    return g
  }
  func updateUIGestureRecognizer(_ g: UIPinchGestureRecognizer, context: Context) { g.isEnabled = on }
  func handleUIGestureRecognizerAction(_ g: UIPinchGestureRecognizer, context: Context) { act(g.state, g.scale) }
}
