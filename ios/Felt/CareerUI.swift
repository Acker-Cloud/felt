/* the career's screens (page section 6d, on the ported engine, CareerEngine): the slots (continue, delete, a new
   career), then the hub: where the player stands, the next match (played on the table under the event's rules, or
   simulated), time moved a week, the events open to enter, offers, the news. The engine's store (the page's
   localStorage keys and values) is kept in a file in Application Support, written as each key changes. */
import FeltRender
import FeltSim
import SwiftUI

@MainActor @Observable final class CareerStore {
  let E = CareerEngine()
  var rev = 0
  var msg = ""
  private let url: URL = {
    let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d.appendingPathComponent("career-store.json")
  }()
  init() {
    if let d = try? Data(contentsOf: url), let o = try? JSONDecoder().decode([String: String].self, from: d) { E.store = o }
    E.persist = { [weak self] _, _ in self?.flush() }
    /* a test hook: `-felt-career-demo` starts a fresh career (seed 31337) and moves it to its first match */
    if ProcessInfo.processInfo.arguments.contains("-felt-career-demo") {
      E.store = [:]
      /* `-felt-career-pro`: the same player started as a pro (a test hook) */
      let start = ProcessInfo.processInfo.arguments.contains("-felt-career-pro") ? "pro" : "amateur"
      _ = E.create(["name": "Ada Demo", "nat": "GB", "disc": "9", "style": "potter", "difficulty": "medium", "start": .str(start), "age": 28], seed: 31337)
      for _ in 0..<12 {
        let day = E.S["day"]!.i
        if let ev = E.S["cal"]!.a.first(where: { $0["start"]!.i > day && E.eligibility($0).isEmpty }) { E.enter(ev["id"]!.s) }
        if E.advance(week: true) == "match" { break }
      }
      /* `-felt-career-forfeit1`: the first match forfeited, so no match is due (a test hook) */
      if ProcessInfo.processInfo.arguments.contains("-felt-career-forfeit1") { E.reportMatch(CareerEngine.MatchReport(forfeit: true)) }
      /* `-felt-career-accept1`: the first offer accepted after any play-on (a test hook) */
      defer { if ProcessInfo.processInfo.arguments.contains("-felt-career-accept1"), let id = E.S["off"]?.a.first?["id"]?.str { E.accept(id) } }
      /* `-felt-career-retire`: retired at once (after any steps on: see below) */
      defer { if ProcessInfo.processInfo.arguments.contains("-felt-career-retire") { E.retire() } }
      /* `-felt-career-rivals`: 40 steps on (a due match simulated, else an eligible event entered and a week) */
      if ProcessInfo.processInfo.arguments.contains("-felt-career-rivals") {
        /* `-felt-career-steps N` sets the count (a test hook) */
        let n = UserDefaults.standard.integer(forKey: "felt-career-steps")
        for _ in 0..<(n > 0 ? n : 40) {
          if E.nextMatch() != .null { E.simMatch(); continue }
          let day = E.S["day"]!.i
          if let ev = E.S["cal"]!.a.first(where: { $0["start"]!.i > day && E.eligibility($0).isEmpty }) { E.enter(ev["id"]!.s) }
          E.advance(week: true)
        }
      }
      return
    }
    if let id = E.listSlots().first(where: { $0["active"] == true && $0["status"] != "corrupt" })?["id"]?.str { E.load(id) }
  }
  /* the career's practice session (cvSave after Career.practice): the result's words */
  func practice(_ id: String, _ score: Int) -> String {
    let r = E.practice(id, score)
    guard r["ok"] == true else { return "Not recorded in your career: \(r["why"]?.str ?? "").".replacingOccurrences(of: "..", with: ".") }
    E.save(); touch()
    let ms = r["milestone"]?.str
    return "Recorded in your career\(ms.map { ": \($0) mastery" } ?? ""). Best there \(r["mastery"]?["best"]?.i ?? score)."
  }
  /* calendar().practiceToday */
  var practiceToday: Int { let me = E.S["me"]!; return me["pdDay"] == E.S["day"] ? (me["pd"]?.i ?? 0) : 0 }
  private func flush() { if let d = try? JSONEncoder().encode(E.store) { try? d.write(to: url, options: .atomic) } }
  var loaded: Bool { E.S != .null }
  /* noteLookOwn: every item a career owns unlocks its look anywhere (Settings' My Look) */
  func touch() { rev &+= 1; if loaded { Prefs.noteLookOwn(E.S["inv"]?["own"]?.a.compactMap { $0.str } ?? []) } }
  static func T(_ k: String) -> JV { CareerEngine.const(k) }
  static func gameName(_ d: String) -> String { T("GAMES")[d]?["name"]?.str ?? d }
  static func game(_ d: String) -> TableGame? { ["8": .eight, "9": .nine, "10": .ten, "straight": .straight, "rotation": .rotation, "heyball": .heyball, "snooker": .snooker, "carom": .carom, "bumper": .bumper][d] }

  /* careerPlay: the next match's terms for the table (careerTerms): the opponent's level and personality, the lag,
     the event's ruleset (CAREER_RULES), calls and table */
  func match() -> (game: TableGame, tm: TableModel.TMatch)? {
    let nm = E.nextMatch()
    guard nm != .null, let r = nm["rules"], let d = r["game"]?.str, let g = Self.game(d) else { return nil }
    let CR = ["8-bar": "8-house", "8-league": "8-house", "8-wpa": "8-wpa", "9-bar": "9-house", "9-wpa": "9-wpa", "10-wpa": "10-wpa", "14.1-wpa": "straight-wpa", "rotation-61": "rotation", "heyball-masters": "heyball"]
    let req = r["call"]?["require"]?.str ?? "official"
    var c = CallConfig()
    c.mode = req == "8ball" ? "off" : req == "off" ? "off" : req == "all" ? "all" : "official"
    c.eight = req == "8ball"
    c.detail = ["ball", "pocket", "rails", "strict"].contains(r["call"]?["detail"]?.str ?? "") ? r["call"]!["detail"]!.s : "pocket"
    let table = r["table"]?.str ?? "9"
    let spec: (table: String, shape: String?, pockets: String) = switch d {
    case "snooker": ("snooker", table == "full" ? "full" : "compact", "regulation")
    case "carom": ("carom", nil, "regulation")
    case "bumper": ("bumper", "octagon", "regulation")
    case "heyball": ("heyball", nil, "regulation")
    default: (table == "9" ? "9" : "7", nil, r["pockets"]?.str == "generous" ? "generous" : "regulation")
    }
    let race = nm["race"]!.i, pts = d == "straight" || d == "carom"
    var tm = TableModel.TMatch(m: nm["match"]!.i, foe: nm["opponent"]!["name"]!.s, level: nm["level"]!.s, arch: nm["ai"]?["arch"]?.str, need: pts ? 1 : race, points: pts, race: race,
                               lag: nm["breaker"]!.i, ruleset: CR[r["ruleset"]!.s] ?? DEFAULT_RULESET[d] ?? "8-house")
    tm.call = c; tm.spec = spec; tm.career = true
    /* career.assist and career.seed (careerPlay): the skills' caps and jitter unless simulation purity is on */
    let a = E.assist()
    tm.assist = truthy(a["purity"]) ? nil : a
    tm.execSeed = CareerLib.seedOf([E.S["id"]?.str ?? "", nm["event"]!.s, String(nm["match"]!.i), "exec"])
    /* lookCareer: the career's equipped items, by slot ('cloth-grey' is CLOTH grey), in the hall */
    let eq = E.equipped(), key = { (s: String) -> String in String((eq[s]?.str ?? "").split(separator: "-", maxSplits: 1).last ?? "") }
    let st = Dress.standard
    tm.dress = Dress(cloth: TableLook.CLOTH[key("cloth")] != nil ? key("cloth") : st.cloth, cue: Dress.ORDER["cue"]!.contains(key("cue")) ? key("cue") : st.cue,
                     chalk: Dress.CHALK[key("chalk")] != nil ? key("chalk") : st.chalk, rail: TableLook.RAILS[key("rail")] != nil ? key("rail") : st.rail,
                     balls: Dress.ORDER["balls"]!.contains(key("balls")) ? key("balls") : st.balls, room: "hall")
    return (g, tm)
  }
  /* the table's result: the score against the race, or a forfeit (leaving the match) */
  func report(_ mine: Int, _ theirs: Int, _ forfeit: Bool) {
    let before = E.nextMatch()
    let why = E.reportMatch(CareerEngine.MatchReport(score: forfeit ? nil : [mine, theirs], forfeit: forfeit))
    let foe = before["opponent"]?["name"]?.str ?? "your opponent"
    msg = why ?? (forfeit ? "Forfeit: the match against \(foe) counts as a loss." : mine > theirs ? "You beat \(foe) \(mine)-\(theirs)." : "\(foe) beat you \(theirs)-\(mine).")
    touch()
  }
}

struct CareerView: View {
  @Bindable var store: CareerStore
  @State private var playing: PlayTerms? = nil
  @State private var page: String? = nil
  @State private var drillPlay: String? = nil
  struct PlayTerms: Identifiable { let id = UUID(); let game: TableGame; let tm: TableModel.TMatch?; var drill: String? = nil }
  var body: some View {
    Group {
      if store.loaded { CareerHub(store: store, play: { if let m = store.match() { playing = PlayTerms(game: m.game, tm: m.tm) } }, onPractice: { page = "practice" }) }
      else { CareerSlots(store: store) }
    }
    /* the hub carries its own header (the season over the name); the slots keep the bar's title */
    .navigationTitle(store.loaded ? "" : "Career")
    /* a test hook: `-felt-career-play` opens the next match on the table */
    .navigationDestination(item: $page) { p in
      switch p { case "stats": CareerStats(store: store); case "shop": CareerShop(store: store); case "sponsors": CareerSponsors(store: store)
      case "practice": CareerPractice(store: store) { drillPlay = $0 }
      default: CareerRankings(store: store) }
    }
    /* a test hook: `-felt-career-page rankings|stats|shop|sponsors` opens that page */
    .onAppear { let a = ProcessInfo.processInfo.arguments; if let i = a.firstIndex(of: "-felt-career-page"), i + 1 < a.count, page == nil { page = a[i + 1] } }
    .onAppear { if ProcessInfo.processInfo.arguments.contains("-felt-career-play"), playing == nil, let m = store.match() { playing = PlayTerms(game: m.game, tm: m.tm) } }
    /* a test hook: `-felt-career-drill id` plays that drill as the career's practice */
    .onAppear { let a = ProcessInfo.processInfo.arguments; if let i = a.firstIndex(of: "-felt-career-drill"), i + 1 < a.count, drillPlay == nil, store.loaded { drillPlay = a[i + 1] } }
    .fullScreenCover(item: Binding(get: { drillPlay.map { PlayTerms(game: .nine, tm: nil, drill: $0) } }, set: { if $0 == nil { drillPlay = nil } })) { p in
      TableScreen(model: { let m = TableModel(game: .nine, drill: p.drill); m.onDrillDone = { id, total in store.practice(id, total) }; return m }())
    }
    .fullScreenCover(item: $playing) { p in
      TableScreen(model: { let m = TableModel(game: p.game, match: p.tm!); m.onReport = { _, a, b, f in store.report(a, b, f) }; return m }())
    }
  }
}

