/* index.html's sim 1a-1d in Swift: constants, the table, collisions, the table in motion. A line
   for line port: the same names, the same operation order, the same doubles (JSMath for every
   transcendental), so a shot run here is the page's shot bit for bit (GoldenTests, against
   tools/ios-golden.cjs). Read the JS comments for the physics; these note only what the port does.
   The page's module globals (TL, CUSH, POCKETS, BALL_R, ...) are a Sim's properties: one Sim is one
   table, set with setTable/setPockets. Ported tables: pool 7 and 9 ft (both pocket styles),
   snooker (compact, full), Chinese 8-ball (heyball) and carom. Bumper pool (its posts and cups) is
   bumper pool's table (1g) is ported; its rules and CPU live with the rules. */
import Foundation

private typealias M = JSMath

public let SIM_DT = 1.0 / 1200
public struct Phys: Sendable { public let R, roll, cue, mu: Double; public let e: [Double]; public let sp: Double }
public let POOL_PHYS = Phys(R: 0.028575, roll: 0.01, cue: 6.0 / 19, mu: 0.2, e: [0.88, 0.03, 0.7], sp: 10.0 * 2 / 5 / 9)
public let SNOOKER_PHYS = Phys(R: 0.02625, roll: 0.01, cue: 6.0 / 19, mu: 0.2, e: [0.88, 0.03, 0.7], sp: 10.0 * 2 / 5 / 9)
public let CAROM_PHYS = Phys(R: 0.03075, roll: 0.0075, cue: 0.4, mu: 0.24, e: [0.92, 0.025, 0.75], sp: 10.0 * 2 / 5 / 9)
public func physOf(_ table: String) -> Phys { table == "carom" ? CAROM_PHYS : table == "snooker" ? SNOOKER_PHYS : POOL_PHYS }
public let TABLE_SIZES: [String: [Double]] = ["7": [1.981, 0.991], "9": [2.54, 1.27]]
public let MIN_V = 0.2, MAX_V = 8.5, POWER_EXP = 1.7, V_CAP = 9.0, G = 9.8, MU_SLIDE = 0.2
public let STOP_V = 0.01, MAX_SIM_T = 60.0
public let E_SLATE = 0.5, V_SLATE = 1.0
public let BALL_E = 0.94
public let THROW_A = 0.00995, THROW_B = 0.108, THROW_C = 1.088
public let CUSH_MU_ALONG = 0.1
public let NOSE_S = 0.27, NOSE_C = (1 - NOSE_S * NOSE_S).squareRoot()
public let TIP_MAX = 0.6, TIP_LOSS = 0.6, SQUIRT = 0.026
public struct PocketStyle: Sendable {
  public let corner, side, cornerFace, sideFace, cornerR, sideR, shelf, sideBack: Double
  public let round: Double?, sideRound: Double?
}
public let POCKET_STYLES: [String: PocketStyle] = [
  "regulation": PocketStyle(corner: 0.1207, side: 0.1334, cornerFace: 142, sideFace: 104, cornerR: 0.056, sideR: 0.058, shelf: 0.032, sideBack: 0.034, round: nil, sideRound: nil),
  "generous": PocketStyle(corner: 0.1334, side: 0.1461, cornerFace: 139, sideFace: 100, cornerR: 0.062, sideR: 0.064, shelf: 0.030, sideBack: 0.029, round: nil, sideRound: nil),
  "snooker": PocketStyle(corner: 0.090, side: 0.104, cornerFace: 137, sideFace: 101, cornerR: 0.05, sideR: 0.05, shelf: 0.045, sideBack: 0.04, round: 0.03, sideRound: 0.022),
  "heyball": PocketStyle(corner: 0.090, side: 0.104, cornerFace: 137, sideFace: 98, cornerR: 0.056, sideR: 0.056, shelf: 0.047, sideBack: 0.043, round: 0.03, sideRound: 0.022),
]
public let CUSH_W = 0.05, POCKET_LIP = 0.02, SIDE_SKIM = 0.008, ESCAPE_R = 0.16, RACK_GAP = 0.0002
public let CUP_V = 1.0
/* bumper pool (1g): the rectangle's bed, the posts' radius, the cups; the octagon (40 in across the flats) */
public let BUMPER_SIZE = [1.219, 0.838], BUMPER_R = 0.0254
public let CUP_IN = 0.15, CUP_R = 0.041, CUP_LIP = 0.006
public let OCTA_F = 1.016, OCTA_CUP_IN = 0.12, OCTA_POSTS = [0.17, 0.16]
public let CAROM_SIZE = [2.84, 1.42], HEYBALL_SIZE = [2.54, 1.26]
public let SNOOKER_SIZES: [String: [Double]] = ["full": [3.569, 1.778], "compact": [3.569 * 5 / 6, 1.778 * 5 / 6]]
public let SNK_BAULK = 0.737, SNK_D = 0.292, SNK_BLACK_IN = 0.324, SNK_APEX = 0.001
public let ELEV_MAX = Double.pi / 3
public let JAW_FROM = 6
public let FROZEN_ON = 2e-4, FROZEN_OFF = 1e-3

@inline(__always) public func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { M.max(lo, M.min(hi, v)) }

/* the spin argument, already resolved (spinOf): side x, follow y, elevation e (0 when level) */
public struct Spin: Equatable, Sendable {
  public var x: Double, y: Double, e: Double
  public init(x: Double = 0, y: Double = 0, e: Double = 0) { self.x = x; self.y = y; self.e = e }
}
/* spinOf: a number is follow or draw; {x, y, e} is clipped to the unit disc, e to [0, ELEV_MAX] */
public func spinOf(follow s: Double) -> Spin { Spin(x: 0, y: s.isFinite ? clamp(s, -1, 1) : 0) }
public func spinOf(x x0: Double?, y y0: Double?, e e0: Double?) -> Spin {
  var x = x0.flatMap { $0.isFinite ? $0 : nil } ?? 0, y = y0.flatMap { $0.isFinite ? $0 : nil } ?? 0
  let m = M.hypot(x, y)
  if m > 1 { x /= m; y /= m }
  let e = e0.flatMap { $0.isFinite ? clamp($0, 0, ELEV_MAX) : nil } ?? 0
  return Spin(x: x, y: y, e: e > 0 ? e : 0)
}

/* A ball: a reference, as the page's ball objects are (hitBalls moves two at once). z and vz are
   nil on the bed, the page's undefined. */
