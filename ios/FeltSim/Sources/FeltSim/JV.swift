/* A JavaScript value, for the career engine's state (its save, S): the page builds and reads one nested object freely,
   so the port keeps it as the page does. Objects keep JS's own key order (integer-like keys first, ascending, then the
   rest as inserted); numbers are doubles; stringify is JSON.stringify exactly (Number#toString's shortest digits and
   layout, its string escapes), so a save written here reads the same on the page and Career.digest() compares bit for bit. */
import Foundation

public enum JV: Equatable, Sendable {
  case null, bool(Bool), num(Double), str(String), arr([JV]), obj(JObj)
}

/* a JS object: its entries and their insertion order */
public struct JObj: Equatable, Sendable {
  var dict: [String: JV] = [:]
  var order: [String] = []
  public init() {}
  /* an array index as JS reads one: "0" or no leading zero, under 2^32 - 1 */
  static func index(_ k: String) -> UInt32? {
    guard !k.isEmpty, k.count <= 10, k.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), k == "0" || !k.hasPrefix("0"), let v = UInt64(k), v < 4294967295 else { return nil }
    return UInt32(v)
  }
  /* Object.keys: integer-like keys ascending, then the others in insertion order */
  public var keys: [String] {
    let ints = order.compactMap { k in JObj.index(k).map { (k, $0) } }.sorted { $0.1 < $1.1 }.map { $0.0 }
    return ints + order.filter { JObj.index($0) == nil }
  }
  public subscript(_ k: String) -> JV? {
    get { dict[k] }
    set {
      if let v = newValue { if dict[k] == nil { order.append(k) }; dict[k] = v }
      else if dict.removeValue(forKey: k) != nil { order.removeAll { $0 == k } }
    }
  }
  public static func == (a: JObj, b: JObj) -> Bool { a.keys == b.keys && a.dict == b.dict }
}

extension JV {
  /* JSON.parse: objects take their keys in document order (a repeated key keeps its first place and its last value) */
  public static func parse(_ s: String) -> JV? {
    var p = Parser(Array(s.utf8)), v: JV? = nil
    p.ws(); v = p.value(); p.ws()
    return p.i == p.b.count ? v : nil
  }
  struct Parser {
    let b: [UInt8]; var i = 0
    init(_ b: [UInt8]) { self.b = b }
    mutating func ws() { while i < b.count, b[i] == 32 || b[i] == 10 || b[i] == 13 || b[i] == 9 { i += 1 } }
    mutating func lit(_ w: String) -> Bool { let u = Array(w.utf8); if i + u.count <= b.count && Array(b[i..<i + u.count]) == u { i += u.count; return true }; return false }
    mutating func value() -> JV? {
      guard i < b.count else { return nil }
      switch b[i] {
      case 123:
        i += 1; var o = JObj(); ws()
        if i < b.count && b[i] == 125 { i += 1; return .obj(o) }
        while true {
          ws(); guard case .str(let k)? = string() else { return nil }
          ws(); guard i < b.count, b[i] == 58 else { return nil }; i += 1; ws()
          guard let v = value() else { return nil }
          o[k] = v; ws()
          if i < b.count && b[i] == 44 { i += 1; continue }
          if i < b.count && b[i] == 125 { i += 1; return .obj(o) }
          return nil
        }
      case 91:
        i += 1; var a: [JV] = []; ws()
        if i < b.count && b[i] == 93 { i += 1; return .arr(a) }
        while true {
          ws(); guard let v = value() else { return nil }
          a.append(v); ws()
          if i < b.count && b[i] == 44 { i += 1; continue }
          if i < b.count && b[i] == 93 { i += 1; return .arr(a) }
          return nil
        }
      case 34: return string()
      case 116: return lit("true") ? .bool(true) : nil
      case 102: return lit("false") ? .bool(false) : nil
      case 110: return lit("null") ? .null : nil
      default:
        let s = i
        while i < b.count, let c = Optional(b[i]), (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 || c == 101 || c == 69 { i += 1 }
        return Double(String(decoding: b[s..<i], as: UTF8.self)).map { .num($0) }
      }
    }
    mutating func string() -> JV? {
      guard i < b.count, b[i] == 34 else { return nil }
      i += 1
      var u16: [UInt16] = []
      while i < b.count {
        let c = b[i]
        if c == 34 { i += 1; return .str(String(decoding: u16, as: UTF16.self)) }
        if c == 92 {
          i += 1; guard i < b.count else { return nil }
          let e = b[i]; i += 1
          switch e {
          case 34: u16.append(34); case 92: u16.append(92); case 47: u16.append(47)
          case 98: u16.append(8); case 102: u16.append(12); case 110: u16.append(10); case 114: u16.append(13); case 116: u16.append(9)
          case 117:
            guard i + 4 <= b.count, let v = UInt16(String(decoding: b[i..<i + 4], as: UTF8.self), radix: 16) else { return nil }
            u16.append(v); i += 4
          default: return nil
          }
          continue
        }
        /* a run of UTF-8 to its UTF-16 units */
        let s = i
        while i < b.count, b[i] != 34, b[i] != 92 { i += 1 }
        u16 += String(decoding: b[s..<i], as: UTF8.self).utf16
      }
      return nil
    }
  }