/* the slots: each career's row (season, week, tier), continue or delete; a new career's profile */
struct CareerSlots: View {
  @Bindable var store: CareerStore
  @State private var name = ""
  @State private var disc = "9"
  @State private var style = "allround"
  @State private var difficulty = "medium"
  @State private var start = "amateur"
  @State private var confirmDelete: String? = nil
  var body: some View {
    let _ = store.rev
    List {
      let slots = store.E.listSlots()
      if !slots.isEmpty {
        Section("Your Careers") {
          ForEach(slots.indices, id: \.self) { i in
            let s = slots[i], id = s["id"]!.s
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(s["name"]!.s).font(.body)
                Text("Season \(s["season"]!.i), week \(s["week"]!.i), \(s["tierName"]!.s)\(s["status"]?.str == "ok" ? "" : ", \(s["status"]!.s)")").font(.footnote).foregroundStyle(.secondary)
              }
              Spacer()
              Button(confirmDelete == id ? "Confirm" : "Delete", role: .destructive) {
                if confirmDelete == id { store.E.deleteSlot(id); confirmDelete = nil; store.touch() } else { confirmDelete = id }
              }.buttonStyle(.borderless)
              Button("Continue") { store.E.load(id); store.touch() }.buttonStyle(.borderless).foregroundStyle(.white).bold()
                .disabled(s["status"]?.str == "corrupt")
            }
          }
        }
      }
      Section("New Career") {
        TextField("Name", text: $name).textInputAutocapitalization(.words)
        Picker("Best Game", selection: $disc) { ForEach(CareerStore.T("DISCS").a.map { $0.s }, id: \.self) { Text(titleCase(CareerStore.gameName($0))).tag($0) } }
        Picker("Style", selection: $style) { ForEach(CareerStore.T("STYLES").keys, id: \.self) { Text(titleCase(CareerStore.T("STYLES")[$0]?["name"]?.str ?? $0)).tag($0) } }
        Picker("Difficulty", selection: $difficulty) { ForEach(CareerStore.T("DIFFS").keys, id: \.self) { Text($0.capitalized).tag($0) } }
        Picker("Start As", selection: $start) { ForEach(CareerStore.T("STARTS").keys, id: \.self) { Text($0.capitalized).tag($0) } }
      }
      Section {
        Button("Start Career") {
          let pr: JV = ["name": .str(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Player" : name), "nat": "US", "disc": .str(disc), "style": .str(style), "difficulty": .str(difficulty), "start": .str(start), "age": 25]
          let r = store.E.create(pr)
          store.msg = r.ok ? "" : "No free slot: delete a career first."
          store.touch()
        }
        .font(.headline).frame(maxWidth: .infinity, minHeight: 50).background(Capsule().fill(.white)).foregroundStyle(.black).listRowBackground(Color.clear)
        .accessibilityIdentifier("career-start")
        if !store.msg.isEmpty { Text(store.msg).font(.footnote).foregroundStyle(.secondary) }
      }
    }
  }
  /* Title Case, the page's titleCase: each word's first letter, after a space or a hyphen ("9-Ball") */
  func titleCase(_ s: String) -> String {
    var out = "", up = true
    for ch in s { out += up ? ch.uppercased() : String(ch); up = ch == " " || ch == "-" }
    return out
  }
}

/* the hub: the player's standing, the next match, a week ahead, events to enter, offers, the news */
/* PAGES.hub's top: the player's card (#cvMe: the avatar, name and line, Credits, Rating and Titles, the season's bar) and
   the Next Match card (#cvNext: the table's banner, the event and a round tag, the opponent's avatar, name and line, the
   match's lines: Game, Rules, Race, Break, Opponent, Head to head, Odds; Play Match, Forfeit This Match) */
@MainActor enum CareerWords {
  static func natName(_ id: String) -> String { CareerData.NAT.first { $0.id == id }?.name ?? id }
  static func crWords(_ n: Double) -> String { let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US"); return "\(f.string(from: NSNumber(value: n.rounded())) ?? "0") cr" }
  static func unitWords(_ kind: String, _ n: Int) -> String { TourneyRun.unitWords(kind, n) }
  static func tableWords(_ r: JV) -> String {
    let g = r["game"]?.str ?? ""
    if g == "heyball" { return "9 ft table, snooker pockets" }
    if g == "snooker" { return r["table"]?.str == "full" ? "12 ft table" : "10 ft table" }
    if g == "carom" { return "10 ft carom table" }
    if g == "bumper" { return "Octagon bumper table" }
    return "\(r["table"].map { $0.str ?? String($0.i) } ?? "7") ft table, \(r["pockets"]?.str ?? "regulation") pockets"
  }
  static let CALL_WORDS = ["off": "no calls", "8ball": "call the 8", "official": "official calls", "all": "call every shot"]
  static let DETAIL_WORDS = ["ball": "the ball", "pocket": "ball and pocket", "rails": "ball, pocket and rails", "strict": "strict"]
  static func rulesWords(_ r: JV) -> String {
    let label = CareerStore.T("RULESETS")[r["ruleset"]?.str ?? ""]?["label"]?.str ?? CareerStore.gameName(r["game"]?.str ?? "")
    let req = r["call"]?["require"]?.str ?? "official"
    return "\(label), \(CALL_WORDS[req] ?? "official calls")" + (req != "off" ? " (\(DETAIL_WORDS[r["call"]?["detail"]?.str ?? ""] ?? "ball and pocket"))" : "")
  }
  /* avatarEl: initials on the avatar's colour, else the page's fallback (AV_COLS by hashStr of the name) */
  static func avatar(_ name: String, _ av: JV?, _ d: CGFloat = 46) -> some View {
    let col = av?["col"]?.str ?? TourneyRun.AV_COLS[Int(TourneyRun.hashStr(name) % UInt32(TourneyRun.AV_COLS.count))]
    let ini = av?["ini"]?.str ?? name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined()
    return Text(ini).font(.system(size: d * 0.37, weight: .bold)).foregroundStyle(.white).frame(width: d, height: d).background(Circle().fill(css(col))).accessibilityHidden(true)
  }
}
struct CareerHubTop: View {
  @Bindable var store: CareerStore
  let play: () -> Void
  @State private var forfeit = false
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, me = S["me"]!, pr = S["profile"]!, tier = me["tier"]!.i, day = S["day"]!.i, week = day % CareerEngine.const("YEAR").i / 7 + 1
    let tierName = CareerStore.T("TIERS")[tier]!["name"]!.s, nm = E.nextMatch(), titles = E.stats()["all"]?["titles"]?.i ?? 0
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Season \(E.season), week \(week)").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
        Text(pr["name"]!.s).font(.system(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
      }
      .padding(.leading, 4)
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 12) {
          CareerWords.avatar(pr["name"]!.s, pr["avatar"])
          VStack(alignment: .leading, spacing: 1) {
            Text(pr["name"]!.s + (pr["nick"]?.str.flatMap { $0.isEmpty ? nil : " \"\($0)\"" } ?? "")).font(.system(size: 17, weight: .semibold))
            Text("\(tierName), tier \(tier). \(CareerWords.natName(pr["nat"]!.s)), \(CareerStore.gameName(pr["disc"]!.s))").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
          }
        }
        HStack(alignment: .top) {
          fact("Credits", CareerWords.crWords(me["money"]!.d)); fact("Rating", "\(me["fr"]?.i ?? 0)"); fact("Titles", "\(titles)")
        }
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.12))
            Capsule().fill(Color(rgb: 0x3d, 0xdc, 0x84)).frame(width: g.size.width * CGFloat(min(52, week)) / 52)
          }
        }
        .frame(height: 4).accessibilityHidden(true)
      }
      .padding(16).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
      if nm != .null {
        let o = nm["opponent"]!, r = nm["rules"]!, g = r["game"]!.s, h = nm["h2h"]!.a, fr = nm["fr"]!
        ModeField("Next Match") {
          VStack(alignment: .leading, spacing: 12) {
            if let tg = TourneyView.game(g) { HeroView(game: tg, txt: 0).frame(height: 170).clipped().allowsHitTesting(false) }
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text(nm["eventName"]!.s).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.7)).lineLimit(1)
                Spacer()
                Text(nm["round"]!.s).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.white.opacity(0.1)))
              }
              HStack(spacing: 12) {
                CareerWords.avatar(o["name"]!.s, o["avatar"])
                VStack(alignment: .leading, spacing: 1) {
                  Text(o["name"]!.s + (o["nick"]?.str.flatMap { $0.isEmpty ? nil : " \"\($0)\"" } ?? "")).font(.system(size: 17, weight: .semibold))
                  Text("\(CareerWords.natName(o["nat"]!.s)), \(o["archName"]?.str ?? ""), rating \(o["rating"]?.i ?? 0)").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
                }
              }
              VStack(spacing: 6) {
                line("Game", "\(CareerStore.gameName(g)), \(CareerWords.tableWords(r))")
                line("Rules", CareerWords.rulesWords(r))
                line("Race", "First to \(CareerWords.unitWords(g, nm["race"]!.i))")
                line("Break", g == "bumper" || g == "carom" ? "You open" : nm["breaker"]!.i == 0 ? "You break first" : "\(o["name"]!.s.split(separator: " ").first ?? "") breaks first")
                line("Opponent", "Tier \(o["tier"]?.i ?? 0), plays as the \(nm["level"]!.s) CPU")
                line("Head to Head", "\(h.first?.i ?? 0)-\(h.count > 1 ? h[1].i : 0)")
                line("Odds", "\(Int((100 * fr["odds"]!.d).rounded()))% by performance rating, \(fr["me"]?.i ?? 0) to \(fr["opp"]?.i ?? 0)")
                if let c = r["custom"]?.str { line("Format", c) }
              }
              Button(action: play) { Text("Play Match").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
                .background(Capsule().fill(.white)).foregroundStyle(.black).accessibilityIdentifier("career-play")
              Button {
                if forfeit { forfeit = false; store.report(0, 0, true) } else { forfeit = true; Task { try? await Task.sleep(for: .seconds(4)); forfeit = false } }
              } label: {
                Text(forfeit ? "Tap again to forfeit" : "Forfeit This Match").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50)
                  .foregroundStyle(forfeit ? Color.white : Color(rgb: 0xff, 0x8a, 0x7a))
                  .background(Capsule().fill(forfeit ? Color(rgb: 0xc0, 0x39, 0x2b) : Color(rgb: 0x2c, 0x2c, 0x30)))
              }
            }
            .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, TourneyView.game(g) == nil ? 16 : 0)
          }
          .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
      }
    }
  }
  private func fact(_ k: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
      Text(v).font(.system(size: 17, weight: .bold)).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  private func line(_ k: String, _ v: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(k).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
      Spacer(minLength: 12)
      Text(v).multilineTextAlignment(.trailing)
    }
    .font(.system(size: 15))
  }
}