public final class Ball {
  public var n: Int, x: Double, y: Double, vx = 0.0, vy = 0.0, on = true, wx = 0.0, wy = 0.0, wz = 0.0
  public var z: Double? = nil, vz: Double? = nil
  public init(_ n: Int, _ x: Double, _ y: Double) { self.n = n; self.x = x; self.y = y }
  public func copy() -> Ball {
    let b = Ball(n, x, y); b.vx = vx; b.vy = vy; b.on = on; b.wx = wx; b.wy = wy; b.wz = wz; b.z = z; b.vz = vz; return b
  }
  @inline(__always) var still: Bool { vx == 0 && vy == 0 && wx == 0 && wy == 0 && wz == 0 && vz == nil }
}

/* tab.hits: [kind, v, extra] (extra: the pocket index of a 'pocket') */
/* a hit [kind, v, extra]: extra the pocket's index, or (tag) a string: 'post' on a bumper post's 'rail' */
public struct Hit: Equatable, Sendable { public let kind: String; public let v: Double; public let extra: Int?; public var tag: String? = nil }

public final class Tab {
  public var balls: [Ball], cue: Int, t = 0.0, steps = 0, first: Int? = nil, railAfter = false, crossed = false
  public var potted: [Int] = [], pocketOf: [Int: Int] = [:], hits: [Hit] = [], end: String? = nil, escaped = 0
  public var rails: [Int: Int] = [:], kick: Int? = nil, contacts: [[Int]] = [], met = Set<Int>(), railAt: [Int: [Double]] = [:]
  public var seq: [Int] = [], railSeq: [[Int]] = [], frozen: [Int: Int]?, over: [Int]? = nil
  init(balls: [Ball], cue: Int, frozen: [Int: Int]?) { self.balls = balls; self.cue = cue; self.frozen = frozen }
}

/* resultOf: the rules' view of a finished (or running) table */
public struct ShotResult {
  public let balls: [Ball], cue: Int, first: Int?, railAfter: Bool, crossed: Bool, potted: [Int], pocketOf: [Int: Int]
  public let end: String?, t: Double, steps: Int, rails: [Int: Int], kick: Int?, contacts: [[Int]], railAt: [Int: [Double]]
  public let seq: [Int], railSeq: [[Int]], over: [Int]?
}

public struct JawPoint { public var p: [Double]; public var e: [Double] }

public final class Sim {
  public private(set) var TABLE = "7", POOL_TABLE = "7", POCKETS_STYLE = "regulation", SNOOKER_SIZE = "compact"
  public private(set) var BALL_R = POOL_PHYS.R, MU_ROLL = POOL_PHYS.roll, CUE_RATIO = POOL_PHYS.cue, CUSH_MU = POOL_PHYS.mu
  public private(set) var RAIL_E = POOL_PHYS.e, MU_SP = POOL_PHYS.sp
  public private(set) var TL = 0.0, TW = 0.0, HEAD_X = 0.0, FOOT = [0.0, 0.0]
  public private(set) var CORNER_W = 0.0, SIDE_W = 0.0, CORNER_FACE = 0.0, SIDE_FACE = 0.0, CORNER_SHELF = 0.0, SIDE_BACK = 0.0
  public private(set) var SKIMS: [Double] = [], HOLE_IN = 0.0
  public private(set) var MOUTHS: [[JawPoint]] = [], RUBBERS: [[JawPoint]] = [], CUSH: [[Double]] = []
  public private(set) var CUSHION_POLYS: [[[Double]]] = [], POCKET_R: [Double] = [], POCKET_AIM: [[Double]] = [], POCKETS: [[Double]] = []
  public private(set) var CPU_MOUTH_N: [[Double]] = []
  public private(set) var JAW_ARCS: [[Double]] = [], JAW_RAD = [0.0, 0.0]
  public private(set) var D_R = 0.0, SPOTS: [Int: [Double]] = [:]
  /* bumper pool (1g): the posts [x, y] (radius BUMPER_R), empty on every other table; the bumper table's shape
     ('octagon' | 'rect', kept for later bumper tables) and, on the octagon, the noses as inward lines [nx, ny, c] */
  public private(set) var BUMPERS: [[Double]] = [], BUMPER_SHAPE = "octagon", BED_LINES: [[Double]]? = nil

  public init() { setTable("7") }

  @inline(__always) public func spinA() -> Double { 2.5 * MU_SP * G }
  @inline(__always) public func cushionTop() -> Double { BALL_R * (1 + NOSE_S) }

  // MARK: 1b. table

