/* index.html 6s, Stats and records: a navigation stack in How to play's manner. The overview (the win streaks, a row
   per game, the records book and the recent form, the CPU results by level, snooker's line) and a page for what is
   pushed: a game's numbers, the records book or the form. Every rate shows its denominator ("7 of 9, 78%"). All of it
   reads the record (Rec); nothing here writes it. Not here: the trick points and daily streak (not ported), the
   career's numbers (its own screen). */
import FeltSim
import SwiftUI

enum StatWords {
  static let NAME = ["8": "8-ball", "9": "9-ball", "10": "10-ball", "straight": "Straight pool", "rotation": "Rotation", "bumper": "Bumper pool", "carom": "Three-cushion", "snooker": "Snooker", "heyball": "Chinese 8-ball"]
  static let BALL = ["8": 8, "9": 9, "10": 10, "straight": 14, "rotation": 15, "heyball": 8]
  /* "7 of 9, 78%", or "none yet" */
  static func of(_ n: Int, _ d: Int) -> String { d > 0 ? "\(n) of \(d), \(Int((100 * Double(n) / Double(d)).rounded()))%" : "none yet" }
  /* dateWords: "15 Nov 2026" */
  static func date(_ d: String?) -> String {
    guard let d, d.count == 10 else { return "" }
    let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], mi = Int(d.dropFirst(5).prefix(2)) ?? 1
    return "\(Int(d.suffix(2)) ?? 1) \(m[max(0, min(11, mi - 1))]) \(d.prefix(4))"
  }
  static func cpuOf(_ r: RecKind) -> (w: Int, n: Int) { Rec.LEVELS.reduce((0, 0)) { a, lv in (a.0 + r.cpu[lv]!.w, a.1 + r.cpu[lv]!.w + r.cpu[lv]!.l) } }
  static func title(_ s: String) -> String { titleCaseWords(s) }
  /* bookOf: every best there is, with its date */
  static func book(_ rec: Rec) -> [(String, String, String?)] {
    var out: [(String, String, String?)] = []
    if rec.best > 0 { out.append(("Longest win streak against the CPU", "\(rec.best) game\(rec.best == 1 ? "" : "s")", rec.bestD)) }
    for k in Rec.KINDS {
      let r = rec.kinds[k]!, car = k == "carom"
      if r.run.v > 0 { out.append(("\(NAME[k]!): \(car ? "high run" : "best run")", "\(r.run.v) \(car ? "point" : "ball")\(r.run.v == 1 ? "" : "s")", r.run.d)) }
      if r.lp.v > 0 { out.append(("\(NAME[k]!): longest pot", "\(r.lp.v) cm", r.lp.d)) }
      if k == "snooker" && r.high > 0 { out.append(("Snooker: highest break", "\(r.high)", r.highD)) }
    }
    return out
  }
}
/* titleCase (6a): words Title Case, Apple style */
func titleCaseWords(_ s: String) -> String {
  let small: Set<String> = ["a", "an", "the", "and", "or", "of", "to", "in", "on", "vs", "at", "by", "for"]
  return s.split(separator: " ", omittingEmptySubsequences: false).enumerated().map { i, w in
    let w = String(w)
    if i > 0 && small.contains(w) { return w }
    return w.split(separator: "-", omittingEmptySubsequences: false).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: "-")
  }.joined(separator: " ")
}

