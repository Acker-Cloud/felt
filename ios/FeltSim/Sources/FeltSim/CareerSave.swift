/* index.html's career persistence, line for line: a save is 'F2|<checksum base 36>|<length>|<json>' (the length and
   the checksum over the JSON's UTF-16 units, as the page counts them), written atomically (the temp copy first, read
   back; the last good save to .bak; then the main key, read back and checked), loaded from main, else the temp copy,
   else the backup; the slot index beside them. The store is the page's localStorage: `store`, with `persist` told of
   every write so the app can keep it on disk. */
import Foundation

extension CareerEngine {
  func sget(_ k: String) -> String? { store[k] }
  @discardableResult func sset(_ k: String, _ v: String) -> Bool { store[k] = v; persist?(k, v); return true }
  func sdel(_ k: String) { store[k] = nil; persist?(k, nil) }
  func kMain(_ id: String) -> String { Self.c("K_PRE").s + id }
  func kTmp(_ id: String) -> String { Self.c("K_PRE").s + id + ".tmp" }
  func kBak(_ id: String) -> String { Self.c("K_PRE").s + id + ".bak" }

  static func pack(_ st: JV) -> String { let d = st.stringify(); return "F2|\(String(CareerLib.hashStr(d), radix: 36))|\(d.utf16.count)|\(d)" }
  static func unpack(_ s: String?) -> JV? {
    guard let s, s.hasPrefix("F2|") else { return nil }
    let u = Array(s.utf16)
    guard let a = u[3...].firstIndex(of: 124), let b = u[(a + 1)...].firstIndex(of: 124) else { return nil }
    let d = String(decoding: u[(b + 1)...], as: UTF16.self), len = String(decoding: u[(a + 1)..<b], as: UTF16.self)
    guard Int(len) == u.count - b - 1, String(CareerLib.hashStr(d), radix: 36) == String(decoding: u[3..<a], as: UTF16.self) else { return nil }
    guard let o = JV.parse(d) else { return nil }
    return validate(o) ? o : nil
  }
  static func isInt(_ v: JV?) -> Bool { guard let d = v?.num else { return false }; return d.isFinite && d.rounded(.towardZero) == d }
  /* the shape a save must have to be played on */
  static func validate(_ o: JV) -> Bool {
    guard o.isObj, o["v"]?.num == c("VERSION").d, isInt(o["seed"]), isInt(o["day"]), o["day"]!.d >= 0, o["id"]?.str != nil else { return false }
    guard let pr = o["profile"], pr.isObj, pr["name"]?.str != nil, let me = o["me"], me.isObj, isInt(me["tier"]), me["tier"]!.d >= 1, me["tier"]!.d <= 12 else { return false }
    guard let money = me["money"]?.num, money.isFinite, money >= 0, let sk = me["sk"], sk.isObj, c("SKILLS").a.allSatisfy({ sk[$0.s]?.num?.isFinite == true }) else { return false }
    guard let pop = o["pop"], pop.isObj, isInt(pop["n"]), pop["m"]?.isObj == true, o["ser"]?.isArr == true, o["cal"]?.isArr == true, o["es"]?.isObj == true else { return false }
    guard let aw = o["aw"]?.arr, aw.allSatisfy({ $0.arr?.count == 6 }), let st = o["st"], st.isObj, st["all"]?.isObj == true, o["h2h"]?.isObj == true else { return false }
    for k in ["obj", "off", "spons", "sph", "led", "arch", "hof", "news", "rh"] where o[k]?.isArr != true { return false }
    return ["ch", "rb", "inv", "tot", "ss", "best"].allSatisfy { o[$0]?.isObj == true }
  }
  func writeSlot(_ st: JV) -> (ok: Bool, why: String?, bytes: Int) {
    let s = Self.pack(st), id = st["id"]!.s
    if !sset(kTmp(id), s) || sget(kTmp(id)) != s { sdel(kTmp(id)); return (false, "write", 0) }
    let old = sget(kMain(id))
    if let old, Self.unpack(old) != nil { sset(kBak(id), old) }
    if !sset(kMain(id), s) || sget(kMain(id)) != s || Self.unpack(sget(kMain(id))) == nil {
      if let bak = sget(kBak(id)), Self.unpack(bak) != nil { sset(kMain(id), bak) }
      return (false, "verify", 0)
    }
    sdel(kTmp(id))
    return (true, nil, s.utf16.count)
  }
  func slotRow(_ st: JV, _ bytes: Int, _ seq: Int) -> JV {
    let me = st["me"]!, pr = st["profile"]!, day = st["day"]!.i
    return ["id": st["id"]!, "name": pr["name"]!, "nick": pr["nick"] ?? .null, "season": .n(seasonOf(day)), "week": .n(weekOf(day)), "tier": me["tier"]!,
            "tierName": Self.c("TIERS")[me["tier"]!.i]!["name"]!, "retired": .bool(me["ret"]!.truthy), "hof": .bool(me["hof"]!.truthy), "seq": .n(seq), "bytes": .n(bytes)]
  }
  @discardableResult public func save() -> (ok: Bool, why: String?) {
    if S == .null { return (false, "none") }
    let w = writeSlot(S)
    if !w.ok { return (false, w.why) }
    var idx = readIndex()
    let id = S["id"]!.s, slots = idx["slots"]!.a, i = slots.firstIndex { $0["id"]!.s == id }
    let seq = (i.map { slots[$0]["seq"]!.i } ?? 0) + 1, row = slotRow(S, w.bytes, seq)
    var ns = slots
    if let i { ns[i] = row } else { ns.append(row) }
    idx["slots"] = .arr(ns)
    idx["active"] = .str(id)
    writeIndex(idx)
    return (true, nil)
  }
  @discardableResult func autosave() -> Bool { S != .null && autosaveOn ? save().ok : false }
  /* a career from its slot: the main save, else the temp copy, else the backup (put back as the main) */
  @discardableResult public func load(_ id: String) -> (ok: Bool, why: String?, recovered: String?) {
    for (from, k) in [("main", kMain(id)), ("tmp", kTmp(id)), ("bak", kBak(id))] {
      guard let o = Self.unpack(sget(k)) else { continue }
      S = o; resetCaches(); upgrade()
      if from != "main" { sset(kMain(id), sget(k)!); news("Save restored from the \(from == "bak" ? "backup" : "temporary copy").") }
      var idx = readIndex()
      idx["active"] = .str(id)
      writeIndex(idx)
      return (true, nil, from == "main" ? nil : from)
    }
    return (false, sget(kMain(id)) == nil ? "missing" : "corrupt", nil)
  }
  public func listSlots() -> [JV] {
    let idx = readIndex()
    return idx["slots"]!.a.map { x in
      let id = x["id"]!.s, ok = Self.unpack(sget(kMain(id))) != nil
      var o = x
      o["status"] = .str(ok ? "ok" : Self.unpack(sget(kBak(id))) != nil || Self.unpack(sget(kTmp(id))) != nil ? "recoverable" : "corrupt")
      o["active"] = .bool(id == idx["active"]?.str)
      return o
    }
  }
  @discardableResult public func deleteSlot(_ id: String) -> Bool {
    var idx = readIndex()
    var slots = idx["slots"]!.a
    guard let i = slots.firstIndex(where: { $0["id"]!.s == id }) else { return false }
    for k in [kMain(id), kTmp(id), kBak(id)] { sdel(k) }
    slots.remove(at: i)
    idx["slots"] = .arr(slots)
    if idx["active"]?.str == id { idx["active"] = .null }
    writeIndex(idx)
    if S != .null && S["id"]?.str == id { S = .null }
    return true
  }
}