  func jaw(_ px: Double, _ py: Double, _ ax: Double, _ ay: Double, _ ox: Double, _ oy: Double, _ face: Double) -> JawPoint {
    let dx = -ax * M.cos(face) + ox * M.sin(face), dy = -ay * M.cos(face) + oy * M.sin(face)
    let t = CUSH_W / M.sin(face)
    return JawPoint(p: [px, py], e: [px + dx * t, py + dy * t])
  }
  func mouths() -> [[JawPoint]] {
    let SQRT2 = 2.0.squareRoot()
    let c = CORNER_W / SQRT2, s = SIDE_W / 2, h = TL / 2
    var out: [[JawPoint]] = []
    for (cx, cy, side) in [(0.0, 0.0, false), (h, 0.0, true), (TL, 0.0, false), (0.0, TW, false), (h, TW, true), (TL, TW, false)] {
      let sy: Double = cy == 0 ? 1 : -1
      if side { out.append([jaw(h - s, cy, 1, 0, 0, -sy, SIDE_FACE), jaw(h + s, cy, -1, 0, 0, -sy, SIDE_FACE)]); continue }
      let sx: Double = cx == 0 ? 1 : -1
      out.append([jaw(cx + sx * c, cy, -sx, 0, 0, -sy, CORNER_FACE), jaw(cx, cy + sy * c, 0, -sy, -sx, 0, CORNER_FACE)])
    }
    return out
  }
  func rubbers(_ m: [[JawPoint]]) -> [[JawPoint]] {
    [[m[0][0], m[1][0]], [m[1][1], m[2][0]], [m[3][0], m[4][0]], [m[4][1], m[5][0]], [m[0][1], m[3][1]], [m[2][1], m[5][1]]]
  }
  func cushions() -> [[Double]] {
    var out = RUBBERS.map { [$0[0].p[0], $0[0].p[1], $0[1].p[0], $0[1].p[1]] }
    for r in RUBBERS {
      let a = r[0], b = r[1]
      out.append([a.p[0], a.p[1], a.e[0], a.e[1]]); out.append([b.p[0], b.p[1], b.e[0], b.e[1]])
    }
    return out
  }
  func pockets() -> [[Double]] {
    let SQRT2 = 2.0.squareRoot()
    return POCKET_AIM.enumerated().map { k, m in
      let ox: Double = m[0] < TL / 2 ? -1 : 1, oy: Double = m[1] < TW / 2 ? -1 : 1
      if k == 1 || k == 4 { return [m[0], m[1] + oy * SIDE_BACK] }
      let d = (CORNER_SHELF + POCKET_R[k]) / SQRT2
      return [m[0] + ox * d, m[1] + oy * d]
    }
  }
  func buildTable() {
    BED_LINES = nil; JAW_ARCS = []; JAW_RAD = [0, 0]; SPOTS = [:]; D_R = 0
    let ph = physOf(TABLE)
    BALL_R = ph.R; MU_ROLL = ph.roll; CUE_RATIO = ph.cue; CUSH_MU = ph.mu; RAIL_E = ph.e; MU_SP = ph.sp
    if TABLE == "carom" { buildCarom(); return }
    if TABLE == "bumper" { buildBumper(); return }
    BUMPERS = []
    let snk = TABLE == "snooker", hey = TABLE == "heyball"
    let st = POCKET_STYLES[snk ? "snooker" : hey ? "heyball" : POCKETS_STYLE]!
    let size = snk ? SNOOKER_SIZES[SNOOKER_SIZE]! : hey ? HEYBALL_SIZE : TABLE_SIZES[TABLE]!
    TL = size[0]; TW = size[1]
    HEAD_X = TL / 4; FOOT = [TL * 3 / 4, TW / 2]
    CORNER_W = st.corner; SIDE_W = st.side; CORNER_SHELF = st.shelf; SIDE_BACK = st.sideBack
    CORNER_FACE = st.cornerFace * Double.pi / 180; SIDE_FACE = st.sideFace * Double.pi / 180
    MOUTHS = mouths()
    RUBBERS = rubbers(MOUTHS)
    CUSH = cushions()
    CUSHION_POLYS = RUBBERS.map { [$0[0].e, $0[0].p, $0[1].p, $0[1].e] }
    POCKET_R = [st.cornerR, st.sideR, st.cornerR, st.cornerR, st.sideR, st.cornerR]
    POCKET_AIM = MOUTHS.map { [($0[0].p[0] + $0[1].p[0]) / 2, ($0[0].p[1] + $0[1].p[1]) / 2] }
    POCKETS = pockets()
    SKIMS = [0, SIDE_SKIM, 0, 0, SIDE_SKIM, 0]
    HOLE_IN = M.max(0, st.sideR - st.sideBack)
    let SQRT1_2 = 0.5.squareRoot()
    CPU_MOUTH_N = POCKET_AIM.enumerated().map { k, p in
      k == 1 || k == 4 ? [0, p[1] < TW / 2 ? 1 : -1]
        : [(p[0] < TL / 2 ? 1 : -1) * SQRT1_2, (p[1] < TW / 2 ? 1 : -1) * SQRT1_2]
    }
    if snk { buildSnooker(st) }
    if hey { roundJaws(st) }
  }
  /* size "7" | "9" | "bumper" | "snooker" | "carom" | "heyball"; shape: the snooker size ("full" | "compact"), else
     the bumper table's ("rect", anything else "octagon"), kept for later tables */
  @discardableResult public func setTable(_ size: String, _ shape: String? = nil) -> String {
    if size == "snooker" {
      if let s = shape { SNOOKER_SIZE = s == "full" ? "full" : "compact" }
      TABLE = "snooker"
    } else {
      if let s = shape { BUMPER_SHAPE = s == "rect" ? "rect" : "octagon" }
      if size == "bumper" || size == "carom" || size == "heyball" { TABLE = size }
      else { POOL_TABLE = size == "9" ? "9" : "7"; TABLE = POOL_TABLE }
    }
    buildTable()
    return TABLE
  }
  @discardableResult public func setPockets(_ style: String) -> String {
    POCKETS_STYLE = style == "generous" ? "generous" : "regulation"
    buildTable()
    return POCKETS_STYLE
  }
  // MARK: 1g. bumper pool's table

