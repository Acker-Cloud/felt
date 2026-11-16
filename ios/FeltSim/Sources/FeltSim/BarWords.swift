/* hudControls' words (page 6): the power bar's label (#powerLab) and whether the bar is idle (#powerBar.idle: the
   chevrons alone, the shimmer), and whether the fine wheel is dimmed (#fineWheel.off). The page's state, as the app
   reads it: aim (the player's to aim), thinking (the CPU's turn, its search, think and cue's turn up to the stroke),
   stroke and rolling (the shot under way), choose (a choice the rules give, the player's to make), over (no game, or
   it is won). */
public enum BarWords {
  public enum State: String, Sendable { case aim, thinking, stroke, rolling, choose, over }
  public static let PULL = "Pull to shoot", CALL = "Call your shot", THINK = "CPU thinking", ROLL = "Rolling", CHOOSE = "Your choice", REPLAY = "Replay"
  /* lab: a replay, the live percentage, the player's aim (the call's words, Call your shot, or Pull to shoot), else the
     state's words; nothing once the game is over */
  public static func lab(_ st: State, human: Bool, replay: Bool, live: Bool, pct: Int, call: String?, ready: Bool) -> String {
    if replay { return REPLAY }
    if live { return "\(pct)%" }
    if st == .aim && human { return !ready && !(call?.contains("\u{00b7}") ?? false) ? CALL : call ?? PULL }
    switch st {
    case .thinking: return THINK
    case .rolling, .stroke: return ROLL
    case .choose: return CHOOSE
    default: return ""
    }
  }
  /* idle: ready to pull, the chevrons alone say it */
  public static func idle(_ lab: String) -> Bool { lab == PULL }
  /* the fine wheel is off whenever the turn is not the player's to aim, and through a replay */
  public static func wheelOff(_ st: State, human: Bool, replay: Bool) -> Bool { !(st == .aim && human) || replay }
}
