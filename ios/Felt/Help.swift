/* index.html 6, How to play: the topics' list (#howList) and a page per topic (rules as rows, the fine print, the action
   pinned at the foot), in the page's own words (help.json, taken from its markup by tools/ios-help.cjs and checked by
   tests/ios-check.cjs). The actions: Play the Lesson, a game's tutorial, Open More Modes, the Drills, the Career. */
import SwiftUI

struct HelpTopic: Decodable, Identifiable, Hashable {
  struct Act: Decodable, Hashable { let id: String, tut: String?, text: String }
  let id: String, title: String, sub: String, rules: [[String]], fine: [String], act: Act?
  static let all: [HelpTopic] = {
    guard let u = Bundle.main.url(forResource: "help", withExtension: "json"), let d = try? Data(contentsOf: u),
          let o = try? JSONDecoder().decode([String: [HelpTopic]].self, from: d) else { return [] }
    return o["topics"] ?? []
  }()
  /* the topic's tile: a game's ball (the page's .htile), else a glyph */
  var ball: (Int, String?)? { ["8": (8, nil), "9": (9, nil), "10": (10, nil), "Str": (14, nil), "Rot": (15, nil), "Hey": (8, nil), "Bump": (0, "bb"), "Carom": (0, "bc"), "Snk": (0, "bsblk")][id] }
  var glyph: String { ["Ctl": "hand.draw", "Call": "scope", "Solo": "figure.pool.swim", "Cue": "arrow.up.right", "Modes": "square.grid.2x2", "Drills": "target", "Career": "trophy"][id] ?? "questionmark" }
}

/* what a topic's action does, handed in by the home */
struct HelpActions {
  var lesson: () -> Void, tutorial: (String) -> Void, modes: () -> Void, drills: () -> Void, career: () -> Void
}

struct HelpView: View {
  let acts: HelpActions
  /* howList: a row per topic, its picture on the accent's tile (a game's ball, else the topic's glyph), the name and
     line, 54 pt; the title the list's head, as the page's header */
  var body: some View {
    List {
      Section {
        ForEach(HelpTopic.all) { t in
          NavigationLink { HelpPage(t: t, acts: acts) } label: {
            HStack(spacing: 12) {
              Group {
                if let b = t.ball { BallDot(n: b.0, style: b.1).frame(width: 18, height: 18) }
                else { Image(systemName: t.glyph).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white) }
              }
              .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.12, green: 0.42, blue: 0.29)))
              .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.system(size: 17))
                Text(t.sub).font(.system(size: 15)).foregroundStyle(.secondary)
              }
            }
          }
          .accessibilityIdentifier("tab" + t.id)
          .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
      } header: {
        Text("How to Play").font(.system(size: 28, weight: .bold)).foregroundStyle(Color.white).textCase(nil).padding(.leading, -4).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
      }
    }
    .environment(\.defaultMinListRowHeight, 54)
    .contentMargins(.top, 0, for: .scrollContent)
    .navigationTitle("").navigationBarTitleDisplayMode(.inline)
  }
}

struct HelpPage: View {
  let t: HelpTopic
  let acts: HelpActions
  var body: some View {
    List {
      if !t.rules.isEmpty {
        Section {
          ForEach(Array(t.rules.enumerated()), id: \.offset) { _, r in
            VStack(alignment: .leading, spacing: 3) {
              if !r[0].isEmpty { Text(r[0]).font(.body.weight(.semibold)) }
              Text(r[1]).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
          }
        }
      }
      if !t.fine.isEmpty {
        Section("Fine Print") {
          ForEach(Array(t.fine.enumerated()), id: \.offset) { _, f in Text(f).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if let a = t.act {
        Button { act(a) } label: { Text(a.text).font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
          .background(Capsule().fill(.white)).foregroundStyle(.black).padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
          .accessibilityIdentifier(a.id)
      }
    }
    .navigationTitle(t.title)
  }
  func act(_ a: HelpTopic.Act) {
    if let k = a.tut { acts.tutorial(k); return }
    switch a.id {
    case "lessonAgain": acts.lesson()
    case "helpModes": acts.modes()
    case "helpDrills": acts.drills()
    case "helpCareer": acts.career()
    default: break
    }
  }
}