  /* JSON.stringify */
  public func stringify() -> String { var o = ""; write(&o); return o }
  func write(_ o: inout String) {
    switch self {
    case .null: o += "null"
    case .bool(let b): o += b ? "true" : "false"
    case .num(let d): o += d.isFinite ? JV.numberString(d) : "null"
    case .str(let s): JV.quote(s, &o)
    case .arr(let a):
      o += "["
      for (i, v) in a.enumerated() { if i > 0 { o += "," }; v.write(&o) }
      o += "]"
    case .obj(let ob):
      o += "{"
      var first = true
      for k in ob.keys { if !first { o += "," }; first = false; JV.quote(k, &o); o += ":"; ob.dict[k]!.write(&o) }
      o += "}"
    }
  }
  static func quote(_ s: String, _ o: inout String) {
    o += "\""
    let u = Array(s.utf16)
    var i = 0
    while i < u.count {
      let c = u[i]
      switch c {
      case 34: o += "\\\""
      case 92: o += "\\\\"
      case 8: o += "\\b"
      case 12: o += "\\f"
      case 10: o += "\\n"
      case 13: o += "\\r"
      case 9: o += "\\t"
      default:
        if c < 0x20 { o += String(format: "\\u%04x", c) }
        else if c >= 0xD800 && c <= 0xDBFF && i + 1 < u.count && u[i + 1] >= 0xDC00 && u[i + 1] <= 0xDFFF { o += String(decoding: [c, u[i + 1]], as: UTF16.self); i += 1 }
        else if c >= 0xD800 && c <= 0xDFFF { o += String(format: "\\u%04x", c) }
        else { o += String(decoding: [c], as: UTF16.self) }
      }
      i += 1
    }
    o += "\""
  }
  /* Number#toString(10): the shortest round-trip digits (Swift's own, the same digits), laid out by ECMA-262's rules */
  public static func numberString(_ d: Double) -> String {
    if d == 0 { return "0" }
    if d < 0 { return "-" + numberString(-d) }
    /* Swift's description: "123.45", "1e-07", "1.2345e+20" or "5e-324": digits and the exponent n (value = 0.digits x 10^n) */
    var s = "\(d)", exp = 0
    if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) { exp = Int(s[s.index(after: e)...])!; s = String(s[..<e]) }
    var digits: String, point: Int
    if let dot = s.firstIndex(of: ".") { digits = String(s[..<dot]) + String(s[s.index(after: dot)...]); point = s.distance(from: s.startIndex, to: dot) }
    else { digits = s; point = s.count }
    var lead = 0
    for ch in digits { if ch == "0" { lead += 1 } else { break } }
    digits = String(digits.dropFirst(lead)); point -= lead
    while digits.hasSuffix("0") { digits.removeLast() }
    if digits.isEmpty { return "0" }
    let k = digits.count, n = point + exp
    if k <= n && n <= 21 { return digits + String(repeating: "0", count: n - k) }
    if 0 < n && n <= 21 { return String(digits.prefix(n)) + "." + String(digits.dropFirst(n)) }
    if -6 < n && n <= 0 { return "0." + String(repeating: "0", count: -n) + digits }
    let e = n - 1, es = e < 0 ? "-\(-e)" : "+\(e)"
    return k == 1 ? digits + "e" + es : String(digits.prefix(1)) + "." + String(digits.dropFirst()) + "e" + es
  }
}
