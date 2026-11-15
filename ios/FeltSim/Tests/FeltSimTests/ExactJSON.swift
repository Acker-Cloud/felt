/* A JSON reader whose numbers are exact: each one is parsed by Double(String), which rounds correctly,
   as JS's JSON.parse does. Foundation's JSONSerialization can land a few ulps off on a long double
   (a ball's y, 2 ulps: found by RuleShotTests), which is no use for bit-for-bit goldens. Numbers come
   back as NSNumber, booleans as NSNumber(bool), null as NSNull, like JSONSerialization. */
import Foundation

enum ExactJSON {
  static func parse(_ data: Data) -> Any {
    let bytes = [UInt8](data)
    var i = 0
    func ws() { while i < bytes.count, [0x20, 0x0a, 0x0d, 0x09].contains(bytes[i]) { i += 1 } }
    func value() -> Any {
      ws()
      switch bytes[i] {
      case UInt8(ascii: "{"):
        i += 1; var o: [String: Any] = [:]; ws()
        if bytes[i] == UInt8(ascii: "}") { i += 1; return o }
        while true {
          ws(); let k = string(); ws(); i += 1   /* : */
          o[k] = value(); ws()
          if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
          i += 1; return o
        }
      case UInt8(ascii: "["):
        i += 1; var a: [Any] = []; ws()
        if bytes[i] == UInt8(ascii: "]") { i += 1; return a }
        while true {
          a.append(value()); ws()
          if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
          i += 1; return a
        }
      case UInt8(ascii: "\""): return string()
      case UInt8(ascii: "t"): i += 4; return NSNumber(value: true)
      case UInt8(ascii: "f"): i += 5; return NSNumber(value: false)
      case UInt8(ascii: "n"): i += 4; return NSNull()
      default:
        let s = i
        while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
        return NSNumber(value: Double(String(decoding: bytes[s..<i], as: UTF8.self))!)
      }
    }
    func string() -> String {
      i += 1; var out = [UInt8]()
      while bytes[i] != UInt8(ascii: "\"") {
        if bytes[i] == UInt8(ascii: "\\") {
          i += 1
          switch bytes[i] {
          case UInt8(ascii: "n"): out.append(0x0a)
          case UInt8(ascii: "t"): out.append(0x09)
          case UInt8(ascii: "u"):
            let h = UInt32(String(decoding: bytes[(i + 1)...(i + 4)], as: UTF8.self), radix: 16)!
            out += Array(String(Character(Unicode.Scalar(h)!)).utf8); i += 4
          default: out.append(bytes[i])
          }
        } else { out.append(bytes[i]) }
        i += 1
      }
      i += 1
      return String(decoding: out, as: UTF8.self)
    }
    return value()
  }
}