/* a row: the label (and a line under it) and the value (and a line under it) */
struct StatRow: View {
  let label: String, value: String
  var sub: String? = nil, vsub: String? = nil
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(StatWords.title(label))
        if let sub, !sub.isEmpty { Text(sub).font(.footnote).foregroundStyle(.secondary) }
      }
      Spacer(minLength: 12)
      VStack(alignment: .trailing, spacing: 2) {
        Text(value).font(.body.weight(.semibold)).monospacedDigit()
        if let vsub, !vsub.isEmpty { Text(vsub).font(.footnote).foregroundStyle(.secondary) }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
/* the form: W and L pips, oldest first (no colour carries it: the letter does) */
struct FormPips: View {
  let list: [RecForm]
  var body: some View {
    HStack(spacing: 6) {
      if list.isEmpty { Text("No games yet").foregroundStyle(.secondary) }
      ForEach(Array(list.enumerated()), id: \.offset) { _, f in
        Text(f.wl).font(.footnote.weight(.bold)).frame(width: 24, height: 24)
          .background(Circle().fill(f.wl == "W" ? Color.white : Color(white: 0.22)))
          .foregroundStyle(f.wl == "W" ? Color.black : Color.white)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(list.isEmpty ? "No games yet" : "Oldest to newest: " + list.map { $0.wl == "W" ? "won" : "lost" }.joined(separator: ", "))
  }
}

struct StatsView: View {
  @State private var rec = Rec.load()
  var body: some View {
    CapList {
      /* .kpis: four tiles, two to a row: the win streak and best against the CPU, the trick shots' points of the
         program's, the daily shot's streak and its best */
      Section {
        let D = DailyStore.rec
        /* four to a row above 600 pt wide (.kpis at min-width 600); never on a phone */
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
          if Prefs.phone {
            GridRow { kpi("Win Streak", rec.streak, "vs CPU"); kpi("Best Streak", rec.best, "vs CPU") }
            GridRow { kpi("Trick Points", programTotal(TrickStore.score.pts), "of \(programMax())"); kpi("Daily Streak", DailyStore.streak(), "best \(D.best)") }
          } else {
            GridRow { kpi("Win Streak", rec.streak, "vs CPU"); kpi("Best Streak", rec.best, "vs CPU"); kpi("Trick Points", programTotal(TrickStore.score.pts), "of \(programMax())"); kpi("Daily Streak", DailyStore.streak(), "best \(D.best)") }
          }
        }
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      } header: {
        Text("Stats").font(.system(size: 28, weight: .bold)).foregroundStyle(Color.white).textCase(nil).padding(.leading, -4).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
      }
      Section {
        ForEach(Rec.KINDS, id: \.self) { k in
          let r = rec.kinds[k]!, c = StatWords.cpuOf(r)
          NavigationLink { StatsKindPage(kind: k, rec: rec) } label: {
            HStack(spacing: 12) {
              /* .htile: the game's ball on the accent's tile */
              BallDot(n: StatWords.BALL[k] ?? 0, style: ["bumper": "bb", "carom": "bc", "snooker": "bsblk"][k]).frame(width: 18, height: 18)
                .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.12, green: 0.42, blue: 0.29)))
              VStack(alignment: .leading, spacing: 1) {
                Text(StatWords.title(StatWords.NAME[k]!)).font(.system(size: 17))
                Text(r.played > 0 ? "\(r.played) played, \(c.n > 0 ? "\(c.w) won of \(c.n) vs CPU" : "none vs CPU")" : "Not played yet").font(.system(size: 15)).foregroundStyle(.secondary)
              }
            }
          }
          .accessibilityIdentifier("st-" + k).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
      } header: { Text("By Game").font(.system(size: 13)).foregroundStyle(.secondary).textCase(nil) }
      Section {
        let bk = StatWords.book(rec).count, fl = rec.form.suffix(10)
        NavigationLink { StatsBookPage(rec: rec) } label: {
          PrefRow(icon: "book.closed", name: "Records Book", line: bk > 0 ? "\(bk) record\(bk == 1 ? "" : "s"), with their dates" : "Your bests, with their dates")
        }
        NavigationLink { StatsFormPage(rec: rec) } label: {
          PrefRow(icon: "chart.line.uptrend.xyaxis", name: "Recent Form", line: fl.isEmpty ? "Your last games against the CPU" : "Last \(fl.count): " + fl.map(\.wl).joined(separator: " "))
        }
      } header: { Text("Records").font(.system(size: 13)).foregroundStyle(.secondary).textCase(nil) }
      /* the table: games by kind, played, against each CPU, two-player */
      Section {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
          GridRow { Text("Game").gridColumnAlignment(.leading); Text("Played"); ForEach(Rec.LEVELS, id: \.self) { Text(Rec.FOES[$0]!) }; Text("2P") }.font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
          ForEach(Rec.KINDS, id: \.self) { k in
            let r = rec.kinds[k]!
            GridRow {
              Text(["bumper": "Bumper", "carom": "Carom", "straight": "14.1"][k] ?? StatWords.NAME[k]!).gridColumnAlignment(.leading)
              Text("\(r.played)").foregroundStyle(r.played > 0 ? .primary : .secondary)
              ForEach(Rec.LEVELS, id: \.self) { lv in let o = r.cpu[lv]!; Text("\(o.w)-\(o.l)").foregroundStyle(o.w + o.l > 0 ? .primary : .secondary) }
              Text("\(r.two)").foregroundStyle(r.two > 0 ? .primary : .secondary)
            }
          }
        }
        .font(.footnote).monospacedDigit()
        .accessibilityElement(children: .contain).accessibilityLabel("Games by kind: played, wins and losses against Rookie, Regular and Hustler, and two-player games")
      } header: { Text("CPU Results by Level").font(.system(size: 13)).foregroundStyle(.secondary).textCase(nil) } footer: {
        let sk = rec.kinds["snooker"]!
        VStack(alignment: .leading, spacing: 8) {
          Text("Against the CPU: wins and losses. A game counts when it finishes.")
          Text("Snooker: \(sk.frames) frame\(sk.frames == 1 ? "" : "s") played, highest break \(sk.high).")
          /* tutStat: the page's six tutorials (TUT_IDS) */
          Text("Tutorials: \(["8", "9", "bumper", "carom", "snooker", "heyball"].filter { TutStore.rec.done.contains($0) }.count) of 6 done.")
        }
      }
    }
    .environment(\.defaultMinListRowHeight, 54)
    .contentMargins(.top, 0, for: .scrollContent)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    .onAppear { rec = Rec.load() }
  }
  /* a .kpis tile: its name, the figure, a few words after it */
  func kpi(_ t: String, _ v: Int, _ s: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(t).font(.system(size: 13)).foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 4) { Text("\(v)").font(.system(size: 22, weight: .bold)).monospacedDigit(); Text(s).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
    }
    .padding(.horizontal, 16).padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(rgb: 0x1c, 0x1c, 0x1f)))
    .accessibilityElement(children: .combine)
  }
}