  /* the rectangle (BUMPER_SHAPE 'rect'): four noses with no gaps, two cups, twelve posts */
  func buildBumper() {
    if BUMPER_SHAPE == "octagon" { buildOcta(); return }
    TL = BUMPER_SIZE[0]; TW = BUMPER_SIZE[1]
    HEAD_X = TL / 2; FOOT = [TL / 2, TW / 2]
    let c = CUSH_W, cx = TL / 2, cy = TW / 2, a = 0.19, b = 0.15
    MOUTHS = []; RUBBERS = []
    CUSH = [[0, 0, TL, 0], [TL, 0, TL, TW], [TL, TW, 0, TW], [0, TW, 0, 0]]
    CUSHION_POLYS = [[[-c, -c], [0, 0], [TL, 0], [TL + c, -c]], [[TL + c, -c], [TL, 0], [TL, TW], [TL + c, TW + c]],
      [[TL + c, TW + c], [TL, TW], [0, TW], [-c, TW + c]], [[-c, TW + c], [0, TW], [0, 0], [-c, -c]]]
    POCKETS = [[CUP_IN, cy], [TL - CUP_IN, cy]]
    POCKET_R = [CUP_R, CUP_R]; SKIMS = [0, 0]; HOLE_IN = 0
    POCKET_AIM = POCKETS.map { $0 }
    CPU_MOUTH_N = [[1, 0], [-1, 0]]
    BUMPERS = [[cx - a, cy], [cx + a, cy], [cx, cy - b], [cx, cy + b],
      [cx - a / 2, cy - b / 2], [cx + a / 2, cy - b / 2], [cx - a / 2, cy + b / 2], [cx + a / 2, cy + b / 2]]
    for (px, sg) in [(CUP_IN, 1.0), (TL - CUP_IN, -1.0)] { BUMPERS.append([px + sg * 0.07, cy - 0.05]); BUMPERS.append([px + sg * 0.07, cy + 0.05]) }
  }
  /* the octagon d outside the nose line, clockwise from the top flat's left end, in the OCTA_F square */
  public func octagon(_ d: Double) -> [[Double]] {
    let c = OCTA_F / 2, h = c + d, t = h * (2.0.squareRoot() - 1)
    return [[c - t, c - h], [c + t, c - h], [c + h, c - t], [c + h, c + t], [c + t, c + h], [c - t, c + h], [c - h, c + t], [c - h, c - t]]
  }
  /* the octagonal table (the default). As the page's, SKIMS and HOLE_IN are left as the last table set them */
  func buildOcta() {
    TL = OCTA_F; TW = OCTA_F
    HEAD_X = TL / 2; FOOT = [TL / 2, TW / 2]
    let N = octagon(0), E = octagon(CUSH_W), cx = TL / 2, cy = TW / 2, a = OCTA_POSTS[0], b = OCTA_POSTS[1]
    MOUTHS = []; RUBBERS = []
    CUSH = N.indices.map { i in [N[i][0], N[i][1], N[(i + 1) % 8][0], N[(i + 1) % 8][1]] }
    CUSHION_POLYS = N.indices.map { i in [E[i], N[i], N[(i + 1) % 8], E[(i + 1) % 8]] }
    BED_LINES = CUSH.map { q in
      let ax = q[0], ay = q[1], bx = q[2], by = q[3], l = M.hypot(bx - ax, by - ay), nx = (ay - by) / l, ny = (bx - ax) / l
      return [nx, ny, nx * ax + ny * ay]
    }
    POCKETS = [[OCTA_CUP_IN, cy], [TL - OCTA_CUP_IN, cy]]
    POCKET_R = [CUP_R, CUP_R]
    POCKET_AIM = POCKETS.map { $0 }
    CPU_MOUTH_N = [[1, 0], [-1, 0]]
    BUMPERS = [[cx - a, cy], [cx + a, cy], [cx, cy - b], [cx, cy + b],
      [cx - a / 2, cy - b / 2], [cx + a / 2, cy - b / 2], [cx - a / 2, cy + b / 2], [cx + a / 2, cy + b / 2]]
    for (px, sg) in [(OCTA_CUP_IN, 1.0), (TL - OCTA_CUP_IN, -1.0)] { BUMPERS.append([px + sg * 0.07, cy - 0.05]); BUMPERS.append([px + sg * 0.07, cy + 0.05]) }
  }
  /* on the octagon: (x, y) is at least d inside every cushion's nose line */
  public func bedIn(_ x: Double, _ y: Double, _ d: Double) -> Bool {
    for l in BED_LINES! where !(l[0] * x + l[1] * y - l[2] >= d) { return false }
    return true
  }
  /* the cup T seen in each cushion's mirror [mx, my, k]; the rectangle's four in its own order (k absent) */
  public func bumperBanks(_ T: [Double]) -> [[Double]] {
    let R = BALL_R
    guard let BL = BED_LINES else { return [[2 * R - T[0], T[1]], [2 * (TL - R) - T[0], T[1]], [T[0], 2 * R - T[1]], [T[0], 2 * (TW - R) - T[1]]] }
    return BL.enumerated().map { k, l in let d = 2 * (l[0] * T[0] + l[1] * T[1] - l[2] - R); return [T[0] - d * l[0], T[1] - d * l[1], Double(k)] }
  }
  /* one step of a moving ball against the posts and the cups; true when it dropped */
  func bumperStep(_ tab: Tab, _ b: Ball) -> Bool {
    let D = BALL_R + BUMPER_R
    for p in BUMPERS {
      var nx = b.x - p[0], ny = b.y - p[1]
      let d2 = nx * nx + ny * ny
      if d2 >= D * D || d2 < 1e-24 { continue }
      let d = d2.squareRoot()
      nx /= d; ny /= d
      b.x = p[0] + nx * D; b.y = p[1] + ny * D
      let v = rail(b, nx, ny)
      if v != 0 { if tab.first != nil { tab.railAfter = true }; tab.hits.append(Hit(kind: "rail", v: v, extra: nil, tag: "post")) }
    }
    let v = M.hypot(b.vx, b.vy)
    if (b.z ?? 0) > 0 { return false }
    for k in 0..<POCKETS.count {
      let p = POCKETS[k], r = POCKET_R[k] - CUP_LIP * M.min(1, v / CUP_V)
      let dx = b.x - p[0], dy = b.y - p[1]
      if dx * dx + dy * dy < r * r { pot(tab, b, k, v); return true }
    }
    return false
  }

  func buildSnooker(_ st: PocketStyle) {
    let s = TL / SNOOKER_SIZES["full"]![0], y = TW / 2
    HEAD_X = SNK_BAULK * s; D_R = SNK_D * s
    SPOTS = [57: [HEAD_X, y + D_R], 58: [HEAD_X, y - D_R], 59: [HEAD_X, y], 60: [TL / 2, y], 61: [0.75 * TL, y], 62: [TL - SNK_BLACK_IN * s, y]]
    FOOT = SPOTS[61]!
    roundJaws(st)
  }
  func unit2(_ a: [Double], _ b: [Double]) -> [Double] {
    let dx = b[0] - a[0], dy = b[1] - a[1], h = M.hypot(dx, dy), d = h == 0 || h.isNaN ? 1 : h
    return [dx / d, dy / d]
  }
  func jawSide(_ p: [Double]) -> Bool { abs(p[0] - TL / 2) < TL / 4 }
  func roundJaws(_ st: PocketStyle) {
    JAW_RAD = [st.round!, st.sideRound!]
    func one(_ j: JawPoint, _ o: [Double]) -> (n: [Double], f: [Double]) {
      let p = j.p, r = JAW_RAD[jawSide(p) ? 1 : 0], u = unit2(p, o), f = unit2(p, j.e)
      let th = M.acos(clamp(u[0] * f[0] + u[1] * f[1], -1, 1)), t = r / M.tan(th / 2), c = r / M.sin(th / 2)
      let bx = u[0] + f[0], by = u[1] + f[1], bl = M.hypot(bx, by)
      JAW_ARCS.append([p[0] + bx / bl * c, p[1] + by / bl * c, r])
      return ([p[0] + u[0] * t, p[1] + u[1] * t], [p[0] + f[0] * t, p[1] + f[1] * t])
    }
    let ends = RUBBERS.map { r in [one(r[0], r[1].p), one(r[1], r[0].p)] }
    CUSH = ends.map { [$0[0].n[0], $0[0].n[1], $0[1].n[0], $0[1].n[1]] }
    for (i, r) in RUBBERS.enumerated() {
      CUSH.append([ends[i][0].f[0], ends[i][0].f[1], r[0].e[0], r[0].e[1]])
      CUSH.append([ends[i][1].f[0], ends[i][1].f[1], r[1].e[0], r[1].e[1]])
    }
  }
  func buildCarom() {
    TL = CAROM_SIZE[0]; TW = CAROM_SIZE[1]
    HEAD_X = TL / 4; FOOT = [TL * 3 / 4, TW / 2]
    let c = CUSH_W
    MOUTHS = []; RUBBERS = []
    CUSH = [[0, 0, TL, 0], [TL, 0, TL, TW], [TL, TW, 0, TW], [0, TW, 0, 0]]
    CUSHION_POLYS = [[[-c, -c], [0, 0], [TL, 0], [TL + c, -c]], [[TL + c, -c], [TL, 0], [TL, TW], [TL + c, TW + c]],
      [[TL + c, TW + c], [TL, TW], [0, TW], [-c, TW + c]], [[-c, TW + c], [0, TW], [0, 0], [-c, -c]]]
    POCKETS = []; POCKET_R = []; POCKET_AIM = []; SKIMS = []; HOLE_IN = 0; CPU_MOUTH_N = []
  }

