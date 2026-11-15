/* Settings (page 6, PREF_PAGES): the settings that change play, as the page keeps them in felt.settings, with its
   defaults (loadSettings): the rules for 8, 9 and 10-ball (RULESETS, the two-player sets), called shots
   (CALL_MODES), the aim guide and auto aim; the tables (pool's size and pockets for every pool game, snooker's
   table and frames, the bumper table's shape, carom's race and cushions); sound and haptics. Read when a game starts. */
import FeltRender
import FeltSim
import SwiftUI

enum Prefs {
  static var d: UserDefaults { .standard }
  static func str(_ k: String, _ def: String) -> String { d.string(forKey: "felt.settings." + k) ?? def }
  static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: "felt.settings." + k) as? Int ?? def }
  static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: "felt.settings." + k) as? Bool ?? def }
  static var rules8: String { str("rules8", DEFAULT_RULESET["8"]!) }
  static var rules9: String { str("rules9", DEFAULT_RULESET["9"]!) }
  static var rules10: String { str("rules10", DEFAULT_RULESET["10"]!) }
  static var calls: String { str("calls", "official") }
  static var guide: String { str("guide", "full") }
  static var autoAim: Bool { bool("autoAim", true) }
  static var table: String { str("table", "7") }
  static var pockets: String { str("pockets", "regulation") }
  /* snooker's table: compact (10 ft) on a phone, as loadSettings picks it */
  /* 14.1's race: 50 on a phone, as loadSettings picks it */
  static var race141: Int { int("race141", 50) }
  static var snookerTable: String { str("snookerTable", "compact") }
  static var snookerFrames: Int { int("snookerFrames", 1) }
  static var bumperTable: String { str("bumperTable", "octagon") }
  static var caromRace: Int { int("caromRace", 10) }
  static var caromCush: Int { int("caromCush", 3) }
  static var sound: Bool { bool("sound", true) }
  /* Settings > Graphics > Opening Animation (6o); the last game played, which the opening breaks if a pocket game */
  static var intro: Bool { bool("intro", true) }
  static var last: String { get { str("last", "8") } set { d.set(newValue, forKey: "felt.settings.last") } }
  /* Table Dressing (settings.dress): "game" wears each game's own (GAME_LOOK), "mine" the settings' look, each slot only if
     unlocked (else the default) */
  static var dressMode: String { str("dress", "game") }
  /* Table View (settings.view): "top" or "3d", with the 3D camera's pitch (8-70 deg) and distance (0.45-3.2 m), clamped */
  static var view: String { str("view", "top") }
  /* After the Shot (settings.viewAfter): 'pull' to the overview, 'top' the roll top-down, 'stay' the aiming pose */
  static var viewAfter: String { str("viewAfter", "pull") }
  static var viewPitch: Double { min(V3.PITCH[1], max(V3.PITCH[0], d.object(forKey: "felt.settings.viewPitch") as? Double ?? V3.PITCH0)) }
  static var viewDist: Double { min(V3.DIST[1], max(V3.DIST[0], d.object(forKey: "felt.settings.viewDist") as? Double ?? V3.DIST0)) }
  static func mine(_ slot: String) -> String { str("look." + slot, LOOK_DEFAULT[slot]!) }
  static let LOOK_DEFAULT = ["cloth": "green", "cue": "house", "chalk": "blue", "rail": "walnut", "balls": "classic"]
  /* LOOK_BASE and felt.looks.v1: the looks unlocked anywhere, the base and every item any career on this device has owned */
  static let LOOK_BASE: Set<String> = ["cloth-green", "cloth-red", "cloth-blue", "cue-house", "chalk-blue", "rail-walnut", "balls-classic"]
  static var lookOwn: Set<String> { LOOK_BASE.union(d.stringArray(forKey: "felt.looks.v1") ?? []) }
  static func noteLookOwn(_ ids: [String]) {
    let known = ids.filter { id in let p = id.split(separator: "-", maxSplits: 1).map(String.init); return p.count == 2 && Dress.ORDER[p[0]]?.contains(p[1]) == true }
    let more = Set(known).subtracting(lookOwn)
    if !more.isEmpty { d.set(Array((lookOwn.subtracting(LOOK_BASE)).union(more)).sorted(), forKey: "felt.looks.v1") }
  }
  static func owned(_ slot: String, _ key: String) -> Bool { lookOwn.contains(slot + "-" + key) }
  /* look(): By Game, the game's; My Look, the settings' (falling back to the default for anything not unlocked) */
  static func dress(_ game: String) -> Dress {
    if dressMode != "mine" { return Dress.game(game) }
    let pick = { (s: String) -> String in let k = mine(s); return owned(s, k) ? k : LOOK_DEFAULT[s]! }
    return Dress(cloth: pick("cloth"), cue: pick("cue"), chalk: pick("chalk"), rail: pick("rail"), balls: pick("balls"), room: "hall")
  }
  static var haptics: Bool { bool("haptics", true) }
  /* rulesFor: the ruleset in settings for 8, 9 and 10-ball, the call mode for all */
  static func rules(_ kind: String) -> RuleSet {
    var c = CallConfig(); c.mode = calls
    let id = kind == "8" ? rules8 : kind == "9" ? rules9 : kind == "10" ? rules10 : nil
    var r = makeRules(kind, ruleset: id, call: c, race: kind == "straight" ? race141 : nil)
    /* the setup's Stalemate (8 and 9-ball): re-rack after STALEMATE_INNINGS dry innings each */
    if (kind == "8" || kind == "9") && bool("stalemate", false) { r.stalemate = 6 }
    return r
  }
  /* the two-player rulesets a game offers (rulesetsFor: no ring sets) */
  static func rulesets(_ kind: String) -> [RuleSet] {
    RULESETS.values.filter { $0.game == kind && !$0.ring }.sorted { $0.id < $1.id }
  }
}