/* statsKindPage */
struct StatsKindPage: View {
  let kind: String, rec: Rec
  var body: some View {
    let r = rec.kinds[kind]!, c = StatWords.cpuOf(r), car = kind == "carom", snk = kind == "snooker", pots = !["carom", "bumper"].contains(kind)
    let form = Array(rec.form.filter { $0.kind == kind }.suffix(10))
    CapList {
      Section("Games") {
        StatRow(label: "Played", value: "\(r.played)", sub: r.two > 0 ? "\(r.two) two-player" : "Two-player and against the CPU")
        StatRow(label: "Wins against the CPU", value: StatWords.of(c.w, c.n))
        if snk { StatRow(label: "Frames played", value: "\(r.frames)") }
      }
      Section("Against the CPU") {
        ForEach(Rec.LEVELS, id: \.self) { lv in
          let o = r.cpu[lv]!
          StatRow(label: Rec.FOES[lv]!, value: "\(o.w)-\(o.l)", sub: ["easy": "Easy", "medium": "Medium", "hard": "Hard"][lv], vsub: o.w + o.l > 0 ? "won \(StatWords.of(o.w, o.w + o.l))" : "not played")
        }
      }
      Section {
        StatRow(label: car ? "Points" : "Potting", value: car ? StatWords.of(r.pot, r.sh) : StatWords.of(min(r.pot, r.sh), r.sh), sub: car ? "Shots that scored" : "Legal balls down, per shot taken")
        if !car { StatRow(label: "Break success", value: StatWords.of(r.brOk, r.br), sub: "A ball down and no foul") }
        StatRow(label: "Fouls", value: StatWords.of(r.fo, r.sh), sub: "Of your shots")
      } header: { Text("Shots") } footer: { Text("Human shots only: yours against the CPU, both players' in a two-player game.") }
      Section("Bests") {
        StatRow(label: car ? "High run" : "Best run", value: "\(r.run.v)\(car ? " point" : " ball")\(r.run.v == 1 ? "" : "s")", sub: car ? "Points in one inning" : "Legal pots in one visit", vsub: StatWords.date(r.run.d))
        if pots || kind == "bumper" { StatRow(label: "Longest pot", value: r.lp.v > 0 ? "\(r.lp.v) cm" : "none yet", sub: "From where the ball lay to its pocket", vsub: StatWords.date(r.lp.d)) }
        if snk { StatRow(label: "Highest break", value: "\(r.high)", vsub: StatWords.date(r.highD)) }
      }
      Section {
        FormPips(list: form)
      } header: { Text("Recent Form") } footer: {
        Text(form.isEmpty ? "No games against the CPU yet." : "The last \(form.count) against the CPU, oldest first: \(form.filter { $0.wl == "W" }.count) won.")
      }
    }
    .navigationTitle(StatWords.title(StatWords.NAME[kind]!))
  }
}

/* statsBookPage */
struct StatsBookPage: View {
  let rec: Rec
  var body: some View {
    let b = StatWords.book(rec)
    CapList {
      if b.isEmpty { Text("No records yet. Runs, long pots, breaks and win streaks are kept here, each with its date.").foregroundStyle(.secondary) }
      else {
        Section {
          ForEach(Array(b.enumerated()), id: \.offset) { _, x in StatRow(label: x.0, value: x.1, sub: x.2.map { StatWords.date($0) } ?? "Before records had dates") }
        } footer: { Text("A record is dated the day it was set, by this device's clock.") }
      }
    }
    .navigationTitle("Records")
  }
}

/* statsFormPage */
struct StatsFormPage: View {
  let rec: Rec
  var body: some View {
    let last = Array(rec.form.suffix(10)), won = last.filter { $0.wl == "W" }.count, f = Array(rec.form.suffix(20).reversed())
    CapList {
      Section {
        FormPips(list: last)
      } header: { Text("Last 10") } footer: { Text(last.isEmpty ? "No games against the CPU yet." : "\(StatWords.of(won, last.count)) won. Current run of wins: \(rec.streak).") }
      if !f.isEmpty {
        Section("Games, Newest First") {
          ForEach(Array(f.enumerated()), id: \.offset) { _, x in
            StatRow(label: "\(StatWords.NAME[x.kind]!) vs \(Rec.FOES[x.level]!)", value: x.wl == "W" ? "Won" : "Lost", sub: StatWords.date(x.d))
          }
        }
      }
    }
    .navigationTitle("Recent Form")
  }
}