  public static let RACKS: [String: [[Int]]] = [
    "8": [[1], [9, 2], [10, 8, 3], [11, 4, 12, 5], [6, 13, 7, 14, 15]],
    "heyball": [[1], [9, 2], [10, 8, 3], [11, 4, 12, 5], [6, 13, 7, 14, 15]],
    "9": [[1], [2, 3], [4, 9, 5], [6, 7], [8]],
    "10": [[1], [2, 3], [4, 10, 5], [6, 7, 8, 9]],
    "rotation": [[1], [10, 11], [12, 15, 13], [4, 5, 6, 7], [2, 8, 9, 14, 3]],
  ]
  public func rack(_ kind: String) -> [Ball] {
    let sp = 2 * BALL_R + RACK_GAP, dx = sp * 3.0.squareRoot() / 2
    let rows = Sim.RACKS[kind] ?? Sim.RACKS["8"]!
    var out = [Ball(0, HEAD_X, TW / 2)]
    for (k, row) in rows.enumerated() {
      for (j, n) in row.enumerated() { out.append(Ball(n, FOOT[0] + Double(k) * dx, FOOT[1] + (Double(j) - Double(row.count - 1) / 2) * sp)) }
    }
    return out
  }
  public func snookerRack() -> [Ball] {
    let sp = 2 * BALL_R + RACK_GAP, dx = sp * 3.0.squareRoot() / 2, x0 = SPOTS[61]![0] + 2 * BALL_R + SNK_APEX
    var out = [Ball(0, HEAD_X - 0.06, TW / 2 + D_R * 0.5)]
    var n = 41
    for k in 0..<5 { for j in 0...k { out.append(Ball(n, x0 + Double(k) * dx, TW / 2 + (Double(j) - Double(k) / 2) * sp)); n += 1 } }
    for c in [57, 58, 59, 60, 61, 62] { out.append(Ball(c, SPOTS[c]![0], SPOTS[c]![1])) }
    return out
  }
  public func speedOf(_ power: Double) -> Double { MIN_V + (MAX_V - MIN_V) * M.pow(clamp(power, 0, 1), POWER_EXP) }
  public func powerFor(_ v: Double) -> Double { M.pow(clamp((v - MIN_V) / (MAX_V - MIN_V), 0, 1), 1 / POWER_EXP) }

  // MARK: 1c. collisions