/* PAGES.hub's groups: Season (Calendar, Rankings, Tour Card), You (Stats and Records, Sponsors and Offers, Shop, Practice
   Drills, News), Career (Switch Career, Retire), each row its name and the page's line. The page's Bracket and
   Standings, Rivals and Options rows are not here: those pages are not ported yet. */
/* PAGES.bracket: with no event, the season's entered events (newest first: the week and format, Under way, Over or
   Not drawn); with one, Final Placings (the top eight, and you after them), the standings (each group, or the round
   robin's table: W-L), Your Matches, then every round (each side, the winner bold, you in the accent; the score or the
   week) */
struct CareerBracket: View {
  @Bindable var store: CareerStore
  var id: String? = nil
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, H = CareerEngine.HUMAN
    if let id {
      let ev = S["cal"]!.a.first { $0["id"]!.s == id }, b = E.bracket(id)
      List {
        if let ev {
          Section {
            VStack(alignment: .leading, spacing: 2) {
              Text(CareerStore.T("FORMATS")[ev["fmt"]!.s]?.str ?? "").font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
              /* a non-breaking hyphen keeps "9-Ball" on one line */
              Text(ev["name"]!.s.replacingOccurrences(of: "-", with: "\u{2011}")).font(.system(size: 28, weight: .bold)).accessibilityLabel(ev["name"]!.s).accessibilityAddTraits(.isHeader)
            }
            .padding(.top, 6).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)).listRowBackground(Color.clear)
          }
        }
        if ev == nil || b == nil { Section { Text("This event is no longer on the calendar.").foregroundStyle(.secondary) } }
        else if let b, !b.drawn { Section { Text("The draw is made when the event starts, in week \(b.week).").foregroundStyle(.secondary) } }
        else if let b {
          let name = { (p: Int?) -> String in p.map { b.field.contains($0) ? E.cardOf($0)["name"]!.s : "To come" } ?? "To come" }
          if let pl = b.placings {
            let me: [Int]? = pl.first { $0[0] == H }
            let tail: [[Int]] = me.map { $0[1] > 8 ? [$0] : [] } ?? []
            let rows: [[Int]] = Array(pl.prefix(8)) + tail
            Section { ForEach(Array(rows.enumerated()), id: \.offset) { _, p in rankRow(p[1], name(p[0]), me: p[0] == H) } } header: { head("Final Placings") }
          }
          if let tables = E.standings(id) {
            ForEach(Array(tables.enumerated()), id: \.offset) { _, g in
              let title: String = g.group.map { "Group \($0)" } ?? "Standings"
              Section { ForEach(Array(g.rows.enumerated()), id: \.offset) { i, r in standRow(i + 1, r, name) } } header: { head(title) }
            }
          }
          let mine = b.matches.filter { $0.o.a == H || $0.o.b == H }
          if !mine.isEmpty { Section { ForEach(mine, id: \.m) { bm($0, name) } } header: { head("Your Matches") }.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)) }
          let rounds = b.matches.reduce(into: [String]()) { if !$0.contains($1.round) { $0.append($1.round) } }
          ForEach(rounds, id: \.self) { r in Section { ForEach(b.matches.filter { $0.round == r }, id: \.m) { bm($0, name) } }
            header: { head(titleCaseWords(r)) }.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)) }
        }
      }
      .environment(\.defaultMinListRowHeight, 44)
      .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    } else {
      let es = S["es"]!, fm = CareerStore.T("FORMATS")
      let evs = S["cal"]!.a.filter { truthy(es[$0["id"]!.s]?["en"]) }.reversed()
      List {
        if evs.isEmpty { Section { Text("Enter an event from the calendar; its draw shows here when it starts.").foregroundStyle(.secondary) } }
        else {
          Section {
            ForEach(Array(evs.enumerated()), id: \.offset) { _, ev in
              let e = es[ev["id"]!.s]!, st = truthy(e["x"]) ? "" : truthy(e["done"]) ? "Over" : e["f"] != nil ? "Under way" : "Not drawn"
              NavigationLink { CareerBracket(store: store, id: ev["id"]!.s) } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 1) {
                    Text(ev["name"]!.s).font(.system(size: 17))
                    Text("Week \(E.weekOfDay(ev["start"]!.i)), \(fm[ev["fmt"]!.s]?.str ?? "")").font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
                  }
                  Spacer()
                  Text(st).font(.system(size: 15)).foregroundStyle(.secondary)
                }
              }
            }
          }
          .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        }
      }
      .navigationTitle("Brackets").navigationBarTitleDisplayMode(.inline)
    }
  }
  private func head(_ t: String) -> some View { Text(t).font(.system(size: 13)).foregroundStyle(.secondary).textCase(nil) }
  private func rankRow(_ rk: Int, _ t: String, me: Bool, val: String? = nil) -> some View {
    HStack(spacing: 12) {
      Text("\(rk)").font(.system(size: 15, weight: .bold)).monospacedDigit().frame(width: 28)
      Text(t).font(.system(size: 17, weight: me ? .bold : .regular))
      Spacer()
      if let val { Text(val).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit() }
    }
  }
  private func standRow(_ i: Int, _ r: CareerLib.Row, _ name: (Int?) -> String) -> some View {
    rankRow(i, name(r.p), me: r.p == CareerEngine.HUMAN, val: "\(r.w)-\(r.l)")
  }
  /* bm: a match's two sides about its score, or the week it is played */
  private func bm(_ m: CareerEngine.BracketMatch, _ name: @escaping (Int?) -> String) -> some View {
    let H = CareerEngine.HUMAN, o = m.o
    let side = { (p: Int?, trail: Bool) -> AnyView in
      let win = o.w != nil && o.w == p
      return AnyView(Text(p == nil ? "To come" : name(p)).font(.system(size: 15, weight: win ? .bold : .regular))
        .foregroundStyle(p == H ? Color(rgb: 0x3d, 0xdc, 0x84) : win ? Color.white : Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.75))
        .lineLimit(1).frame(maxWidth: .infinity, alignment: trail ? .trailing : .leading))
    }
    return HStack(spacing: 8) {
      side(o.a, false)
      Text(o.s.map { "\($0[0])-\($0[1])" } ?? "wk \(store.E.weekOfDay(m.day))").font(.system(size: 15, weight: .bold)).monospacedDigit().fixedSize()
      side(o.b, true)
    }
  }
}

/* PAGES.rivals: Rivalry Objectives (the open ones, each its words and pay), then the rivals (won and lost, finals, at
   the hill; the streak), each opening the player's page */
struct CareerRivals: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, rv = E.rivals(), obj = E.S["obj"]!.a.filter { !truthy($0["done"]) }
    List {
      CareerTitle(kick: "Career", title: "Rivals")
      if !obj.isEmpty {
        Section {
          ForEach(Array(obj.enumerated()), id: \.offset) { _, o in
            HStack(alignment: .firstTextBaseline) {
              Text(o["text"]?.str ?? "").font(.system(size: 17)).fixedSize(horizontal: false, vertical: true)
              Spacer(minLength: 12)
              Text(CareerWords.crWords(o["pay"]?.d ?? 0)).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit()
            }
          }
        } header: { CareerPageHead(t: "Rivalry Objectives") }
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
      }
      Section {
        if rv.isEmpty { Text("Rivals come from meeting the same players again: finals, upsets and close matches count most.").font(.system(size: 15)).foregroundStyle(.secondary) }
        ForEach(Array(rv.enumerated()), id: \.offset) { _, r in
          let fw = r["finalsWon"]!.i, fl = r["finalsLost"]!.i, cl = r["close"]!.i, st = r["streak"]!.i
          NavigationLink { CareerPlayer(store: store, id: r["id"]!.i) } label: {
            HStack {
              VStack(alignment: .leading, spacing: 1) {
                Text(r["name"]!.s).font(.system(size: 17))
                Text("Won \(r["won"]!.i), lost \(r["lost"]!.i)" + (fw + fl > 0 ? ", finals \(fw)-\(fl)" : "") + (cl > 0 ? ", \(cl) at the hill" : ""))
                  .font(.system(size: 15)).foregroundStyle(.secondary).lineLimit(1)
              }
              Spacer()
              Text(st > 0 ? "W\(st)" : st < 0 ? "L\(-st)" : "").font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit()
            }
          }
        }
      } header: { CareerPageHead(t: "Rivals") }
      .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
    .environment(\.defaultMinListRowHeight, 44)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
}
/* setHead(kick, title): the page's kicker over its large title, as the list's first row */
struct CareerTitle: View {
  let kick: String, title: String
  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 2) {
        Text(kick).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
        Text(title.replacingOccurrences(of: "-", with: "\u{2011}")).font(.system(size: 28, weight: .bold)).accessibilityLabel(title).accessibilityAddTraits(.isHeader)
      }
      .padding(.top, 6).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)).listRowBackground(Color.clear)
    }
  }
}
struct CareerPageHead: View {
  let t: String
  var body: some View { Text(t).font(.system(size: 13)).foregroundStyle(.secondary).textCase(nil) }
}
/* PAGES.player: the card (avatar, name and nickname, nation, town and age; Rating, Tier, Titles; Plays, As a CPU,
   Record), Head to Head (matches, finals, upsets), Attributes (each a value over its meter) */
