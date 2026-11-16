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
  /* an Int, or a numeric string (a launch argument's default arrives as one; @AppStorage converts it too) */
  static func int(_ k: String, _ def: Int) -> Int { d.object(forKey: "felt.settings." + k) as? Int ?? d.string(forKey: "felt.settings." + k).flatMap { Int($0) } ?? def }
  static func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: "felt.settings." + k) as? Bool ?? def }
  static var rules8: String { str("rules8", DEFAULT_RULESET["8"]!) }
  static var rules9: String { str("rules9", DEFAULT_RULESET["9"]!) }
  static var rules10: String { str("rules10", DEFAULT_RULESET["10"]!) }
  /* settings.calls (sv 2): the called-shot configuration (makeCall, sim 1e) and the page's own switches (CALL_UI), a key
     each, as the page names them (calls.mode, calls.detail, calls.safety, ...), each field checked as loadSettings does */
  static func callsStored() -> [String: Any] {
    var o: [String: Any] = [:]
    for k in CALL_KEYS { if let v = d.object(forKey: "felt.settings.calls." + k) { o[k] = v } }
    return o
  }
  static var callConfig: CallConfig { makeCall(callsStored()) }
  static var callUI: CallUI { makeCallUI(callsStored()) }
  static var guide: String { str("guide", "full") }
  static var autoAim: Bool { bool("autoAim", true) }
  static var table: String { str("table", "7") }
  static var pockets: String { str("pockets", "regulation") }
  /* loadSettings' phone: min(innerWidth, innerHeight) < 700 (every iPad is 744 or more either way); set at launch by
     boot(), before any view reads it */
  nonisolated(unsafe) static var phone = true
  /* the defaults that go by it, registered so @AppStorage reads them too (a stored value wins) */
  @MainActor static func boot() {
    let s = UIScreen.main.bounds.size
    phone = min(s.width, s.height) < 700
    d.register(defaults: ["felt.settings.snookerTable": phone ? "compact" : "full", "felt.settings.race141": phone ? 50 : 100])
    /* migrateSettings for the calls: an older build kept the mode alone at felt.settings.calls; it becomes calls.mode */
    if let m = d.string(forKey: "felt.settings.calls") {
      if d.object(forKey: "felt.settings.calls.mode") == nil, CALL_MODES.contains(m) { d.set(m, forKey: "felt.settings.calls.mode") }
      d.removeObject(forKey: "felt.settings.calls")
    }
    /* loadSettings: a stored field it would not take is dropped, so the default stands (and the controls show it) */
    for k in callsInvalid(callsStored()) { d.removeObject(forKey: "felt.settings.calls." + k) }
  }
  /* snooker's table: compact (10 ft) on a phone, full (12 ft) on a bigger screen, as loadSettings picks it */
  /* 14.1's race: 50 on a phone, 100 on a bigger screen, as loadSettings picks it */
  static var race141: Int { int("race141", phone ? 50 : 100) }
  static var snookerTable: String { str("snookerTable", phone ? "compact" : "full") }
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
  /* reducedMotion(): Settings' Reduce Motion, or the system's, whichever says so */
  static var reduceMotion: Bool { bool("reduceMotion", false) || UIAccessibility.isReduceMotionEnabled }
  /* settings.names: the two players' names, as given at setup (cleanName: spaces collapsed, trimmed, 12 at most) */
  static func cleanName(_ v: String) -> String { String(v.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(12)) }
  static var names: [String] {
    get { let a = d.stringArray(forKey: "felt.settings.names") ?? []; return [a.count > 0 ? cleanName(a[0]) : "", a.count > 1 ? cleanName(a[1]) : ""] }
    set { d.set(newValue.map(cleanName), forKey: "felt.settings.names") }
  }
  /* After the Shot (settings.viewAfter): 'pull' to the overview, 'top' the roll top-down, 'stay' the aiming pose */
  static var viewAfter: String { str("viewAfter", "pull") }
  /* Camera (settings.camera, 3b): 'auto' Follow, 'off' Fixed. The follow camera is opt-in (it gave players vertigo): a
     choice is kept only with camV 2, which its control writes with it */
  static var camera: String { let c = str("camera", "off"); return int("camV", 0) == 2 && ["auto", "off"].contains(c) ? c : "off" }
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
  /* rulesFor: the ruleset in settings for 8, 9 and 10-ball, the calls for all */
  static func rules(_ kind: String) -> RuleSet {
    let c = callConfig
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
  /* rulesLocked: opened from the pause menu over an event's game (a career, tournament or party match), whose rules are
     its own: the rules and the calls an event may lock are shown and not changed (#lockNote) */
  var locked = false
  @AppStorage("felt.settings.rules8") private var rules8 = DEFAULT_RULESET["8"]!
  @AppStorage("felt.settings.rules9") private var rules9 = DEFAULT_RULESET["9"]!
  @AppStorage("felt.settings.calls.mode") private var callMode = "official"
  @AppStorage("felt.settings.calls.detail") private var callDetail = "pocket"
  @AppStorage("felt.settings.calls.obvious") private var callObvious = true
  @AppStorage("felt.settings.calls.safety") private var callSafety = true
  @AppStorage("felt.settings.calls.eight") private var callEight = false
  @AppStorage("felt.settings.calls.change") private var callChange = true
  @AppStorage("felt.settings.calls.highlight") private var callHighlight = true
  @AppStorage("felt.settings.calls.confirm") private var callConfirm = true
  @AppStorage("felt.settings.calls.sound") private var callSound = true
  @AppStorage("felt.settings.calls.warn") private var callWarn = true
  @AppStorage("felt.settings.calls.history") private var callHistory = true
  @AppStorage("felt.settings.guide") private var guide = "full"
  @AppStorage("felt.settings.autoAim") private var autoAim = true
  @AppStorage("felt.settings.race141") private var race141 = 50
  @AppStorage("felt.settings.snookerFrames") private var snookerFrames = 1
  @AppStorage("felt.settings.caromRace") private var caromRace = 10
  @AppStorage("felt.settings.sound") private var sound = true
  @AppStorage("felt.settings.haptics") private var haptics = true
  @AppStorage("felt.settings.dress") private var dressMode = "game"
  @AppStorage("felt.settings.view") private var tableView = "top"
  @AppStorage("felt.settings.intro") private var intro = true
  @AppStorage("felt.settings.viewAfter") private var viewAfter = "pull"
  @AppStorage("felt.settings.camera") private var camera = "off"
  @AppStorage("felt.settings.camV") private var camV = 0
  @AppStorage("felt.settings.look.cloth") private var lookCloth = "green"
  @AppStorage("felt.settings.look.cue") private var lookCue = "house"
  @AppStorage("felt.settings.look.chalk") private var lookChalk = "blue"
  @AppStorage("felt.settings.look.rail") private var lookRail = "walnut"
  @AppStorage("felt.settings.look.balls") private var lookBalls = "classic"

  @AppStorage("felt.settings.stalemate") private var stalemate = false
  @AppStorage("felt.settings.hand") private var hand = "right"
  @AppStorage("felt.settings.vol") private var vol = 100
  @AppStorage("felt.settings.volFx") private var volFx = 100
  @AppStorage("felt.settings.replays") private var replays = true
  @AppStorage("felt.settings.reduceMotion") private var reduceMotion = false
  @AppStorage("felt.settings.hcAim") private var hcAim = false
  @AppStorage("felt.settings.marks") private var marks = false
  @AppStorage("felt.settings.text") private var text = 100
  @AppStorage("felt.settings.keyShoot") private var keyShoot = false
  @AppStorage("felt.settings.bar") private var bar = "mid"
  /* the list (prefsList): a row per page (PREF_PAGES), its icon, name and line, pushed from the right */
  var body: some View {
    CapList {
      Section {
        NavigationLink { page("Gameplay") { gameplay } } label: { PrefRow(icon: "circle.grid.2x1.fill", name: "Gameplay", line: locked ? "Locked by event: this match plays its own rules" : "Rules, called shots, races, aim guide") }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        NavigationLink { page("Controls") { controls } } label: { PrefRow(icon: "switch.2", name: "Controls", line: "Auto aim, layout, power bar") }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        NavigationLink { page("Graphics") { graphics } } label: { PrefRow(icon: "photo", name: "Graphics", line: "Cloth, camera, replay, motion") }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        NavigationLink { page("Audio and Haptics") { audio } } label: { PrefRow(icon: "speaker.wave.2.fill", name: "Audio and Haptics", line: "Volume, table sounds, haptics") }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        NavigationLink { page("Accessibility") { a11y } } label: { PrefRow(icon: "figure.stand", name: "Accessibility", line: "Ball marks, high-contrast aim, motion, text size") }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        NavigationLink { page("About") { about } } label: { PrefRow(icon: "info.circle", name: "About", line: "This build") }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
      } header: {
        /* the page's header row: "Settings" in Title 1, by the back button */
        Text("Settings").font(.system(size: 28, weight: .bold)).foregroundStyle(Color.white).textCase(nil).padding(.leading, -4).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
      }
    }
    .environment(\.defaultMinListRowHeight, 54)
    .contentMargins(.top, 0, for: .scrollContent)
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .tint(.primary)
  }
  private func page<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
    CapList { c() }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).tint(.primary)
  }
  /* ppGame: Default Rules, Races, Called Shots, Aim Guide; under an event's rules the note over them (#lockNote) */
  @ViewBuilder private var gameplay: some View {
    if locked {
      Section { Text("Locked by event: this match plays its own rules, whatever is set here.").font(.footnote).foregroundStyle(.secondary) }
        .accessibilityIdentifier("lockNote")
    }
    Section {
      rules("8-Ball", "8", $rules8)
      rules("9-Ball", "9", $rules9)
      Toggle("House Re-Rack on a Stalemate (8 and 9-Ball)", isOn: $stalemate)
    } header: { Text("Default Rules") } footer: { Text("A new game starts on these. An event (a career match) brings its own.") }
      .disabled(locked)
    Section {
      Picker("Straight Pool (14.1), Points", selection: $race141) { ForEach([25, 50, 100, 150], id: \.self) { Text("\($0)").tag($0) } }
      Picker("Three-Cushion, Points", selection: $caromRace) { Text("5").tag(5); Text("10").tag(10); Text("15").tag(15) }
      Picker("Snooker, Frames", selection: $snookerFrames) { Text("One Frame").tag(1); Text("Best of 3").tag(3) }
    } header: { Text("Races") }
    /* the calls (settings.calls): the Call and Declaration pop-ups, then the switches (TOGS); an event locks those two and
       the rules' four (LOCKABLE), never the page's own five */
    Section {
      Picker("Call", selection: $callMode) {
        Text("Off").tag("off"); Text("8-Ball Only").tag("eight"); Text("Official Rules").tag("official"); Text("All Shots").tag("all"); Text("Career Rules").tag("career")
      }.disabled(locked)
      Picker("Declaration", selection: $callDetail) {
        Text("Ball Only").tag("ball"); Text("Ball and Pocket").tag("pocket"); Text("Ball, Pocket and Rails (Custom)").tag("rails"); Text("Strict (Custom)").tag("strict")
      }.disabled(locked)
      Group {
        Toggle("Auto-Call Obvious Shots", isOn: $callObvious)
        Toggle("Require Safety Declarations", isOn: $callSafety)
        Toggle("Require Called 8 Pocket", isOn: $callEight)
        Toggle("Allow Changing the Call Before Striking", isOn: $callChange)
      }.disabled(locked)
      Toggle("Highlight Called Ball and Pocket", isOn: $callHighlight)
      Toggle("Show Declaration Confirmation", isOn: $callConfirm)
      Toggle("Called-Shot Sound", isOn: $callSound)
      Toggle("Invalid-Shot Warnings", isOn: $callWarn)
      Toggle("Declaration History", isOn: $callHistory)
    } header: { Text("Called Shots") } footer: { Text("Official rules: each game's own (8-ball WPA, 10-ball and straight pool call every shot; 9-ball and rotation none). A missed call is not a foul: the turn ends.") }
    Section {
      Picker("Aim Guide", selection: $guide) { Text("Full").tag("full"); Text("Short").tag("short"); Text("Off").tag("off") }.pickerStyle(.segmented).labelsHidden()
    } header: { Text("Aim Guide") } footer: { Text("Full runs both balls' paths out; short shows the ghost ball and a stub; off draws nothing.") }
  }
  /* ppCtl: Auto Aim (the page's Layout group, the hand and the power bar's place, is not ported) */
  @ViewBuilder private var controls: some View {
    Section {
      Picker("Auto Aim", selection: $autoAim) { Text("On").tag(true); Text("Off").tag(false) }.pickerStyle(.segmented).labelsHidden()
    } header: { Text("Auto Aim") } footer: { Text("Auto aim starts each turn pointed at the ball to play next. The cut is up to you.") }
    Section {
      Picker("Hand", selection: $hand) { Text("Right-Handed").tag("right"); Text("Left-Handed").tag("left") }
      Picker("Power Bar", selection: $bar) { Text("Middle").tag("mid"); Text("At the Edge").tag("edge") }
    } header: { Text("Layout") } footer: { Text("Left-handed mirrors the controls: the strip under the table runs the other way. At the edge puts the power bar under your thumb, at the end of the strip.") }
  }
  /* ppGfx: Table, Look, Table View, After the Shot, Opening */
  @ViewBuilder private var graphics: some View {
    Section {
      Picker("Table Dressing", selection: $dressMode) { Text("By Game").tag("game"); Text("My Look").tag("mine") }
      look("Cloth", "cloth", $lookCloth)
    } header: { Text("Table") } footer: { Text("By Game dresses each game as itself: its cloth, rails, balls, cue and room. My Look wears your choices below on every game. Picking one switches to My Look. A career match wears what its player equipped.") }
    Section {
      look("Cue", "cue", $lookCue)
      look("Chalk", "chalk", $lookChalk)
      look("Rails", "rail", $lookRail)
      look("Balls", "balls", $lookBalls)
    } header: { Text("Look") } footer: { Text("More cloths, cues, chalk, rails and ball sets come from the career shop and are yours here once owned. A look never changes a shot.") }
    Section {
      Picker("Table View", selection: $tableView) { Text("Top Down").tag("top"); Text("3D").tag("3d") }.pickerStyle(.segmented).labelsHidden()
    } header: { Text("Table View") } footer: { Text("3D puts the camera behind the cue ball: drag across the table to aim, up and down to tilt, pinch to move in or out. The 3D button on the table switches too.") }
    Section {
      Picker("After the Shot", selection: $viewAfter) { Text("Pull Back").tag("pull"); Text("Top Down").tag("top"); Text("Stay").tag("stay") }.pickerStyle(.segmented).labelsHidden()
    } header: { Text("After the Shot") } footer: { Text("In 3D, once the cue strikes. Pull Back rises smoothly to a view of the whole table, holds it while the balls roll, then comes back down behind the cue ball. Top Down shows the roll on the flat table. Stay keeps your aiming view. Your pitch and distance are always kept.") }
    /* #camAuto, #camOff: the choice saved with camV 2 (loadSettings keeps no other) */
    Section {
      Picker("Camera", selection: Binding(get: { camV == 2 && ["auto", "off"].contains(camera) ? camera : "off" }, set: { camV = 2; camera = $0 })) { Text("Follow").tag("auto"); Text("Fixed").tag("off") }.pickerStyle(.segmented).labelsHidden()
    } header: { Text("Camera") } footer: { Text("Follow moves in a little on the action while the balls roll, and close on replays. Aiming always shows the whole table.") }
    Section {
      Picker("Replays", selection: $replays) { Text("Offer").tag(true); Text("Never").tag(false) }.pickerStyle(.segmented).labelsHidden()
    } header: { Text("Replays") } footer: { Text("Offer puts a Replay pill over the table after a shot. Never keeps the table clear after every shot.") }
    Section {
      Toggle("Reduce Motion", isOn: $reduceMotion)
    } header: { Text("Motion") } footer: { Text("On: no sliding sheets, swings or pulses, whatever the system says. Off: follows the system setting.") }
    Section {
      Toggle("Opening Animation", isOn: $intro)
    } header: { Text("Opening") } footer: { Text("A break under the lamp each time felt opens, then the home. A tap skips it. With Reduce Motion the home simply fades in.") }
  }
  /* ppAud: Sound (on or off, the master volume and the table sounds), Haptics */
  @ViewBuilder private var audio: some View {
    Section {
      Picker("Sound", selection: $sound) { Text("On").tag(true); Text("Off").tag(false) }.pickerStyle(.segmented).labelsHidden()
      slider("Master Volume", $vol)
      slider("Table Sounds", $volFx)
    } header: { Text("Sound") } footer: { Text("Table sounds are the balls, cushions, cue and pockets; the master volume is everything, the game's little cues too. felt has no music or ambience.") }
    Section {
      Picker("Haptics", selection: $haptics) { Text("On").tag(true); Text("Off").tag(false) }.pickerStyle(.segmented).labelsHidden()
    } header: { Text("Haptics") } footer: { Text("A tick for a hard contact, two for a pot, three for a win.") }
  }
  /* ppA11y: Seeing the Table (ball marks, high-contrast aim, Reduce Motion), Text Size, Keyboard */
  @ViewBuilder private var a11y: some View {
    Section {
      Toggle("Colour-Blind Safe Ball Marks", isOn: $marks)
      Toggle("High-Contrast Aim Line", isOn: $hcAim)
      Toggle("Reduce Motion", isOn: $reduceMotion)
    } header: { Text("Seeing the Table") } footer: { Text("Ball marks put an upright badge on every ball: solids light with a dark number, stripes dark with a light one, snooker's colours their value, carom's yellow Y and red R, bumper pool's reds R. Tell them apart without colour. High contrast draws the aim line, the ghost ball and the paths wider, white over a near-black edge, on any cloth.") }
    /* settings.text (100, 115, 130): Large and Larger zoom the menus and sheets (data-text); the table keeps its size */
    Section {
      Picker("Text Size", selection: $text) { Text("Default").tag(100); Text("Large").tag(115); Text("Larger").tag(130) }.pickerStyle(.segmented).labelsHidden()
        .accessibilityIdentifier("textSize")
    } header: { Text("Text Size") } footer: { Text("Menus, sheets, banners and the call bar grow; the table keeps its size.") }
    /* settings.keyShoot (audit F7): off, no key ever shoots */
    Section {
      Toggle("Space Drives the Power Bar", isOn: $keyShoot)
    } header: { Text("Keyboard") } footer: { Text("For keyboard and switch players. Up and down set the bar's mark, then Space or Enter: the bar pulls to the mark and lets go, as a finger would. Any other key stops it. Off, no key ever shoots.") }
  }
  /* ppAbout: felt, and the sound credits (CREDITS.md) */
  @ViewBuilder private var about: some View {
    Section {
      VStack(alignment: .leading, spacing: 2) { Text("felt").font(.headline); Text("Pool, snooker and carom in one app. Offline, no account, nothing leaves the device.").font(.subheadline).foregroundStyle(.secondary) }
      Text("Settings, records and the career stay on this device.").font(.subheadline).foregroundStyle(.secondary)
    }
    Section {
      credit("Ball Clacks", "Za-Games, bsumusictech, RossJuterbock, 13FPanska_Marval_Lukas and csaszi, on Freesound.")
      credit("Cue", "craigsmith and csaszi, on Freesound.")
      credit("Cushions", "allberto and 13FPanska_Marval_Lukas, on Freesound.")
      credit("Pockets", "Yarmonics and Caitlin_100, on Freesound.")
      credit("Break and Roll", "RossJuterbock and csaszi, on Freesound.")
    } header: { Text("Sound Credits") } footer: { Text("Every recording is CC0 (public domain), trimmed and levelled for felt.") }
  }
  /* a volume row (#volRow): its name, the level in percent, a slider 0 to 100 in steps of 5 */
  private func slider(_ t: String, _ v: Binding<Int>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack { Text(t); Spacer(); Text("\(v.wrappedValue)%").foregroundStyle(.secondary).monospacedDigit() }
      Slider(value: Binding(get: { Double(v.wrappedValue) }, set: { v.wrappedValue = Int($0.rounded()) }), in: 0...100, step: 5).tint(Color(rgb: 0x3d, 0xdc, 0x84))
        .accessibilityLabel(t).accessibilityValue("\(v.wrappedValue) percent")
    }
    .padding(.vertical, 4)
  }
  private func credit(_ t: String, _ w: String) -> some View {
    VStack(alignment: .leading, spacing: 2) { Text(t); Text(w).font(.subheadline).foregroundStyle(.secondary) }
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

/* a row of the settings list (.prow): its icon on the accent's tile, the name, the line, a chevron */
struct PrefRow: View {
  let icon: String, name: String, line: String
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.12, green: 0.42, blue: 0.29)))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(name).font(.system(size: 17))
        Text(line).font(.system(size: 15)).foregroundStyle(.secondary)
      }
    }
  }
}

/* the full-screen sheets (How to play, Settings, Stats, Drills, the career, the modes): above 600 pt wide a card of 560
   at most, centred (:is(#helpSheet, #prefsSheet, #statsSheet, #drillSheet, #careerSheet, #modesSheet) .sheet); full
   width on a phone, either way up */
extension View {
  @ViewBuilder func pageCap(_ w: CGFloat = 560) -> some View {
    if Prefs.phone { self } else { frame(maxWidth: w, alignment: .leading).frame(maxWidth: .infinity) }
  }
}
/* a sheet's inset grouped list, capped as pageCap */
struct CapList<C: View>: View {
  let content: C
  init(@ViewBuilder content: () -> C) { self.content = content() }
  var body: some View { List { content }.pageCap() }
}
