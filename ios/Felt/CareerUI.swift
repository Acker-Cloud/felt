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
      _ = E.create(["name": "Ada Demo", "nat": "GB", "disc": "9", "style": "potter", "difficulty": "medium", "start": "amateur", "age": 28], seed: 31337)
      for _ in 0..<12 {
        let day = E.S["day"]!.i
        if let ev = E.S["cal"]!.a.first(where: { $0["start"]!.i > day && E.eligibility($0).isEmpty }) { E.enter(ev["id"]!.s) }
        if E.advance(week: true) == "match" { break }
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

/* the offers (sponsorships, challenges, exhibitions), each to accept or decline: the page's Sponsors and Offers */
struct CareerOffersSection: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S
      let off = S["off"]!.a
    if !off.isEmpty {
      Section("Offers") {
        ForEach(off.indices, id: \.self) { i in
          let o = off[i], id = o["id"]!.s
          HStack {
            Text(o["type"]!.s == "sponsor" ? "\(o["brand"]!.s): \(o["weeks"]!.i) weeks, \(JV.numberString(o["ret"]!.d)) a week" : "\(o["type"]!.s.capitalized) vs \(E.nameOf(o["opp"]!.i))").font(.subheadline)
            Spacer()
            Button("Decline") { E.decline(id); store.touch() }.buttonStyle(.borderless).foregroundStyle(.secondary)
            Button("Accept") { store.msg = E.accept(id) ?? ""; store.touch() }.buttonStyle(.borderless).bold().foregroundStyle(.white)
          }
        }
      }
    }
  }
}

/* PAGES.hub's groups: Season (Calendar, Rankings, Tour Card), You (Stats and Records, Sponsors and Offers, Shop, Practice
   Drills, News), Career (Switch Career, Retire), each row its name and the page's line. The page's Bracket and
   Standings, Rivals and Options rows are not here: those pages are not ported yet. */