struct CareerPlayer: View {
  @Bindable var store: CareerStore
  let id: Int
  var body: some View {
    let _ = store.rev
    let E = store.E, p = E.player(id), h = E.headToHead(id), names = CareerStore.T("ATTR_NAMES")
    let dim = Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)
    List {
      CareerTitle(kick: p == .null ? "Player" : p["archName"]?.str ?? "Player", title: p == .null ? "Not Found" : p["name"]!.s)
      if p == .null { Section { Text("No such player.").foregroundStyle(.secondary) } }
      else {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
              CareerWords.avatar(p["name"]!.s, p["avatar"])
              VStack(alignment: .leading, spacing: 1) {
                Text(p["name"]!.s + (p["nick"]?.str.flatMap { $0.isEmpty ? nil : " \"\($0)\"" } ?? "")).font(.system(size: 17, weight: .semibold))
                Text("\(CareerWords.natName(p["nat"]!.s)), \(p["town"]?.str ?? ""), age \(p["age"]?.i ?? 0)").font(.system(size: 13)).foregroundStyle(dim)
              }
            }
            HStack(alignment: .top) { fact("Rating", "\(p["rating"]?.i ?? 0)"); fact("Tier", "\(p["tier"]?.i ?? 0)"); fact("Titles", "\(p["titles"]?.i ?? 0)") }
            VStack(spacing: 6) {
              line("Plays", "\(CareerStore.gameName(p["disc"]?.str ?? "")), \(p["hand"]?.str ?? "") handed")
              line("As a CPU", p["ai"]?["level"]?.str ?? "-")
              line("Record", "\(p["w"]?.i ?? 0)-\(p["l"]?.i ?? 0)")
            }
          }
          .padding(.vertical, 6)
        }
        if h != .null {
          Section {
            row("Matches", "\(h["won"]!.i)-\(h["lost"]!.i)")
            row("Finals", "\(h["finalsWon"]!.i)-\(h["finalsLost"]!.i)")
            HStack {
              VStack(alignment: .leading, spacing: 1) {
                Text("Upsets").font(.system(size: 17))
                Text("You beat a stronger player / a weaker one beat you").font(.system(size: 15)).foregroundStyle(.secondary)
              }
              Spacer()
              Text("\(h["upsets"]!.i) / \(h["upsetBy"]!.i)").font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit()
            }
          } header: { CareerPageHead(t: "Head to Head") }
          .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        }
        Section {
          ForEach(CareerData.ATTRS, id: \.self) { k in
            let v = p["attrs"]?[k]?.i ?? 0
            HStack {
              Text(names[k]?.str ?? k).font(.system(size: 17))
              Spacer()
              VStack(alignment: .trailing, spacing: 3) {
                Text("\(v)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                ZStack(alignment: .leading) {
                  Capsule().fill(Color.white.opacity(0.12))
                  Capsule().fill(Color(rgb: 0x3d, 0xdc, 0x84)).frame(width: 96 * CGFloat(min(100, max(0, v))) / 100)
                }
                .frame(width: 96, height: 4)
              }
              .accessibilityElement(children: .ignore).accessibilityLabel("\(v) of 100")
            }
          }
        } header: { CareerPageHead(t: "Attributes") }
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
      }
    }
    .environment(\.defaultMinListRowHeight, 44)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
  private func fact(_ k: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
      Text(v).font(.system(size: 17, weight: .bold)).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  private func line(_ k: String, _ v: String) -> some View {
    HStack { Text(k).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)); Spacer(); Text(v) }.font(.system(size: 15))
  }
  private func row(_ k: String, _ v: String) -> some View {
    HStack { Text(k).font(.system(size: 17)); Spacer(); Text(v).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit() }
  }
}

/* PAGES.options: Difficulty over Options; Play (Simulation Purity, Execution Variance); What Your Skills Change Now (with
   purity: nothing; else the guide's cap, auto aim, and each jitter from Career.assist()); the page's closing note */
struct CareerOptions: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, o = E.S["me"]!["opt"]!, a = E.assist(), diff = E.S["profile"]?["difficulty"]?.str ?? "medium"
    List {
      CareerTitle(kick: "Difficulty: \(diff)", title: "Options")
      Section {
        toggle("Simulation Purity", "Skills are a record only: your shots are exactly yours", truthy(o["purity"]), "cvPurity") { E.setOptions(purity: $0) }
        toggle("Execution Variance", "Without purity: a little jitter on your shots from your skills", truthy(o["variance"]), "cvVariance") { E.setOptions(variance: $0) }
      } header: { CareerPageHead(t: "Play") }
      .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
      Section {
        if truthy(a["purity"]) {
          Text("Nothing: the physics, the guide and auto aim are as in any game, from your settings.").font(.system(size: 15)).foregroundStyle(.secondary)
        } else {
          row("Guide", "Capped by position play", ["none": "Off", "short": "Short", "long": "Full"][a["guide"]?.str ?? ""] ?? "")
          row("Auto Aim", "Needs tactics 40", truthy(a["autoAim"]) ? "Allowed" : "Off")
          row("Aim Jitter", nil, String(format: "%.2f deg", a["aimNoise"]!.d * 180 / .pi))
          row("Power Jitter", nil, String(format: "%.1f%%", a["powerNoise"]!.d * 100))
          row("Break Power Jitter", nil, String(format: "%.1f%%", a["breakNoise"]!.d * 100))
          row("Tip Jitter", nil, String(format: "%.1f%%", a["spinNoise"]!.d * 100))
          row("On the Hill", "Jitter multiplier, from pressure", "x\(JV.numberString(a["hillNoise"]!.d))")
        }
      } header: { CareerPageHead(t: "What Your Skills Change Now") } footer: {
        Text("The bank guide and the safety hint the engine allows are not drawn on this table yet. Nothing here ever changes the physics or the CPU.").font(.system(size: 13))
      }
      .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
    .environment(\.defaultMinListRowHeight, 44)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
  private func toggle(_ t: String, _ sub: String, _ on: Bool, _ id: String, _ set: @escaping (Bool) -> Void) -> some View {
    Toggle(isOn: Binding(get: { on }, set: { set($0); store.E.save(); store.touch() })) {
      VStack(alignment: .leading, spacing: 1) {
        Text(t).font(.system(size: 17))
        Text(sub).font(.system(size: 15)).foregroundStyle(.secondary)
      }
    }
    .tint(Color(rgb: 0x34, 0xc7, 0x59)).accessibilityIdentifier(id)
  }
  private func row(_ t: String, _ sub: String?, _ v: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(t).font(.system(size: 17))
        if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary) }
      }
      Spacer()
      Text(v).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit()
    }
  }
}

/* PAGES.records: Personal Bests (the longest winning run, the biggest upset, the longest match, the ladder), Your
   Titles (newest first), Seasons (newest first: W-L, titles and prize; Promoted, Relegated or the tier), Hall of
   Fame, Most Titles (you in bold) */
struct CareerRecords: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, r = E.records(), p = r["personal"]!, H = CareerEngine.HUMAN
    let nm = { (id: Int) -> String in id == H ? "You" : E.player(id)["name"]?.str ?? "A player" }
    let ins = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
    List {
      CareerTitle(kick: "Career", title: "Records")
      Section {
        row("Longest Winning Run", nil, p["streak"].map { "\($0[0]!.i) (season \($0[1]!.i))" } ?? "None yet")
        row("Biggest Upset", p["upset"].map { "\(nm($0[1]!.i)), \($0[3]?.str ?? "")" }, p["upset"].map { "\($0[0]!.i) rating points" } ?? "None yet")
        row("Longest Match", p["longest"].map { "\(nm($0[1]!.i)), \($0[3]?.str ?? "")" }, p["longest"].map { "\($0[0]!.i) racks" } ?? "None yet")
        if let l = p["ladder"] { row("Ladder", nil, "\(l[0]!.i) of \(l[1]!.i) beaten") }
      } header: { CareerPageHead(t: "Personal Bests") }
      .listRowInsets(ins)
      Section {
        let t = r["titles"]!.a.reversed()
        if t.isEmpty { note("No titles yet.") }
        ForEach(Array(t.enumerated()), id: \.offset) { _, x in row(x["name"]!.s, "Season \(x["season"]!.i), tier \(x["tier"]!.i)", nil) }
      } header: { CareerPageHead(t: "Your Titles") }
      .listRowInsets(ins)
      if !r["seasons"]!.a.isEmpty {
        Section {
          ForEach(Array(r["seasons"]!.a.reversed().enumerated()), id: \.offset) { _, x in
            let t0 = x["t0"]!.i, t1 = x["t1"]!.i, ti = x["ti"]!.i
            row("Season \(x["s"]!.i)", "\(x["w"]!.i)-\(x["l"]!.i), \(ti) title\(ti == 1 ? "" : "s"), \(CareerWords.crWords(x["prize"]!.d))", t1 > t0 ? "Promoted" : t1 < t0 ? "Relegated" : "Tier \(t1)")
          }
        } header: { CareerPageHead(t: "Seasons") }
        .listRowInsets(ins)
      }
      Section {
        let h = r["hallOfFame"]!.a
        if h.isEmpty { note("Nobody yet: a legacy of \(CareerEngine.const("HOF_LEG").i) gets you in. Titles weigh their tier squared by their prestige.") }
        ForEach(Array(h.enumerated()), id: \.offset) { _, x in row(x["name"]!.s, "Inducted season \(x["season"]!.i)", "\(x["legacy"]!.i) legacy", me: x["id"]!.i == H) }
      } header: { CareerPageHead(t: "Hall of Fame") }
      .listRowInsets(ins)
      if !r["titleLeaders"]!.a.isEmpty {
        Section {
          ForEach(Array(r["titleLeaders"]!.a.enumerated()), id: \.offset) { _, x in row(x["name"]!.s, nil, "\(x["titles"]!.i)", me: x["id"]!.i == H) }
        } header: { CareerPageHead(t: "Most Titles") }
        .listRowInsets(ins)
      }
    }
    .environment(\.defaultMinListRowHeight, 44)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
  /* cvNoteEl: plain words under the head, not a cell */
  private func note(_ t: String) -> some View { Text(t).font(.system(size: 13)).foregroundStyle(.secondary).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)) }
  private func row(_ t: String, _ sub: String?, _ v: String?, me: Bool = false) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(t).font(.system(size: 17, weight: me ? .bold : .regular))
        if let sub, !sub.isEmpty { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary) }
      }
      Spacer()
      if let v { Text(v).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit() }
    }
  }
}