struct SettingsView: View {
  @AppStorage("felt.settings.rules8") private var rules8 = DEFAULT_RULESET["8"]!
  @AppStorage("felt.settings.rules9") private var rules9 = DEFAULT_RULESET["9"]!
  @AppStorage("felt.settings.rules10") private var rules10 = DEFAULT_RULESET["10"]!
  @AppStorage("felt.settings.calls") private var calls = "official"
  @AppStorage("felt.settings.guide") private var guide = "full"
  @AppStorage("felt.settings.autoAim") private var autoAim = true
  @AppStorage("felt.settings.table") private var table = "7"
  @AppStorage("felt.settings.pockets") private var pockets = "regulation"
  @AppStorage("felt.settings.race141") private var race141 = 50
  @AppStorage("felt.settings.snookerTable") private var snookerTable = "compact"
  @AppStorage("felt.settings.snookerFrames") private var snookerFrames = 1
  @AppStorage("felt.settings.bumperTable") private var bumperTable = "octagon"
  @AppStorage("felt.settings.caromRace") private var caromRace = 10
  @AppStorage("felt.settings.caromCush") private var caromCush = 3
  @AppStorage("felt.settings.sound") private var sound = true
  @AppStorage("felt.settings.haptics") private var haptics = true
  @AppStorage("felt.settings.dress") private var dressMode = "game"
  @AppStorage("felt.settings.view") private var tableView = "top"
  @AppStorage("felt.settings.intro") private var intro = true
  @AppStorage("felt.settings.viewAfter") private var viewAfter = "pull"
  @AppStorage("felt.settings.look.cloth") private var lookCloth = "green"
  @AppStorage("felt.settings.look.cue") private var lookCue = "house"
  @AppStorage("felt.settings.look.chalk") private var lookChalk = "blue"
  @AppStorage("felt.settings.look.rail") private var lookRail = "walnut"
  @AppStorage("felt.settings.look.balls") private var lookBalls = "classic"

