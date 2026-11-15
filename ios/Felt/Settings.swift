/* Settings (page 6, PREF_PAGES): the settings that change play, as the page keeps them in felt.settings, with its
   defaults (loadSettings): the rules for 8, 9 and 10-ball (RULESETS, the two-player sets), called shots
   (CALL_MODES), the aim guide and auto aim; the tables (pool's size and pockets for every pool game, snooker's
   table and frames, the bumper table's shape, carom's race and cushions); sound and haptics. Read when a game starts. */
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
  static var snookerTable: String { str("snookerTable", "compact") }
  static var snookerFrames: Int { int("snookerFrames", 1) }
  static var bumperTable: String { str("bumperTable", "octagon") }
  static var caromRace: Int { int("caromRace", 10) }
  static var caromCush: Int { int("caromCush", 3) }
  static var sound: Bool { bool("sound", true) }
  static var haptics: Bool { bool("haptics", true) }
  /* rulesFor: the ruleset in settings for 8, 9 and 10-ball, the call mode for all */
  static func rules(_ kind: String) -> RuleSet {
    var c = CallConfig(); c.mode = calls
    let id = kind == "8" ? rules8 : kind == "9" ? rules9 : kind == "10" ? rules10 : nil
    return makeRules(kind, ruleset: id, call: c)
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
  @AppStorage("felt.settings.snookerTable") private var snookerTable = "compact"
  @AppStorage("felt.settings.snookerFrames") private var snookerFrames = 1
  @AppStorage("felt.settings.bumperTable") private var bumperTable = "octagon"
  @AppStorage("felt.settings.caromRace") private var caromRace = 10
  @AppStorage("felt.settings.caromCush") private var caromCush = 3
  @AppStorage("felt.settings.sound") private var sound = true
  @AppStorage("felt.settings.haptics") private var haptics = true

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
      } header: { Text("Pool") } footer: { Text("8, 9 and 10-ball. Chinese 8-ball plays on its own table.") }
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
      Section {
        Toggle("Sound", isOn: $sound)
        Toggle("Haptics", isOn: $haptics)
      } header: { Text("Sound") }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
  }
  private func rules(_ title: String, _ kind: String, _ sel: Binding<String>) -> some View {
    Picker(title, selection: sel) { ForEach(Prefs.rulesets(kind), id: \.id) { r in Text(r.id.hasSuffix("house") ? "House Rules" : "WPA").tag(r.id) } }
  }
}