/* PAGES.recap: Retired over the name; the card (Seasons, Matches, Titles; Peak Tier, Prize Money, Legacy); the Hall of
   Fame note; Titles; Best Rankings; Your Careers */
struct CareerRecap: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let r = store.E.S["recap"] ?? .null, ins = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
    List {
      CareerTitle(kick: "Retired", title: r == .null ? "Recap" : r["name"]!.s)
      if r == .null { Section { Text("This career has not ended.").foregroundStyle(.secondary) } }
      else {
        Section {
          VStack(spacing: 12) {
            HStack(alignment: .top) { fact("Seasons", "\(r["seasons"]!.i)"); fact("Matches", "\(r["won"]!.i)-\(r["lost"]!.i)"); fact("Titles", "\(r["titles"]!.a.count)") }
            HStack(alignment: .top) { fact("Peak Tier", "\(r["peakTier"]!.i)"); fact("Prize Money", CareerWords.crWords(r["prize"]!.d)); fact("Legacy", "\(r["legacy"]!.i)") }
          }
          .padding(.vertical, 6)
        }
        if truthy(r["hallOfFame"]) { Section { Text("Inducted into the Hall of Fame.").font(.system(size: 13)).foregroundStyle(.secondary).listRowBackground(Color.clear) } }
        Section {
          let t = r["titles"]!.a
          if t.isEmpty { Text("No titles.").font(.system(size: 13)).foregroundStyle(.secondary).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)) }
          ForEach(Array(t.enumerated()), id: \.offset) { _, x in
            VStack(alignment: .leading, spacing: 1) {
              Text(x["name"]!.s).font(.system(size: 17))
              Text("Season \(x["season"]!.i), tier \(x["tier"]!.i)").font(.system(size: 15)).foregroundStyle(.secondary)
            }
          }
        } header: { CareerPageHead(t: "Titles") }
        .listRowInsets(ins)
        let br = r["bestRanks"]!.keys
        if !br.isEmpty {
          Section {
            ForEach(br, id: \.self) { k in
              HStack { Text(k.prefix(1).uppercased() + k.dropFirst()).font(.system(size: 17)); Spacer(); Text("number \(r["bestRanks"]![k]!.i)").font(.system(size: 15)).foregroundStyle(.secondary) }
            }
          } header: { CareerPageHead(t: "Best Rankings") }
          .listRowInsets(ins)
        }
        Section {
          Button { store.E.save(); store.E.S = .null; store.touch() } label: {
            Text("Your Careers").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(.white)
              .background(Capsule().fill(Color(rgb: 0x2c, 0x2c, 0x30)))
          }
          .buttonStyle(.plain).accessibilityIdentifier("cvToSlots")
        }
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
    }
    .environment(\.defaultMinListRowHeight, 44)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
  private func fact(_ k: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
      Text(v).font(.system(size: 17, weight: .bold)).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
/* the hub of a retired career: the Retired group (Career Recap, Stats and Records, News, Switch Career) and its note */
struct CareerRetired: View {
  @Bindable var store: CareerStore
  var body: some View {
    let hof = truthy(store.E.S["me"]?["hof"])
    Section {
      NavigationLink { CareerRecap(store: store) } label: { two("Career Recap", hof ? "Hall of Fame" : "Your career in numbers") }
      NavigationLink { CareerStats(store: store) } label: { two("Stats and Records", nil) }
      NavigationLink { CareerNews(store: store) } label: { two("News", nil) }
      Button { store.E.save(); store.E.S = .null; store.touch() } label: { HStack { two("Switch Career", nil); Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(uiColor: .tertiaryLabel)) } }.tint(.primary)
    } header: { CareerPageHead(t: "Retired") } footer: {
      Text("A retired career is read only. Start a new one from Switch career.").font(.system(size: 13))
    }
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
  }
  private func two(_ t: String, _ sub: String?) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(t).font(.system(size: 17)).foregroundStyle(.primary)
        if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary) }
      }
      Spacer()
    }
    .frame(minHeight: 44)
  }
}

/* the hub's This Week card (no match due): what is under way or next, else none entered; Advance a Week, and To My Next
   Match (to the event's start, or the week while one is under way) or Calendar. cvAdvance's words: the match day or
   the season and week, then up to three news lines since */
struct CareerThisWeek: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, es = S["es"]!
    let sched = S["cal"]!.a.filter { truthy(es[$0["id"]!.s]?["en"]) && !truthy(es[$0["id"]!.s]?["done"]) }
    let live = sched.first { es[$0["id"]!.s]?["f"] != nil && !truthy(es[$0["id"]!.s]?["x"]) }
    let nx = sched.first { es[$0["id"]!.s]?["f"] == nil && !truthy(es[$0["id"]!.s]?["x"]) }
    Section {
      VStack(alignment: .leading, spacing: 12) {
        Text(live.map { "\($0["name"]!.s) is under way: your next match comes as the draw reaches it." }
             ?? nx.map { "Next: \($0["name"]!.s), week \(E.weekOfDay($0["start"]!.i))." } ?? "You have not entered an event. Pick one from the calendar.")
          .font(.system(size: 15)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
          Button { go(week: true) } label: { cap("Advance a Week", primary: true) }.buttonStyle(.plain).accessibilityIdentifier("career-week")
          if nx != nil || live != nil {
            Button { if live != nil { go(week: true) } else { go(event: true) } } label: { cap("To My Next Match", primary: false) }.buttonStyle(.plain).accessibilityIdentifier("cvToEvent")
          } else {
            NavigationLink { CareerCalendar(store: store) } label: { cap("Calendar", primary: false) }.buttonStyle(.plain).accessibilityIdentifier("cvCalBtn")
          }
        }
      }
      .padding(.vertical, 6)
    } header: { CareerPageHead(t: "This Week") }
  }
  private func go(week: Bool = false, event: Bool = false) {
    let E = store.E, from = E.S["day"]!.i
    if truthy(E.S["me"]?["ret"]) { store.msg = "This career is over."; store.touch(); return }
    let stop = event ? E.advance(toEvent: true) : E.advance(week: true)
    E.save()
    let fresh = E.S["news"]!.a.filter { $0[0]!.i > from }.map { $0[1]!.s }.suffix(3)
    let nm = E.nextMatch()
    let said = stop == "match" && nm != .null ? "Match day: \(nm["round"]!.s) of \(nm["eventName"]!.s), against \(nm["opponent"]!["name"]!.s)." : "Season \(E.season), week \(E.weekOfDay(E.S["day"]!.i))."
    store.msg = ([said] + fresh).joined(separator: " ")
    store.touch()
  }
  private func cap(_ t: String, primary: Bool) -> some View {
    Text(t).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: 50)
      .foregroundStyle(primary ? Color.black : Color.white)
      .background(Capsule().fill(primary ? Color.white : Color(rgb: 0x2c, 0x2c, 0x30)))
  }
}

