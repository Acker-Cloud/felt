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
  struct PlayTerms: Identifiable { let id = UUID(); let game: TableGame; let tm: TableModel.TMatch }
  var body: some View {
    Group {
      if store.loaded { CareerHub(store: store) { if let m = store.match() { playing = PlayTerms(game: m.game, tm: m.tm) } } }
      else { CareerSlots(store: store) }
    }
    .navigationTitle(store.loaded ? (store.E.S["profile"]?["name"]?.str ?? "Career") : "Career")
    /* a test hook: `-felt-career-play` opens the next match on the table */
    .navigationDestination(item: $page) { p in
      switch p { case "stats": CareerStats(store: store); case "shop": CareerShop(store: store); case "sponsors": CareerSponsors(store: store); default: CareerRankings(store: store) }
    }
    /* a test hook: `-felt-career-page rankings|stats|shop|sponsors` opens that page */
    .onAppear { let a = ProcessInfo.processInfo.arguments; if let i = a.firstIndex(of: "-felt-career-page"), i + 1 < a.count, page == nil { page = a[i + 1] } }
    .onAppear { if ProcessInfo.processInfo.arguments.contains("-felt-career-play"), playing == nil, let m = store.match() { playing = PlayTerms(game: m.game, tm: m.tm) } }
    .fullScreenCover(item: $playing) { p in
      TableScreen(model: { let m = TableModel(game: p.game, match: p.tm); m.onReport = { _, a, b, f in store.report(a, b, f) }; return m }())
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
struct CareerHub: View {
  @Bindable var store: CareerStore
  let play: () -> Void
  var body: some View {
    let _ = store.rev
    let E = store.E, S = E.S, me = S["me"]!, tier = me["tier"]!.i, day = S["day"]!.i
    let nm = E.nextMatch()
    List {
      Section {
        row("Tier", "\(tier): \(CareerStore.T("TIERS")[tier]!["name"]!.s)")
        row("Season", "\(E.season), week \(day % CareerEngine.const("YEAR").i / 7 + 1)")
        row("Credits", JV.numberString(me["money"]!.d))
        row("Reputation", JV.numberString(me["rep"]!.d))
      }
      if !store.msg.isEmpty { Section { Text(store.msg).font(.subheadline) } }
      if E.reviewDue { CareerReview(store: store) }
      if nm != .null {
        Section("Next Match") {
          VStack(alignment: .leading, spacing: 4) {
            Text("\(nm["eventName"]!.s), \(nm["round"]!.s)").font(.footnote).foregroundStyle(.secondary)
            Text("vs \(nm["opponent"]!["name"]!.s)").font(.headline)
            Text("Race to \(nm["race"]!.i), \(CareerStore.gameName(nm["rules"]!["game"]!.s)), \(nm["level"]!.s.capitalized) opponent").font(.footnote).foregroundStyle(.secondary)
          }
          Button("Play Match", action: play).bold().foregroundStyle(.white).accessibilityIdentifier("career-play")
          Button("Simulate Match") { E.simMatch(); store.msg = "Match simulated."; store.touch() }.foregroundStyle(.white)
        }
      } else {
        Section {
          Button("Next Week") { let r = E.advance(week: true); store.msg = r == "match" ? "A match is due." : ""; store.touch() }.bold().foregroundStyle(.white).accessibilityIdentifier("career-week")
        }
      }
      let open = S["cal"]!.a.filter { $0["start"]!.i > day && $0["start"]!.i <= day + 28 }
      if !open.isEmpty {
        Section("Coming Up") {
          ForEach(open.indices, id: \.self) { i in
            let ev = open[i], id = ev["id"]!.s, entered = truthy(S["es"]![id]?["en"]), why = E.eligibility(ev)
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(ev["name"]!.s)
                Text("\(CareerStore.gameName(ev["disc"]!.s)), week \(ev["start"]!.i % CareerEngine.const("YEAR").i / 7 + 1), fee \(JV.numberString(ev["fee"]!.d + ev["trav"]!.d))\(entered ? ", entered" : why.isEmpty ? "" : ", \(why[0])")")
                  .font(.footnote).foregroundStyle(.secondary)
              }
              Spacer()
              if !entered && why.isEmpty { Button("Enter") { E.enter(id); store.touch() }.buttonStyle(.borderless).bold().foregroundStyle(.white) }
            }
          }
        }
      }
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
      Section {
        NavigationLink("Rankings") { CareerRankings(store: store) }
        NavigationLink("Stats") { CareerStats(store: store) }
        NavigationLink("Shop") { CareerShop(store: store) }
        NavigationLink("Sponsors") { CareerSponsors(store: store) }
      }
      Section("News") { ForEach(Array(S["news"]!.a.suffix(8).reversed().enumerated()), id: \.offset) { _, n in Text(n[1]!.s).font(.footnote) } }
      Section { Button("Switch Career") { E.save(); E.S = .null; store.touch() }.foregroundStyle(.secondary) }
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