  @inline(__always) func closestOnSeg(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ x: Double, _ y: Double) -> (Double, Double) {
    let ex = bx - ax, ey = by - ay, L2 = ex * ex + ey * ey
    let t = L2 != 0 ? clamp(((x - ax) * ex + (y - ay) * ey) / L2, 0, 1) : 0
    return (ax + ex * t, ay + ey * t)
  }
  public func segGap(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ x: Double, _ y: Double) -> Double {
    let ex = bx - ax, ey = by - ay, L2 = ex * ex + ey * ey
    let t = L2 != 0 ? clamp(((x - ax) * ex + (y - ay) * ey) / L2, 0, 1) : 0
    return M.hypot(ax + ex * t - x, ay + ey * t - y)
  }
  public func energyOf(_ b: Ball) -> Double { (b.vx * b.vx + b.vy * b.vy) / 2 + BALL_R * BALL_R * (b.wx * b.wx + b.wy * b.wy + b.wz * b.wz) / 5 }
  @inline(__always) func kick(_ b: Ball, _ px: Double, _ py: Double, _ pz: Double, _ rx: Double, _ ry: Double, _ rz: Double) {
    let k = 2.5 / (BALL_R * BALL_R)
    b.vx += px; b.vy += py
    b.wx += k * (ry * pz - rz * py); b.wy += k * (rz * px - rx * pz); b.wz += k * (rx * py - ry * px)
  }
  @inline(__always) func rub(_ b: Ball, _ ux: Double, _ uy: Double, _ uz: Double, _ load: Double, _ mu: Double, _ eff: Double, _ rx: Double, _ ry: Double, _ rz: Double) {
    let u = M.hypot(ux, uy, uz)
    if u < 1e-12 || load <= 0 { return }
    let f = M.min(mu * load, u / eff) / u
    kick(b, -ux * f, -uy * f, -uz * f, rx, ry, rz)
  }
  @inline(__always) func slipX(_ b: Ball) -> Double { b.vx + BALL_R * b.wy }
  @inline(__always) func slipY(_ b: Ball) -> Double { b.vy - BALL_R * b.wx }
  func noseSlip(_ b: Ball, _ tx: Double, _ ty: Double, _ rx: Double, _ ry: Double, _ rz: Double) -> (Double, Double, Double) {
    let vt = b.vx * tx + b.vy * ty
    let ux = vt * tx + b.wy * rz - b.wz * ry, uy = vt * ty + b.wz * rx - b.wx * rz, uz = b.wx * ry - b.wy * rx
    let un = (ux * rx + uy * ry + uz * rz) / (BALL_R * BALL_R)
    return (ux - un * rx, uy - un * ry, uz - un * rz)
  }
  func rail(_ b: Ball, _ nx: Double, _ ny: Double) -> Double {
    let vn = -(b.vx * nx + b.vy * ny)
    if vn <= 0 { return 0 }
    let e = clamp(RAIL_E[0] - RAIL_E[1] * vn, RAIL_E[2], RAIL_E[0]), R = BALL_R
    let tx = -ny, ty = nx
    b.vx += (1 + e) * vn * nx; b.vy += (1 + e) * vn * ny
    let rx = -R * NOSE_C * nx, ry = -R * NOSE_C * ny, rz = -R * NOSE_S, load = (1 + e) * vn / NOSE_C
    var (ux, uy, uz) = noseSlip(b, tx, ty, rx, ry, rz)
    let uh = M.hypot(ux, uy), u0 = M.hypot(uh, uz), u = u0 == 0 || u0.isNaN ? 1 : u0
    let q = uh / u
    rub(b, ux, uy, uz, load, CUSH_MU, 2.5 + q * q, rx, ry, rz)
    (ux, uy, uz) = noseSlip(b, tx, ty, rx, ry, rz)
    let ut = ux * tx + uy * ty
    rub(b, ut * tx, ut * ty, 0, load, CUSH_MU_ALONG, 3.5, rx, ry, rz)
    if b.vz == nil { rub(b, slipX(b), slipY(b), 0, load * NOSE_S, MU_SLIDE, 3.5, 0, 0, R) }
    let s = M.hypot(b.vx, b.vy)
    if s > V_CAP { b.vx *= V_CAP / s; b.vy *= V_CAP / s }
    return vn
  }
  func hitSeg(_ b: Ball, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    let (px, py) = closestOnSeg(ax, ay, bx, by, b.x, b.y)
    var nx = b.x - px, ny = b.y - py
    let d2 = nx * nx + ny * ny
    if d2 >= BALL_R * BALL_R || d2 < 1e-24 { return 0 }
    let d = d2.squareRoot()
    nx /= d; ny /= d
    b.x = px + nx * BALL_R; b.y = py + ny * BALL_R
    return rail(b, nx, ny)
  }
  func hitPost(_ b: Ball, _ px: Double, _ py: Double, _ r: Double) -> Double {
    var nx = b.x - px, ny = b.y - py
    let D = BALL_R + r, d2 = nx * nx + ny * ny
    if d2 >= D * D || d2 < 1e-24 { return 0 }
    let d = d2.squareRoot()
    nx /= d; ny /= d
    b.x = px + nx * D; b.y = py + ny * D
    return rail(b, nx, ny)
  }
  func hitBalls(_ tab: Tab, _ a: Ball, _ b: Ball) {
    var nx = b.x - a.x, ny = b.y - a.y
    let d2 = nx * nx + ny * ny
    if d2 >= 4 * BALL_R * BALL_R || d2 < 1e-24 { return }
    let d = d2.squareRoot(), R = BALL_R
    nx /= d; ny /= d
    let push = (2 * R - d) / 2
    a.x -= nx * push; a.y -= ny * push; b.x += nx * push; b.y += ny * push
    let vn = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
    if vn <= 0 { return }
    var ux = a.vx - b.vx - R * (a.wz + b.wz) * ny, uy = a.vy - b.vy + R * (a.wz + b.wz) * nx
    let uz = R * ((a.wx + b.wx) * ny - (a.wy + b.wy) * nx), un = ux * nx + uy * ny
    ux -= un * nx; uy -= un * ny
    let J = (1 + BALL_E) / 2 * vn
    a.vx -= J * nx; a.vy -= J * ny; b.vx += J * nx; b.vy += J * ny
    let u = M.hypot(ux, uy, uz)
    if u > 1e-12 {
      let f = M.min((THROW_A + THROW_B * M.exp(-THROW_C * u)) * J, u / (5 + 2 * (ux * ux + uy * uy) / (u * u))) / u
      kick(a, -ux * f, -uy * f, -uz * f, R * nx, R * ny, 0)
      kick(b, ux * f, uy * f, uz * f, -R * nx, -R * ny, 0)
    }
    metBalls(tab, a, b, vn)
  }
  func metBalls(_ tab: Tab, _ a: Ball, _ b: Ball, _ vn: Double) {
    let cue: Ball? = a.n == tab.cue ? a : b.n == tab.cue ? b : nil
    if let c = cue { tab.seq.append((c === a ? b : a).n) }
    if let c = cue, tab.first == nil { tab.first = (c === a ? b : a).n; tab.kick = tab.rails[tab.cue] ?? 0 }
    let lo = Swift.min(a.n, b.n), hi = Swift.max(a.n, b.n), key = lo * 64 + hi
    if !tab.met.contains(key) { tab.met.insert(key); tab.contacts.append([lo, hi]) }
    tab.hits.append(Hit(kind: "ball", v: vn, extra: nil))
  }
  func hitAir(_ tab: Tab, _ a: Ball, _ b: Ball) {
    let R = BALL_R, za = a.z ?? 0, zb = b.z ?? 0
    var nx = b.x - a.x, ny = b.y - a.y, nz = zb - za
    let d2 = nx * nx + ny * ny + nz * nz
    if d2 >= 4 * R * R {
      let c: Ball? = a.n == tab.cue ? a : b.n == tab.cue ? b : nil, o = c === a ? b : a
      if let c, c.vz != nil, tab.first == nil, !(tab.over ?? []).contains(o.n) { tab.over = (tab.over ?? []) + [o.n] }
      return
    }
    if d2 < 1e-24 { return }
    let d = d2.squareRoot(), push = (2 * R - d) / 2
    nx /= d; ny /= d; nz /= d
    a.x -= nx * push; a.y -= ny * push; b.x += nx * push; b.y += ny * push
    if a.vz != nil { a.z = M.max(0, za - nz * push) }
    if b.vz != nil { b.z = M.max(0, zb + nz * push) }
    let vn = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny + ((a.vz ?? 0) - (b.vz ?? 0)) * nz
    if vn <= 0 { return }
    let J = (1 + BALL_E) / 2 * vn
    a.vx -= J * nx; a.vy -= J * ny; b.vx += J * nx; b.vy += J * ny
    for (o, jz) in [(a, -J * nz), (b, J * nz)] {
      if let vz = o.vz { o.vz = vz + jz } else if jz > 0.02 { o.z = 0; o.vz = jz }
    }
    metBalls(tab, a, b, vn)
  }

  // MARK: 1d. the table in motion