struct CareerHubGroups: View {
  @Bindable var store: CareerStore
  var onPractice: () -> Void
  var onRetire: () -> Void = {}
  @State private var retiring = false
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, me = S["me"]!, tier = me["tier"]!.i, day = S["day"]!.i
    let es = S["es"]!
    let entered = S["cal"]!.a.filter { ev in es[ev["id"]!.s].map { truthy($0["en"]) && !truthy($0["done"]) } ?? false }.count
    let open = S["cal"]!.a.filter { ev in day <= (ev["dl"]?.i ?? 0) && !(es[ev["id"]!.s].map { truthy($0["en"]) } ?? false) && ev["opp"] == nil && E.eligibility(ev).isEmpty }.count
    let circ = CareerStore.T("TIERS")[tier]!["circ"]!.i, circs = CareerStore.T("CIRCUITS").a.map { $0.s }, circNames = CareerStore.T("CIRC_NAMES").a.map { $0.s }
    let rk = E.rankings(circs[circ], top: 400).a.first { $0["human"] == true }
    let st = E.stats()["all"] ?? .null, offers = S["off"]!.a.count, sponsors = S["spons"]!.a.filter { !truthy($0["end"]) }.count
    /* the page's cur: the event under way, else the first entered */
    let sched = S["cal"]!.a.filter { ev in es[ev["id"]!.s].map { truthy($0["en"]) && !truthy($0["done"]) } ?? false }
    let cur = sched.first { es[$0["id"]!.s]?["f"] != nil && !truthy(es[$0["id"]!.s]?["x"]) } ?? sched.first
    let news = S["news"]!.a.last.map { $0[1]?.str ?? "Nothing yet" } ?? "Nothing yet"
    Section {
      NavigationLink { CareerCalendar(store: store) } label: { row("Calendar", "\(open) event\(open == 1 ? "" : "s") open to you, \(entered) entered") }
      NavigationLink { CareerBracket(store: store, id: cur?["id"]?.str) } label: { row("Bracket and Standings", cur?["name"]?.str ?? "Your events, once drawn") }
      NavigationLink { CareerRankings(store: store) } label: { row("Rankings", rk.map { "\(circNames[circ]): number \($0["rank"]!.i), \($0["pts"]!.i) points" } ?? "Unranked so far") }
      row("Tour Card", tourLine(E, tier))
    } header: { head("Season") }
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    Section {
      NavigationLink { CareerStats(store: store) } label: { row("Stats and Records", "\(st["won"]?.i ?? 0) won of \(st["matches"]?.i ?? 0)") }
      NavigationLink { CareerRivals(store: store) } label: { row("Rivals", "Head to head") }
      NavigationLink { CareerSponsors(store: store) } label: { row("Sponsors and Offers", "\(sponsors) contract(s)", val: offers > 0 ? "\(offers) new" : nil) }
      NavigationLink { CareerShop(store: store) } label: { row("Shop", "Cosmetics only", val: CareerWords.crWords(me["money"]!.d)) }
      Button(action: onPractice) { row("Practice Drills", "\(store.practiceToday) of 3 sessions today", chevron: true) }.tint(.primary).accessibilityIdentifier("cvPractice")
      NavigationLink { CareerNews(store: store) } label: { row("News", news) }
    } header: { head("You") }
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    Section {
      NavigationLink { CareerOptions(store: store) } label: { row("Options", truthy(me["opt"]?["purity"]) ? "Simulation purity on" : "Skills shape your play") }
      Button { store.E.save(); store.E.S = .null; store.touch() } label: { row("Switch Career", "Your careers, a new one", chevron: true) }.tint(.primary)
      Button {
        if retiring { retiring = false; store.E.retire(); store.touch(); onRetire() } else { retiring = true; Task { try? await Task.sleep(for: .seconds(4)); retiring = false } }
      } label: { row(retiring ? "Tap again to retire" : "Retire", "End this career, see the recap", warn: true, chevron: true) }
    } header: { head("Career") }
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
  }
  /* the page's Tour Card line: the money list from tier 8, the card won, the qualifier a step from a card tier */
  private func tourLine(_ E: CareerEngine, _ tier: Int) -> String {
    let keep = CareerEngine.const("CARD_KEEP").i, mr = E.moneyRank(), card = E.S["me"]!["card"]?.i ?? 0
    if tier >= 8 && tier < 12 { return mr > 0 ? "Money list: number \(mr). The top \(keep) keep their cards" : "Earn on the money list: the top \(keep) keep their cards" }
    if card > 0 { return "Tier \(card) card won" }
    return tier == 7 || tier == 9 ? "The step up needs a card: win the qualifier" : "Not needed yet"
  }
  private func head(_ t: String) -> some View { Text(t).font(.system(size: 13)).foregroundStyle(.secondary).textCase(nil) }
  private func row(_ t: String, _ sub: String, val: String? = nil, warn: Bool = false, chevron: Bool = false) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(t).font(.system(size: 17)).foregroundStyle(warn ? Color(rgb: 0xff, 0x8a, 0x7a) : Color.primary)
        Text(sub).font(.system(size: 15)).foregroundStyle(Color.secondary).lineLimit(1)
      }
      Spacer()
      if let val { Text(val).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit() }
      /* a button row that opens a page wears the link's chevron, as the page's cvRow */
      if chevron { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(uiColor: .tertiaryLabel)) }
    }
    .frame(minHeight: 44)
  }
}

/* PAGES.calendar: the season and week over Calendar; Open to You (the events you can enter now), Entered, All (the
   season, each still taking entries with its eligibility); each row its week, name, game, kind and tier (and why
   not, when not eligible), and its state or cost; the page's note */
struct CareerCalendar: View {
  @Bindable var store: CareerStore
  @State private var tab = "open"
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, day = S["day"]!.i, es = S["es"]!
    let views = S["cal"]!.a.map { E.evView($0) }
    let avail = S["cal"]!.a.filter { day <= $0["dl"]!.i && !truthy(es[$0["id"]!.s]?["en"]) && $0["opp"] == nil }.map { $0["id"]!.s }
    let list: [JV] = tab == "open" ? views.filter { avail.contains($0["id"]!.s) && E.eligibility($0).isEmpty }
      : tab == "entered" ? views.filter { truthy(es[$0["id"]!.s]?["en"]) && !truthy(es[$0["id"]!.s]?["done"]) }
      : views.filter { $0["status"]!.s != "cancelled" }
    List {
      CareerTitle(kick: "Season \(E.season), week \(E.weekOfDay(day))", title: "Calendar")
      Section {
        Picker("Show", selection: $tab) { Text("Open to You").tag("open"); Text("Entered").tag("entered"); Text("All").tag("all") }
          .pickerStyle(.segmented).labelsHidden()
      }
      .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      Section {
        if list.isEmpty {
          Text(tab == "entered" ? "Nothing entered. Events open to you are under Open to You."
               : tab == "open" && !avail.isEmpty ? "Nothing you can enter right now. All lists the season, and what each event needs." : "No events left this season. Advance to the next season from the hub.")
            .font(.system(size: 15)).foregroundStyle(.secondary)
        }
        ForEach(Array(list.enumerated()), id: \.offset) { _, e in
          let id = e["id"]!.s, isAvail = avail.contains(id), why = isAvail ? E.eligibility(e) : [], st = e["status"]!.s
          let val = st == "entered" ? "Entered" : st == "live" ? "Under way" : st == "done" ? "Over" : st == "closed" ? "Closed"
            : isAvail ? (why.isEmpty ? CareerWords.crWords(e["fee"]!.d + e["trav"]!.d) : "Not eligible") : CareerWords.crWords(e["fee"]!.d + e["trav"]!.d)
          NavigationLink { CareerEvent(store: store, id: id) } label: {
            HStack(spacing: 12) {
              VStack(spacing: 0) {
                Text("Wk").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("\(e["week"]!.i)").font(.system(size: 17, weight: .bold)).monospacedDigit()
              }
              .frame(width: 34)
              VStack(alignment: .leading, spacing: 1) {
                Text(e["name"]!.s.replacingOccurrences(of: "-", with: "\u{2011}")).font(.system(size: 17)).fixedSize(horizontal: false, vertical: true).accessibilityLabel(e["name"]!.s)
                Text("\(e["game"]!.s), \(e["kindName"]!.s), tier \(e["tier"]!.i)" + (why.isEmpty ? "" : ". \(why[0].prefix(1).uppercased() + why[0].dropFirst())"))
                  .font(.system(size: 15)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
              }
              Spacer(minLength: 8)
              Text(val).font(.system(size: 15, weight: truthy(e["entered"]) ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(truthy(e["entered"]) ? Color(rgb: 0x3d, 0xdc, 0x84) : !why.isEmpty ? Color(rgb: 0xff, 0x8a, 0x7a) : Color.secondary)
            }
          }
          .accessibilityIdentifier("ev-" + id.replacingOccurrences(of: ".", with: "-"))
        }
      } footer: {
        Text("Entry fees come back if you withdraw before the deadline; travel does not. Weeks 51 and 52 are the off-season.").font(.system(size: 13))
      }
      .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
    .environment(\.defaultMinListRowHeight, 44)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
}

/* PAGES.event: the kind and tier over the name; the card's lines (Where, When, Entries close, Format, Game, Rules, Race,
   Custom, Entry, Purse, Ranking points, Last champion, Status); Enter (or why you cannot), Withdraw, Bracket and
   Standings */
struct CareerEvent: View {
  @Bindable var store: CareerStore
  let id: String
  var body: some View {
    let _ = store.rev
    let E = store.E, ev = E.S["cal"]!.a.first { $0["id"]!.s == id }
    List {
      if let ev {
        let e = E.evView(ev), why = E.eligibility(ev), st = e["status"]!.s, r = e["rules"]!
        let wk = { (d: String) in E.weekOfDay(e[d]!.i) }
        CareerTitle(kick: "\(e["kindName"]!.s), tier \(e["tier"]!.i)", title: e["name"]!.s)
        if !store.msg.isEmpty { Section { Text(store.msg).font(.system(size: 15)) } }
        Section {
          VStack(spacing: 6) {
            line("Where", "\(e["venue"]?.str ?? ""), \(e["city"]?.str ?? "")")
            line("When", wk("start") == wk("end") ? "Week \(wk("start"))" : "Weeks \(wk("start")) to \(wk("end"))")
            line("Entries Close", "Week \(wk("dl"))")
            line("Format", "\(e["fmtName"]!.s), \(e["size"]!.i) players")
            line("Game", "\(e["game"]!.s), \(CareerWords.tableWords(r))")
            line("Rules", CareerWords.rulesWords(r))
            line("Race", "First to \(CareerWords.unitWords(e["disc"]!.s, e["race"]!.i))")
            if let c = r["custom"]?.str { line("Custom", c) }
            line("Entry", "\(CareerWords.crWords(e["fee"]!.d)) fee, \(CareerWords.crWords(e["trav"]!.d)) travel")
            line("Purse", CareerWords.crWords(e["purse"]?.d ?? 0))
            line("Ranking Points", (e["pts"]?.d ?? 0) > 0 ? "\(e["pts"]!.i) to the winner, \(e["circuit"]!.s)" : "None")
            if let ch = e["champion"], ch != .null { line("Last Champion", "\(ch["name"]!.s) (season \(ch["season"]!.i))" + (truthy(e["defending"]) ? ", you defend" : "")) }
            line("Status", ["open": "Open for entries", "closed": "Entries closed", "entered": "Entered", "live": "Under way", "done": "Over", "cancelled": "Cancelled"][st] ?? st)
          }
          .padding(.vertical, 6)
        }
        if !truthy(e["live"]) { Section { Text("\(e["game"]!.s) matches cannot be played on this table yet: yours are settled by the match model, and shown as simulated.").font(.system(size: 15)).foregroundStyle(.secondary) } }
        if st == "open" && !truthy(e["entered"]) {
          if why.isEmpty {
            Section {
              act("Enter, \(CareerWords.crWords(e["fee"]!.d + e["trav"]!.d))", "cvEnter", primary: true) {
                let no = E.enter(id)
                store.msg = no.isEmpty ? "Entered \(e["name"]!.s): \(CareerWords.crWords(e["fee"]!.d + e["trav"]!.d)) paid." : "Not entered: \(no.joined(separator: ", "))."
                E.save(); store.touch()
              }
            }
            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
          } else {
            Section { ForEach(why, id: \.self) { w in Text(w.prefix(1).uppercased() + w.dropFirst()).font(.system(size: 17)) } } header: { CareerPageHead(t: "Why You Cannot Enter") }
          }
        }
        if truthy(e["entered"]) && st == "entered" {
          Section {
            act("Withdraw", "cvWithdraw", warn: true) {
              let no = E.withdraw(id)
              store.msg = no == nil ? "Withdrawn: the \(CareerWords.crWords(e["fee"]!.d)) fee is back, the travel is not." : "Cannot withdraw: \(no!)."
              E.save(); store.touch()
            }
          } footer: { Text("Before the deadline the fee comes back; the travel does not.").font(.system(size: 13)) }
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
        if st == "live" || st == "done" {
          Section {
            NavigationLink { CareerBracket(store: store, id: id) } label: { Text("Bracket and Standings").font(.headline).frame(maxWidth: .infinity) }
              .accessibilityIdentifier("cvSeeBracket")
          }
        }
      } else {
        CareerTitle(kick: "Event", title: "Not Found")
        Section { Text("This event is no longer on the calendar.").foregroundStyle(.secondary) }
      }
    }
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    .onDisappear { store.msg = "" }
  }
  private func line(_ k: String, _ v: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(k).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
      Spacer(minLength: 12)
      Text(v).multilineTextAlignment(.trailing)
    }
    .font(.system(size: 15))
  }
  private func act(_ t: String, _ id: String, primary: Bool = false, warn: Bool = false, _ go: @escaping () -> Void) -> some View {
    Button(action: go) {
      Text(t).font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50)
        .foregroundStyle(primary ? Color.black : warn ? Color(rgb: 0xff, 0x8a, 0x7a) : Color.white)
        .background(Capsule().fill(primary ? Color.white : Color(rgb: 0x2c, 0x2c, 0x30)))
    }
    .buttonStyle(.plain).accessibilityIdentifier(id)
  }
}

/* PAGES.news: the career's news, newest first, each with its week */
struct CareerNews: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let Y = CareerEngine.const("YEAR").i
    List {
      ForEach(Array(store.E.S["news"]!.a.reversed().enumerated()), id: \.offset) { _, n in
        VStack(alignment: .leading, spacing: 2) {
          Text("Season \((n[0]?.i ?? 0) / Y + 1), week \((n[0]?.i ?? 0) % Y / 7 + 1)").font(.footnote).foregroundStyle(.secondary)
          Text(n[1]?.str ?? "")
        }
      }
    }
    .navigationTitle("News")
  }
}

struct CareerHub: View {
  @Bindable var store: CareerStore
  let play: () -> Void
  var onPractice: () -> Void = {}
  /* Retire pushes the recap (cv.stack = hub, recap) */
  @State private var recap = false
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, me = S["me"]!, tier = me["tier"]!.i, day = S["day"]!.i
    let nm = E.nextMatch()
    /* `-felt-career-bracket`: the next match's event's bracket in place of the hub (a test hook) */
    if ProcessInfo.processInfo.arguments.contains("-felt-career-bracket"), let id = nm["event"]?.str {
      CareerBracket(store: store, id: id)
    } else if ProcessInfo.processInfo.arguments.contains("-felt-career-calendar") {
      if ProcessInfo.processInfo.arguments.contains("-felt-career-event"), let id = nm["event"]?.str { CareerEvent(store: store, id: id) } else { CareerCalendar(store: store) }
    } else if ProcessInfo.processInfo.arguments.contains("-felt-career-sponsors") {
      CareerSponsors(store: store)
    } else if ProcessInfo.processInfo.arguments.contains("-felt-career-recap") {
      CareerRecap(store: store)
    } else if ProcessInfo.processInfo.arguments.contains("-felt-career-stats") {
      CareerStats(store: store)
    } else if ProcessInfo.processInfo.arguments.contains("-felt-career-records") {
      CareerRecords(store: store)
    } else if ProcessInfo.processInfo.arguments.contains("-felt-career-options") {
      CareerOptions(store: store)
    } else if ProcessInfo.processInfo.arguments.contains("-felt-career-rivals") {
      if let r = ProcessInfo.processInfo.arguments.contains("-felt-career-player") ? E.rivals().first?["id"]?.i : nil { CareerPlayer(store: store, id: r) } else { CareerRivals(store: store) }
    } else {
    List {
      Section {
        /* `-felt-career-groups`: the hub without its top, to see the groups (a test hook) */
        if !ProcessInfo.processInfo.arguments.contains("-felt-career-groups") {
          CareerHubTop(store: store, play: play).padding(.top, 6).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
      }
      if truthy(me["ret"]) {
        CareerRetired(store: store)
      } else {
      if !store.msg.isEmpty { Section { Text(store.msg).font(.subheadline) } }
      if E.reviewDue { CareerReview(store: store) }
      if nm == .null { CareerThisWeek(store: store) }
      CareerHubGroups(store: store, onPractice: onPractice, onRetire: { recap = true })
      }
    }
    .navigationDestination(isPresented: $recap) { CareerRecap(store: store) }
    }
  }
  func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary) } }
}