struct CareerHubGroups: View {
  @Bindable var store: CareerStore
  var onPractice: () -> Void
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
    let news = S["news"]!.a.last.map { $0[1]?.str ?? "Nothing yet" } ?? "Nothing yet"
    Section {
      NavigationLink { CareerCalendar(store: store) } label: { row("Calendar", "\(open) event\(open == 1 ? "" : "s") open to you, \(entered) entered") }
      NavigationLink { CareerRankings(store: store) } label: { row("Rankings", rk.map { "\(circNames[circ]): number \($0["rank"]!.i), \($0["pts"]!.i) points" } ?? "Unranked so far") }
      row("Tour Card", tier >= 8 && tier < 12 ? (E.moneyRank() > 0 ? "Money list: number \(E.moneyRank())" : "Earn on the money list") : "Not needed yet")
    } header: { head("Season") }
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    Section {
      NavigationLink { CareerStats(store: store) } label: { row("Stats and Records", "\(st["won"]?.i ?? 0) won of \(st["matches"]?.i ?? 0)") }
      NavigationLink { CareerSponsors(store: store) } label: { row("Sponsors and Offers", "\(sponsors) contract(s)", val: offers > 0 ? "\(offers) new" : nil) }
      NavigationLink { CareerShop(store: store) } label: { row("Shop", "Cosmetics only", val: CareerWords.crWords(me["money"]!.d)) }
      Button(action: onPractice) { row("Practice Drills", "\(store.practiceToday) of 3 sessions today", chevron: true) }.tint(.primary).accessibilityIdentifier("cvPractice")
      NavigationLink { CareerNews(store: store) } label: { row("News", news) }
    } header: { head("You") }
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    Section {
      Button { store.E.save(); store.E.S = .null; store.touch() } label: { row("Switch Career", "Your careers, a new one", chevron: true) }.tint(.primary)
      Button {
        if retiring { retiring = false; store.E.retire(); store.touch() } else { retiring = true; Task { try? await Task.sleep(for: .seconds(4)); retiring = false } }
      } label: { row(retiring ? "Tap again to retire" : "Retire", "End this career, see the recap", warn: true, chevron: true) }
    } header: { head("Career") }
    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
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

/* PAGES.calendar, in brief: the events still taking entries, with the week, fee, and Enter where you may */
struct CareerCalendar: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, day = S["day"]!.i, Y = CareerEngine.const("YEAR").i
    let list = S["cal"]!.a.filter { day <= ($0["dl"]?.i ?? 0) && $0["opp"] == nil }
    List {
      Section {
        ForEach(list.indices, id: \.self) { i in
          let ev = list[i], id = ev["id"]!.s, entered = truthy(S["es"]![id]?["en"]), why = E.eligibility(ev)
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(ev["name"]!.s)
              Text("\(CareerStore.gameName(ev["disc"]!.s)), week \(ev["start"]!.i % Y / 7 + 1), tier \(ev["tier"]?.i ?? 0)" + (entered ? ", entered" : why.isEmpty ? "" : ". \(why[0].prefix(1).uppercased() + why[0].dropFirst())"))
                .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if !entered && why.isEmpty { Button(CareerWords.crWords(ev["fee"]!.d + ev["trav"]!.d)) { E.enter(id); store.touch() }.buttonStyle(.borderless).bold().foregroundStyle(.white) }
          }
        }
      }
    }
    .navigationTitle("Calendar")
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
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, me = S["me"]!, tier = me["tier"]!.i, day = S["day"]!.i
    let nm = E.nextMatch()
    List {
      Section {
        /* `-felt-career-groups`: the hub without its top, to see the groups (a test hook) */
        if !ProcessInfo.processInfo.arguments.contains("-felt-career-groups") {
          CareerHubTop(store: store, play: play).padding(.top, 6).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
        }
      }
      if !store.msg.isEmpty { Section { Text(store.msg).font(.subheadline) } }
      if E.reviewDue { CareerReview(store: store) }
      if nm == .null {
        Section {
          Button("Next Week") { let r = E.advance(week: true); store.msg = r == "match" ? "A match is due." : ""; store.touch() }.bold().foregroundStyle(.white).accessibilityIdentifier("career-week")
        }
      }
      CareerHubGroups(store: store, onPractice: onPractice)

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
struct CareerStats: View {
  @Bindable var store: CareerStore
  var body: some View {
    let st = store.E.stats()
    List {
      block("All Games", st["all"]!)
      ForEach(st["byDisc"]!.keys, id: \.self) { d in block(CareerStore.gameName(d), st["byDisc"]![d]!) }
    }
    .navigationTitle("Stats")
  }
  func pctWords(_ p: JV) -> String { p["d"]!.d != 0 ? "\(p["n"]!.i) of \(p["d"]!.i), \(JV.numberString(p["pct"]!.d))%" : "None yet" }
  @ViewBuilder func block(_ title: String, _ b: JV) -> some View {
    Section(title) {
      row("Matches", "\(b["won"]!.i)-\(b["lost"]!.i)")
      row("Win Rate", pctWords(b["winPct"]!))
      row("Racks", pctWords(b["racks"]!["pct"]!))
      row("Titles", "\(b["titles"]!.i)")
      row("Shot Accuracy", pctWords(b["shotAccuracy"]!))
      row("Safeties", pctWords(b["safety"]!))
      row("Break and Run", pctWords(b["breakAndRun"]!))
      row("Best Streak", "\(b["bestStreak"]!.i)")
    }
  }
  func row(_ k: String, _ v: String) -> some View { HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary) } }
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
struct CareerSponsors: View {
  @Bindable var store: CareerStore
  var body: some View {
    let _ = store.rev
    let S = store.E.S, day = S["day"]!.d
    List {
      CareerOffersSection(store: store)
      let sp = S["spons"]!.a
      if sp.isEmpty { Text("No sponsor yet. Offers come with results and reputation.").foregroundStyle(.secondary) }
      ForEach(sp.indices, id: \.self) { i in
        let c = sp[i]
        Section(c["brand"]!.s) {
          Text("\(JV.numberString(c["ret"]!.d)) credits a week, \(Int(((c["to"]!.d - day) / 7).rounded(.up))) weeks left").font(.subheadline)
          ForEach(c["obj"]!.a.indices, id: \.self) { j in
            let o = c["obj"]!.a[j]
            Text("\(store.E.objText(o)), pays \(JV.numberString(o["pay"]!.d))").font(.footnote).fontWeight(truthy(o["done"]) ? .bold : .regular)
          }
        }
      }
    }
    .navigationTitle("Sponsors")
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