  public func newTable(_ balls: [Ball], cue: Int = 0) -> Tab {
    let bs = balls.map { b -> Ball in let c = b.copy(); c.wx = 0; c.wy = 0; c.wz = 0; return c }
    return Tab(balls: bs, cue: cue, frozen: frozenOf(balls))
  }
  func frozenOf(_ balls: [Ball]) -> [Int: Int]? {
    if !BUMPERS.isEmpty { return nil }
    var out: [Int: Int]? = nil
    for b in balls {
      if !b.on { continue }
      let m = BALL_R + 2 * FROZEN_ON
      if b.x > m && b.x < TL - m && b.y > m && b.y < TW - m { continue }
      var mask = 0
      for k in 0..<CUSH.count { let c = CUSH[k]; if segGap(c[0], c[1], c[2], c[3], b.x, b.y) <= BALL_R + FROZEN_ON { mask |= 1 << k } }
      if mask != 0 { if out == nil { out = [:] }; out![b.n] = mask }
    }
    return out
  }
  func thaw(_ tab: Tab, _ b: Ball) {
    var mask = tab.frozen![b.n] ?? 0
    for k in 0..<CUSH.count {
      if (mask >> k) & 1 == 0 { continue }
      let c = CUSH[k]
      if segGap(c[0], c[1], c[2], c[3], b.x, b.y) > BALL_R + FROZEN_OFF { mask &= ~(1 << k) }
    }
    tab.frozen![b.n] = mask
  }
  @discardableResult public func strike(_ tab: Tab, _ angle: Double, _ power: Double, _ sp: Spin) -> Tab {
    let c = tab.balls.first { $0.n == tab.cue }!, ox = sp.x * TIP_MAX, oy = sp.y * TIP_MAX
    let v = speedOf(power) * (1 + CUE_RATIO) / (1 + CUE_RATIO + 2.5 * TIP_LOSS * (ox * ox + oy * oy))
    let dx = M.cos(angle), dy = M.sin(angle), k = 2.5 * v / BALL_R
    if sp.e != 0 {
      let ce = M.cos(sp.e), se = M.sin(sp.e), a = angle - M.atan(M.tan(SQUIRT * sp.x) / ce), vh = v * ce
      c.vx = M.cos(a) * vh; c.vy = M.sin(a) * vh
      c.wx = k * (oy * dy + ox * se * dx); c.wy = k * (ox * se * dy - oy * dx); c.wz = -k * ox * ce
      tab.hits.append(Hit(kind: "cue", v: vh, extra: nil))
      let vd = v * se
      if vd >= V_SLATE && oy * ce + M.sqrt(M.max(0, 1 - ox * ox - oy * oy)) * se > 0 {
        c.z = 0; c.vz = E_SLATE * vd
        rub(c, slipX(c), slipY(c), 0, (1 + E_SLATE) * vd, MU_SLIDE, 3.5, 0, 0, BALL_R)
      }
      return tab
    }
    let a = angle - SQUIRT * sp.x
    c.vx = M.cos(a) * v; c.vy = M.sin(a) * v
    c.wx = k * oy * dy; c.wy = -k * oy * dx; c.wz = -k * ox
    tab.hits.append(Hit(kind: "cue", v: v, extra: nil))
    return tab
  }
  @inline(__always) func cloth(_ b: Ball, _ dt: Double) {
    let ux = slipX(b), uy = slipY(b), u = M.hypot(ux, uy), du = 3.5 * MU_SLIDE * G * dt
    if u > du {
      let k = du / u / 3.5
      b.vx -= k * ux; b.vy -= k * uy; b.wy -= 2.5 * k * ux / BALL_R; b.wx += 2.5 * k * uy / BALL_R
    } else {
      if u > 0 { b.vx -= ux / 3.5; b.vy -= uy / 3.5 }
      let sp = M.hypot(b.vx, b.vy), s1 = M.max(0, sp - MU_ROLL * G * dt)
      if sp > 0 { b.vx *= s1 / sp; b.vy *= s1 / sp }
      b.wx = b.vy / BALL_R; b.wy = -b.vx / BALL_R
    }
    let dw = spinA() * dt
    b.wz = b.wz > 0 ? M.max(0, b.wz - dw) : M.min(0, b.wz + dw)
  }
  @inline(__always) func grounded(_ b: Ball) { b.z = nil; b.vz = nil }
  func pot(_ tab: Tab, _ b: Ball, _ k: Int, _ v: Double) {
    b.on = false; b.vx = 0; b.vy = 0; b.wx = 0; b.wy = 0; b.wz = 0
    if b.vz != nil { grounded(b) }
    tab.potted.append(b.n); tab.pocketOf[b.n] = k
    tab.hits.append(Hit(kind: "pocket", v: v, extra: k))
  }
  func offTable(_ tab: Tab, _ b: Ball) {
    let v = M.hypot(b.vx, b.vy)
    pot(tab, b, -1, v)
    tab.hits[tab.hits.count - 1] = Hit(kind: "off", v: v, extra: nil)
  }
  func air(_ tab: Tab, _ b: Ball, _ dt: Double) {
    b.z = b.z! + (b.vz! * dt - 0.5 * G * dt * dt); b.vz = b.vz! - G * dt   /* JS's +=: z + (the whole right side) */
    if b.z! > 0 { return }
    let vin = -b.vz!, e = vin >= V_SLATE ? E_SLATE : 0
    rub(b, slipX(b), slipY(b), 0, (1 + e) * vin, MU_SLIDE, 3.5, 0, 0, BALL_R)
    tab.hits.append(Hit(kind: "land", v: vin, extra: nil))
    if e != 0 { b.z = 0; b.vz = e * vin } else { grounded(b) }
  }
  func overMouth(_ b: Ball) -> Bool {
    for k in 0..<POCKETS.count {
      let p = POCKETS[k], m = POCKET_AIM[k], w = (k == 1 || k == 4 ? SIDE_W : CORNER_W) / 2 + BALL_R
      let dx = b.x - p[0], dy = b.y - p[1], r = POCKET_R[k] + BALL_R, mx = b.x - m[0], my = b.y - m[1]
      if dx * dx + dy * dy < r * r || (!MOUTHS.isEmpty && mx * mx + my * my < w * w) { return true }
    }
    return false
  }
  func onLip(_ b: Ball) -> Int {
    for k in 0..<POCKETS.count {
      let p = POCKETS[k], r = POCKET_R[k] + (BUMPERS.isEmpty ? POCKET_LIP : 0)
      let dx = b.x - p[0], dy = b.y - p[1]
      if dx * dx + dy * dy < r * r { return k }
    }
    return -1
  }
  /* one fixed step; true while anything is still rolling */
  @discardableResult public func stepTable(_ tab: Tab) -> Bool {
    let dt = SIM_DT, B = tab.balls, R = BALL_R, R2 = 4 * R * R, lo = R + 1e-6, edge = M.max(lo, HOLE_IN + 1e-6)
    for b in B {
      if !b.on || b.still { continue }
      if b.vz != nil { air(tab, b, dt) } else { cloth(b, dt) }
      b.x += b.vx * dt; b.y += b.vy * dt
      if b.n == tab.cue && b.x >= HEAD_X && tab.first == nil { tab.crossed = true }
    }
    let n = B.count
    for i in 0..<n {
      let a = B[i]
      if !a.on { continue }
      let sa = a.still
      var j = i + 1
      while j < n {
        let b = B[j]; j += 1
        if !b.on { continue }
        let dx = b.x - a.x, dy = b.y - a.y
        if dx * dx + dy * dy >= R2 || (sa && b.still) { continue }
        if a.vz != nil || b.vz != nil { hitAir(tab, a, b) } else { hitBalls(tab, a, b) }
      }
    }
    var moving = false
    let cushTop = cushionTop()
    for b in B {
      if !b.on { continue }
      if !BUMPERS.isEmpty && !b.still && bumperStep(tab, b) { continue }
      if let fr = tab.frozen, (fr[b.n] ?? 0) != 0, !b.still { thaw(tab, b) }
      if BED_LINES != nil ? !bedIn(b.x, b.y, lo) : b.x < lo || b.x > TL - lo || b.y < edge || b.y > TW - edge {
        let fly = (b.z ?? 0) > 0, over = fly && b.z! >= cushTop
        var k = 0
        while !over && k < CUSH.count {
          let c = CUSH[k], v = hitSeg(b, c[0], c[1], c[2], c[3])
          if v != 0 {
            if tab.frozen == nil || ((tab.frozen![b.n] ?? 0) >> k) & 1 == 0 {
              if tab.first != nil { tab.railAfter = true }
              if k < JAW_FROM { tab.rails[b.n] = (tab.rails[b.n] ?? 0) + 1; tab.railSeq.append([b.n, k]) }
              if (k < JAW_FROM || !BUMPERS.isEmpty) && tab.railAt[b.n] == nil { tab.railAt[b.n] = [b.x, b.y] }
            }
            if k < JAW_FROM && b.n == tab.cue { tab.seq.append(-1) }
            tab.hits.append(Hit(kind: k >= JAW_FROM ? "jaw" : "rail", v: v, extra: nil))
          }
          k += 1
        }
        if !over {
          for q in JAW_ARCS {
            let v = hitPost(b, q[0], q[1], q[2])
            if v != 0 { if tab.first != nil { tab.railAfter = true }; tab.hits.append(Hit(kind: "jaw", v: v, extra: nil)) }
          }
        }
        let off = BED_LINES != nil ? !bedIn(b.x, b.y, 0) : b.x < 0 || b.x > TL || b.y < 0 || b.y > TW
        if fly { if off && !overMouth(b) { offTable(tab, b); continue }; moving = true; continue }
        var hole = -1, near = -1, nd = Double.infinity
        for k in 0..<POCKETS.count {
          let p = POCKETS[k], dx = b.x - p[0], dy = b.y - p[1], d2 = dx * dx + dy * dy
          /* SKIMS may be shorter than POCKETS (the octagon keeps the last table's: after carom, none): undefined, no skim */
          let sk = k < SKIMS.count ? SKIMS[k] : 0
          let r = sk != 0 ? POCKET_R[k] - sk * M.min(1, M.hypot(b.vx, b.vy) / CUP_V) : POCKET_R[k]
          if d2 < r * r { hole = k; break }
          let m = POCKET_AIM[k], ex = b.x - m[0], ey = b.y - m[1], e2 = ex * ex + ey * ey
          if e2 < nd { nd = e2; near = k }
        }
        if hole < 0 && off && MOUTHS.isEmpty { tab.escaped += 1; pot(tab, b, -1, M.hypot(b.vx, b.vy)); continue }
        if hole < 0 && off { hole = near; if nd > ESCAPE_R * ESCAPE_R { tab.escaped += 1 } }
        if hole >= 0 { pot(tab, b, hole, M.hypot(b.vx, b.vy)); continue }
      }
      if !b.still {
        let v2 = b.vx * b.vx + b.vy * b.vy
        let sx = slipX(b), sy = slipY(b)
        let slip2: Double = sx * sx + sy * sy
        if b.vz != nil { moving = true }
        else if v2 < STOP_V * STOP_V && slip2 < 1e-12 {
          let k = onLip(b)
          if k >= 0 { pot(tab, b, k, v2.squareRoot()); continue }
          b.vx = 0; b.vy = 0; b.wx = 0; b.wy = 0
          if b.wz != 0 { moving = true }
        } else { moving = true }
      }
    }
    tab.t += dt; tab.steps += 1
    if !moving { tab.end = "rest"; return false }
    if tab.t >= MAX_SIM_T {
      for b in B { b.vx = 0; b.vy = 0; b.wx = 0; b.wy = 0; b.wz = 0; if b.vz != nil { grounded(b) } }
      tab.end = "timeout"; return false
    }
    return true
  }
  public func resultOf(_ tab: Tab) -> ShotResult {
    ShotResult(balls: tab.balls.map { $0.copy() }, cue: tab.cue, first: tab.first, railAfter: tab.railAfter, crossed: tab.crossed,
      potted: tab.potted, pocketOf: tab.pocketOf, end: tab.end, t: tab.t, steps: tab.steps, rails: tab.rails, kick: tab.kick,
      contacts: tab.contacts, railAt: tab.railAt, seq: tab.seq, railSeq: tab.railSeq, over: tab.over)
  }
  public struct Shot { public var angle: Double, power: Double, spin: Spin, ball: Int
    public init(angle: Double, power: Double, spin: Spin = Spin(), ball: Int = 0) { self.angle = angle; self.power = power; self.spin = spin; self.ball = ball }
  }
  public func simulateShot(_ balls: [Ball], _ shot: Shot) -> ShotResult {
    let tab = strike(newTable(balls, cue: shot.ball), shot.angle, shot.power, shot.spin)
    while stepTable(tab) {}
    return resultOf(tab)
  }
}