/* the season just ended (review): its line, the verdict, next season's targets; Done marks it seen */
struct CareerReview: View {
  @Bindable var store: CareerStore
  var body: some View {
    let r = store.E.review()
    Section("Season \(r["season"]!.i) Review") {
      Text(r["moved"]!.s == "up" ? "Promoted to \(r["tier"]!.s)." : r["moved"]!.s == "down" ? "Relegated to \(r["tier"]!.s)." : "Staying at \(r["tier"]!.s).").font(.headline)
      Text("\(r["w"]!.i)-\(r["l"]!.i) in matches, \(r["ti"]!.i) title\(r["ti"]!.i == 1 ? "" : "s"), \(JV.numberString(r["prize"]!.d)) credits in prize money.").font(.subheadline)
      ForEach(r["targets"]!.a.indices, id: \.self) { i in Text(r["targets"]!.a[i].s).font(.footnote).foregroundStyle(.secondary) }
      Button("Done") { store.E.reviewSeen(); store.E.save(); store.touch() }.bold().foregroundStyle(.white)
    }
  }
}

/* the rankings: a circuit, a game, or the season's points; the player's row in weight 700 */
struct CareerRankings: View {
  @Bindable var store: CareerStore
  @State private var key = "local"
  var body: some View {
    let _ = store.rev
    let keys = CareerEngine.const("CIRCUITS").a.map { $0.s } + ["season"] + CareerEngine.const("DISCS").a.map { $0.s }
    List {
      Picker("Ranking", selection: $key) { ForEach(keys, id: \.self) { k in Text(CareerStore.game(k) != nil ? CareerStore.gameName(k) : k.capitalized).tag(k) } }
      let rows = store.E.rankings(key, top: 50).a
      if rows.isEmpty { Text("No points yet.").foregroundStyle(.secondary) }
      ForEach(rows.indices, id: \.self) { i in
        let r = rows[i], me = r["human"] == true
        HStack {
          Text("\(r["rank"]!.i)").monospacedDigit().frame(width: 32, alignment: .trailing).foregroundStyle(.secondary)
          Text(r["name"]!.s).fontWeight(me ? .bold : .regular)
          Spacer()
          Text(JV.numberString(r["pts"]!.d)).monospacedDigit().fontWeight(me ? .bold : .regular)
        }
      }
    }
    .navigationTitle("Rankings")
  }
}

/* the player's numbers: all games, then each game played */
/* PAGES.stats: Career over Stats; the card (Matches, Won, Win rate; Titles, Finals, Prize money); Play (racks, breaks,
   break and run, run outs, accuracy, called shots, safeties, fouls, streak, best run); By Game; Skills (each value over
   its meter); the purity note; the ladder record; Records and Hall of Fame */
struct CareerStats: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, s = E.stats(), a = s["all"]!, ins = EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16)
    let fr = a["foulsPerRack"]!, st = a["streak"]!.i
    List {
      CareerTitle(kick: "Career", title: "Stats")
      Section {
        VStack(spacing: 12) {
          HStack(alignment: .top) { fact("Matches", "\(a["matches"]!.i)"); fact("Won", "\(a["won"]!.i)"); fact("Win Rate", a["winPct"]!["d"]!.d != 0 ? "\(JV.numberString(a["winPct"]!["pct"]!.d))%" : "-") }
          HStack(alignment: .top) { fact("Titles", "\(a["titles"]!.i)"); fact("Finals", "\(a["finals"]!.i)"); fact("Prize Money", CareerWords.crWords(a["prize"]!.d)) }
        }
        .padding(.vertical, 6)
      }
      Section {
        row("Racks Won", nil, pw(a["racks"]!["pct"]!))
        row("Legal Breaks", nil, pw(a["legalBreak"]!))
        row("Break and Run", nil, pw(a["breakAndRun"]!))
        row("Run Outs", nil, pw(a["runout"]!))
        row("Shot Accuracy", "Balls potted of shots taken", pw(a["shotAccuracy"]!))
        row("Called Shots Made", nil, pw(a["calledShot"]!))
        row("Safeties That Worked", "Counted in simulated matches", pw(a["safety"]!))
        row("Fouls", nil, "\(a["fouls"]!.i), " + (fr["d"]!.d != 0 ? String(format: "%.2f a rack", a["fouls"]!.d / fr["d"]!.d) : "no racks yet"))
        row("Streak", nil, st > 0 ? "Won \(st)" : st < 0 ? "Lost \(-st)" : "None")
        row("Best Winning Run", nil, "\(a["bestStreak"]!.i)")
      } header: { CareerPageHead(t: "Play") }
      .listRowInsets(ins)
      let by = s["byDisc"]!.keys
      if !by.isEmpty {
        Section {
          ForEach(by, id: \.self) { d in
            let x = s["byDisc"]![d]!, ti = x["titles"]!.i
            row(titleCaseWords(CareerStore.gameName(d)), "\(ti) title\(ti == 1 ? "" : "s"), \(pw(x["racks"]!["pct"]!)) racks", "\(x["won"]!.i)-\(x["lost"]!.i)")
          }
        } header: { CareerPageHead(t: "By Game") }
        .listRowInsets(ins)
      }
      Section {
        ForEach(CareerStore.T("SKILLS").a.map { $0.s }, id: \.self) { k in
          let v = Int((s["skills"]![k]?.d ?? 0).rounded())
          HStack {
            Text(CareerStore.T("SKILL_NAMES")[k]?.str ?? k).font(.system(size: 17))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
              Text("\(v)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
              ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Color(rgb: 0x3d, 0xdc, 0x84)).frame(width: 96 * CGFloat(min(100, max(0, v))) / 100)
              }
              .frame(width: 96, height: 4)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel("\(v) of 100")
          }
        }
      } header: { CareerPageHead(t: "Skills") } footer: {
        Text(truthy(E.S["me"]!["opt"]?["purity"]) ? "Simulation purity is on: skills are a record of your play and decide only the matches the model settles."
             : "Skills grow from matches and drills. Under Options: what they change in your own play.").font(.system(size: 13))
      }
      .listRowInsets(ins)
      if let lg = s["legacy"], lg != .null {
        Section {
          row("Carried Over", "\(lg["beaten"]?.a.count ?? 0) of 8 beaten, \(lg["won"]!.i) of \(lg["played"]!.i) matches won", lg["played"]!.d != 0 ? "\(JV.numberString(lg["winPct"]!["pct"]!.d))%" : "")
        } header: { CareerPageHead(t: "Ladder Record") }
        .listRowInsets(ins)
      }
      Section { NavigationLink { CareerRecords(store: store) } label: { Text("Records and Hall of Fame").font(.system(size: 17)) }.accessibilityIdentifier("cvRecords") }
        .listRowInsets(ins)
    }
    .environment(\.defaultMinListRowHeight, 44)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
  /* pctWords */
  private func pw(_ p: JV) -> String { p["d"]!.d != 0 ? "\(p["n"]!.i) of \(p["d"]!.i), \(JV.numberString(p["pct"]!.d))%" : "none yet" }
  private func fact(_ k: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(k).font(.system(size: 13)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
      Text(v).font(.system(size: 17, weight: .bold)).monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
  private func row(_ t: String, _ sub: String?, _ v: String) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(t).font(.system(size: 17))
        if let sub { Text(sub).font(.system(size: 15)).foregroundStyle(.secondary) }
      }
      Spacer()
      Text(v).font(.system(size: 15)).foregroundStyle(.secondary).monospacedDigit().multilineTextAlignment(.trailing)
    }
  }
}