  var body: some View {
    List {
      Section {
        rules("8-Ball", "8", $rules8)
        rules("9-Ball", "9", $rules9)
        rules("10-Ball", "10", $rules10)
        Picker("Called Shots", selection: $calls) {
          Text("Off").tag("off"); Text("8-Ball Only").tag("eight"); Text("Official").tag("official"); Text("All").tag("all")
        }
      } header: { Text("Rules") } footer: { Text("Official calls what the rules call; All calls every shot.") }
      Section {
        Picker("Aim Guide", selection: $guide) { Text("Full").tag("full"); Text("Short").tag("short"); Text("Off").tag("off") }
        Toggle("Auto Aim", isOn: $autoAim)
      } header: { Text("Aiming") }
      Section {
        Picker("Pool Table", selection: $table) { Text("7 ft").tag("7"); Text("9 ft").tag("9") }.pickerStyle(.segmented)
        Picker("Pockets", selection: $pockets) { Text("Regulation").tag("regulation"); Text("Generous").tag("generous") }.pickerStyle(.segmented)
        Picker("Straight Pool Race", selection: $race141) { Text("25").tag(25); Text("50").tag(50); Text("100").tag(100); Text("150").tag(150) }
      } header: { Text("Pool") } footer: { Text("8, 9, 10-ball, straight pool and rotation. Chinese 8-ball plays on its own table.") }
      Section {
        Picker("Table", selection: $snookerTable) { Text("10 ft").tag("compact"); Text("12 ft").tag("full") }.pickerStyle(.segmented)
        Picker("Frames", selection: $snookerFrames) { Text("1 Frame").tag(1); Text("Best of 3").tag(3) }.pickerStyle(.segmented)
      } header: { Text("Snooker") }
      Section {
        Picker("Table", selection: $bumperTable) { Text("Octagon").tag("octagon"); Text("Rectangle").tag("rect") }.pickerStyle(.segmented)
      } header: { Text("Bumper Pool") }
      Section {
        Picker("Race", selection: $caromRace) { Text("5").tag(5); Text("10").tag(10); Text("15").tag(15) }.pickerStyle(.segmented)
        Picker("Cushions", selection: $caromCush) { Text("One").tag(1); Text("Three").tag(3) }.pickerStyle(.segmented)
      } header: { Text("Three-Cushion") }
      /* Settings > Graphics: Table Dressing, and My Look's slots, each listing only what is unlocked; picking one switches
         to My Look */
      Section {
        Picker("Table View", selection: $tableView) { Text("Top Down").tag("top"); Text("3D").tag("3d") }.pickerStyle(.segmented)
        if tableView == "3d" { Picker("After the Shot", selection: $viewAfter) { Text("Pull Back").tag("pull"); Text("Top Down").tag("top"); Text("Stay").tag("stay") } }
        Picker("Table Dressing", selection: $dressMode) { Text("By Game").tag("game"); Text("My Look").tag("mine") }.pickerStyle(.segmented)
        look("Cloth", "cloth", $lookCloth)
        look("Cue", "cue", $lookCue)
        look("Chalk", "chalk", $lookChalk)
        look("Rails", "rail", $lookRail)
        look("Balls", "balls", $lookBalls)
        Toggle("Opening Animation", isOn: $intro)
      } header: { Text("Graphics") } footer: { Text("By Game dresses each game as itself: its cloth, rails, balls, cue and room. My Look wears your choices below on every game. Picking one switches to My Look. A career match wears what its player equipped.") }
      Section {
        Toggle("Sound", isOn: $sound)
        Toggle("Haptics", isOn: $haptics)
      } header: { Text("Sound") }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
  private func look(_ title: String, _ slot: String, _ sel: Binding<String>) -> some View {
    let pick = Binding<String>(get: { sel.wrappedValue }, set: { sel.wrappedValue = $0; dressMode = "mine" })
    return Picker(title, selection: pick) {
      ForEach(Dress.ORDER[slot]!.filter { Prefs.owned(slot, $0) }, id: \.self) { k in Text(Dress.NAMES[slot]![k]!).tag(k) }
    }
  }
  private func rules(_ title: String, _ kind: String, _ sel: Binding<String>) -> some View {
    Picker(title, selection: sel) { ForEach(Prefs.rulesets(kind), id: \.id) { r in Text(r.id.hasSuffix("house") ? "House Rules" : "WPA").tag(r.id) } }
  }
}

/* rulesInfoOf: the (i) popover's words for a game: the ruleset's name (RULES_SRC), its description, the choices' fine print */
enum RulesInfo {
  static let SRC = ["8-house": "House rules", "8-wpa": "WPA world standardized rules", "9-house": "House rules", "9-wpa": "WPA world standardized rules, with the push out",
    "10-wpa": "WPA world standardized rules", "straight-wpa": "14.1 continuous, WPA world standardized rules",
    "rotation": "House rules, after the BCA game", "bumper": "House rules", "carom": "UMB rules, simplified", "snooker": "WPBSA rules, simplified",
    "heyball": "WPA Rules of Heyball, 2025"]
  static let DESC = [
    "8-house": "Hit one of your group first, pot it to carry on. No calls unless your settings ask for them. An 8 on the break is spotted and the breaker carries on.",
    "8-wpa": "Call every shot that is not obvious, and the 8 always with its pocket. A legal break pots a ball or drives four to the cushions. An 8 on the break: spot it or re-rack. A ball off the table on the break: the table as it lies, or ball in hand behind the head string.",
    "9-house": "Lowest ball first. A legal 9 wins, early or on the break. Three fouls in a row lose.",
    "9-wpa": "Lowest ball first, any legal 9 wins. Push out on the shot after the break; your opponent may hand it back. A legal break pots a ball or drives four to the cushions, and three must drop or lie past the head string, or your opponent may hand it back and any 9 is spotted. Three fouls lose.",
    "10-wpa": "Lowest ball first, and call your shots; an obvious one is called from your aim, and there is no safety. The 10 wins only when called as the last ball; on the break or early it is spotted. Push out after the break. Three fouls lose.",
    "straight-wpa": "Any ball, called with its pocket: a point each. With one ball left the other 14 are racked again. A foul costs a point, three in a row 15 more and a new break.",
    "rotation": "Lowest ball first; every ball potted on a legal shot scores its number. 61 wins. Balls potted on a foul are spotted.",
    "bumper": "Five balls each round the posts to the far cup; the marked ball first.",
    "carom": "Your cue ball meets both others, with three cushions before the second. A point each.",
    "snooker": "A red, then a colour, until the reds are gone; then the colours in order.",
    "heyball": "Balls potted on the break leave the table open: the first legal pot after it chooses your group, the group of the ball you hit first. A legal break pots a ball or drives four to the cushions. A foul on the break: ball in hand behind the head string, or a re-rack. Any other foul: ball in hand anywhere. The 8 last, in any pocket: nothing is called."]
  static func of(_ kind: String, title: String) -> (title: String, src: String, ps: [String]) {
    let id = kind == "8" ? Prefs.rules8 : kind == "9" ? Prefs.rules9 : kind == "10" ? Prefs.rules10 : DEFAULT_RULESET[kind]!
    var ps = [DESC[id] ?? ""]
    if kind == "8" || kind == "9" { ps.append(Prefs.bool("stalemate", false) ? "Stalemate: after 6 innings with no ball potted, the balls are racked again." : "Stalemate: play on. A rack with no ball potted is played out.") }
    if kind == "straight" { ps.append("First to \(Prefs.race141) points wins.") }
    if kind == "heyball" { ps.append("The 8 loses the rack if it drops before your group is clear, on a foul, or off the table. An 8 on the break is spotted, or the breaker breaks again.") }
    if kind == "carom" { ps.append("First to \(Prefs.caromRace) points wins." + (Prefs.caromCush == 1 ? " The easier game: one cushion before the second ball is enough." : "")) }
    if kind == "snooker" { ps.append(Prefs.snookerFrames == 3 ? "Best of three frames." : "One frame."); ps.append("After a foul the player fouled chooses: play on, have it played again, or take a free ball when snookered.") }
    return (title + " Rules", SRC[id] ?? "", ps)
  }
}