/* the shop: each item's price or lock, Buy, and Equip for what is owned; a checkmark on what is worn */
struct CareerShop: View {
  @Bindable var store: CareerStore
  @State private var msg = ""
  var body: some View {
    let _ = store.rev
    let E = store.E, eq = E.equipped(), items = CareerEngine.const("SHOP").a
    let slots = CareerEngine.const("SHOP_SLOTS").a.map { $0.s }
    List {
      Section { Text("Credits: \(JV.numberString(E.S["me"]!["money"]!.d))") ; if !msg.isEmpty { Text(msg).font(.footnote).foregroundStyle(.secondary) } }
      ForEach(slots, id: \.self) { slot in
        Section(slot.capitalized) {
          ForEach(items.indices.filter { items[$0]["slot"]?.str == slot }, id: \.self) { i in
            let it = items[i], id = it["id"]!.s, owned = E.owns(id), worn = eq[slot]?.str == id
            HStack {
              Text(it["name"]!.s).fontWeight(worn ? .bold : .regular)
              if worn { Image(systemName: "checkmark").foregroundStyle(.white) }
              Spacer()
              if owned { if !worn { Button("Equip") { E.equip(id); E.save(); store.touch() }.buttonStyle(.borderless).foregroundStyle(.white) } }
              else { Button("Buy, \(JV.numberString(it["price"]!.d))") { msg = E.buy(id).map { "Can't buy: \($0)." } ?? "Bought \(it["name"]!.s)."; E.save(); store.touch() }.buttonStyle(.borderless).foregroundStyle(.white) }
            }
          }
        }
      }
    }
    .navigationTitle("Shop")
  }
}

/* the sponsors: each contract, its weeks left, retainer and objectives (met in weight 700) */
/* PAGES.sponsors: Career over Sponsors; Contracts (each brand and category over Brand, Retainer, Weeks left, Bonus and
   each objective with its progress); Offers (a sponsor's retainer, bonus, objectives and end; a challenge's or an
   exhibition's game, race, purse and end), each Accept and Decline; the past contracts' count */
struct CareerSponsors: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, day = S["day"]!.i
    let act = S["spons"]!.a.filter { !truthy($0["end"]) }, offs = S["off"]!.a, past = S["sph"]!.a.count
    let note = { (t: String) in Text(t).font(.system(size: 13)).foregroundStyle(.secondary).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4)) }
    List {
      CareerTitle(kick: "Career", title: "Sponsors")
      if !store.msg.isEmpty { Section { Text(store.msg).font(.system(size: 15)) } }
      if act.isEmpty { Section { note("No sponsor yet. Offers come with results and reputation; two contracts at once, one per category.") } header: { CareerPageHead(t: "Contracts") } }
      ForEach(Array(act.enumerated()), id: \.offset) { i, c in
        Section {
          card(c["brand"]!.s, c["cat"]!.s, [("Brand", "\(c["brand"]!.s) (\(c["cat"]!.s))"), ("Retainer", "\(CareerWords.crWords(c["ret"]!.d)) a week"),
                ("Weeks Left", "\(max(0, Int((Double(c["to"]!.i - day) / 7).rounded(.up))))"), ("Bonus", "\(CareerWords.crWords(c["bonus"]!.d)) for every objective")]
               + c["obj"]!.a.map { o in
                 let done = truthy(o["done"]), pr = E.objProgress(o)
                 return (done ? "Done" : "Objective", E.objText(o) + (done ? "" : o["k"]!.s == "rank" ? (pr.map { ", now number \($0)" } ?? ", unranked now") : ", \(pr ?? 0) so far"))
               })
        } header: { if i == 0 { CareerPageHead(t: "Contracts") } }
      }
      if offs.isEmpty { Section { note("No offers right now. They expire after a few weeks.") } header: { CareerPageHead(t: "Offers") } }
      ForEach(Array(offs.enumerated()), id: \.offset) { i, o in
        let id = o["id"]!.s, sp = o["type"]!.s == "sponsor"
        Section {
          VStack(spacing: 8) {
          if sp {
            card(o["brand"]!.s, "\(o["cat"]!.s), \(o["weeks"]!.i) weeks", [("Retainer", "\(CareerWords.crWords(o["ret"]!.d)) a week"), ("Bonus", CareerWords.crWords(o["bonus"]!.d))]
                 + o["obj"]!.a.map { ("Objective", E.objText($0)) } + [("Offer Ends", "Week \(E.weekOfDay(o["exp"]!.i))")])
          } else {
            card(o["type"]!.s == "challenge" ? "Challenge from \(E.nameOf(o["opp"]!.i))" : "Exhibition with \(E.nameOf(o["opp"]!.i))", "Week \(E.weekOfDay(o["start"]!.i))",
                 [("Game", CareerStore.gameName(o["disc"]!.s)), ("Race", "First to \(CareerWords.unitWords(o["disc"]!.s, o["race"]!.i))"), ("Purse", CareerWords.crWords(o["purse"]!.d)),
                  ("Offer Ends", "Week \(E.weekOfDay(o["exp"]!.i))")])
          }
          HStack(spacing: 8) {
            Button { let why = E.accept(id); store.msg = why == nil ? "Accepted." : "Not accepted: \(why!)."; E.save(); store.touch() } label: { cap("Accept", true) }
              .buttonStyle(.plain).accessibilityIdentifier("acc-" + id)
            Button { E.decline(id); store.msg = "Declined."; E.save(); store.touch() } label: { cap("Decline", false) }
              .buttonStyle(.plain).accessibilityIdentifier("dec-" + id)
          }
          .padding(.bottom, 6)
          }
        } header: { if i == 0 { CareerPageHead(t: "Offers") } }
      }
      if past > 0 { Section { note("\(past) past contract\(past == 1 ? "" : "s").") } }
    }
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    .onDisappear { store.msg = "" }
  }
  /* a cvCard: the name and its tag over the lines */
  private func card(_ name: String, _ tag: String, _ lines: [(String, String)]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.7))
        Spacer()
        Text(tag).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color.white.opacity(0.1)))
      }
      VStack(spacing: 6) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
          HStack(alignment: .firstTextBaseline) {
            Text(l.0).foregroundStyle(Color(rgb: 0xeb, 0xeb, 0xf5).opacity(0.6))
            Spacer(minLength: 12)
            Text(l.1).multilineTextAlignment(.trailing)
          }
          .font(.system(size: 15))
        }
      }
    }
    .padding(.vertical, 6)
  }
  private func cap(_ t: String, _ primary: Bool) -> some View {
    Text(t).font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 50)
      .foregroundStyle(primary ? Color.black : Color.white)
      .background(Capsule().fill(primary ? Color.white : Color(rgb: 0x2c, 0x2c, 0x30)))
  }
}

/* PAGES.practice: three sessions a day; each drill (the career's DRILLS) with its skill, shots and mastery, Play */
struct CareerPractice: View {
  @Bindable var store: CareerStore
  let play: (String) -> Void
  var body: some View {
    let done = store.practiceToday, mas = store.E.S["me"]?["mas"], names = CareerStore.T("SKILL_NAMES")
    List {
      Section {} footer: { Text("Each drill is played on the table and scored from your shots; the score is recorded here when it ends. Three sessions a day; practice never moves the clock. Mastery is a record; skills grow a little.") }
      Section {
        ForEach(Array(CareerStore.T("DRILLS").a.enumerated()), id: \.offset) { _, d in
          let id = d["id"]!.s, m = mas?[id], best = m?["best"]?.i ?? 0, lv = m?["lv"]?.i ?? 0, lib = drillById(id)
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(d["name"]!.s).font(.body.weight(.semibold))
              Text("\(names[d["skill"]!.s]?.str ?? ""). \(lib.map { "\($0.shots) shots. " } ?? "")Best \(best)" + (lv > 0 ? ", \(["bronze", "silver", "gold"][lv - 1])" : "")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Play") { play(id) }.buttonStyle(.borderless).bold().foregroundStyle(.white).disabled(done >= 3 || lib == nil)
              .accessibilityLabel("Play \(d["name"]!.s)").accessibilityIdentifier("drill-" + id)
          }
          .frame(minHeight: 44)
        }
      }
    }
    .navigationTitle("Practice")
    .onAppear { store.touch() }
  }
}
