// MLB Booth data layer: pure parse/format functions over MLB Stats API
// responses (schedule, GUMBO live feed, standings) plus the optional BYOK
// recap request/response shapes. No QML or network access here — the same
// file loads in Quickshell (via `import "Model.js" as Model`) and in node
// for the unit suite.

// The 30 clubs, keyed by statsapi abbreviation. Fixed data: ids and
// abbreviations are stable season over season, and shipping them beats a
// fourth network fetch just to fill the team picker. A unit test pins this
// table against manifest.json's picker options so the two cannot drift.
var TEAMS = {
  ATH: { id: 133, name: "Athletics" },
  ATL: { id: 144, name: "Atlanta Braves" },
  AZ:  { id: 109, name: "Arizona Diamondbacks" },
  BAL: { id: 110, name: "Baltimore Orioles" },
  BOS: { id: 111, name: "Boston Red Sox" },
  CHC: { id: 112, name: "Chicago Cubs" },
  CIN: { id: 113, name: "Cincinnati Reds" },
  CLE: { id: 114, name: "Cleveland Guardians" },
  COL: { id: 115, name: "Colorado Rockies" },
  CWS: { id: 145, name: "Chicago White Sox" },
  DET: { id: 116, name: "Detroit Tigers" },
  HOU: { id: 117, name: "Houston Astros" },
  KC:  { id: 118, name: "Kansas City Royals" },
  LAA: { id: 108, name: "Los Angeles Angels" },
  LAD: { id: 119, name: "Los Angeles Dodgers" },
  MIA: { id: 146, name: "Miami Marlins" },
  MIL: { id: 158, name: "Milwaukee Brewers" },
  MIN: { id: 142, name: "Minnesota Twins" },
  NYM: { id: 121, name: "New York Mets" },
  NYY: { id: 147, name: "New York Yankees" },
  PHI: { id: 143, name: "Philadelphia Phillies" },
  PIT: { id: 134, name: "Pittsburgh Pirates" },
  SD:  { id: 135, name: "San Diego Padres" },
  SEA: { id: 136, name: "Seattle Mariners" },
  SF:  { id: 137, name: "San Francisco Giants" },
  STL: { id: 138, name: "St. Louis Cardinals" },
  TB:  { id: 139, name: "Tampa Bay Rays" },
  TEX: { id: 140, name: "Texas Rangers" },
  TOR: { id: 141, name: "Toronto Blue Jays" },
  WSH: { id: 120, name: "Washington Nationals" }
}

var DIVISIONS = {
  200: "AL West",
  201: "AL East",
  202: "AL Central",
  203: "NL West",
  204: "NL East",
  205: "NL Central"
}

// A response bigger than this is not a baseball feed. The curl argv carries
// the same number as --max-filesize, but that flag is only reliable when the
// server sends Content-Length (and only for HTTP), so the real bound lives
// here, in-process, before JSON.parse runs on the shell's UI thread.
var MAX_BODY_CHARS = 4000000

function teamAbbrs() {
  var out = []
  for (var k in TEAMS) out.push(k)
  out.sort()
  return out
}

function teamId(abbr) {
  var t = TEAMS[String(abbr || "").toUpperCase()]
  return t ? t.id : 0
}

// Sanitize every string that comes from the network before it reaches a QML
// Text. Strips: angle brackets (a first-party bar label renders as Qt
// AutoText, which promotes an HTML-looking string to StyledText — an
// `<img src=...>` in a name or play description would make the shell process
// fetch a URL); ASCII controls; bidi override/isolate marks and Unicode tag
// characters (display-spoofing, CVE-2021-42574 class — tag chars are the
// surrogate pair DB40 DC00-DC7F, written that way so the regex needs no /u
// flag support from the QML engine). Then caps length, because a
// pathologically long field is a layout-cost problem.
function clean(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[<>]/g, "")
    .replace(/[\x00-\x1f\x7f]/g, "")
    .replace(/[\u200b-\u200f\u202a-\u202e\u2066-\u2069]/g, "")
    .replace(/\uDB40[\uDC00-\uDC7F]/g, "")
  var cap = max || 64
  return s.length > cap ? s.slice(0, cap) : s
}

function num(v) {
  var n = Number(v)
  return isNaN(n) ? 0 : n
}

// statsapi /schedule (hydrate=team,linescore) -> ordered games for one team.
// Each game: { gamePk, startMs, state, detail, home/away: {id, abbr, name,
// score}, isHome }. States: "pre" | "live" | "final" | "postponed".
// Postponed, cancelled, and suspended games get their own state because
// statsapi codes them under misleading abstract states (Postponed/Cancelled
// are abstract "Final" with no score; Suspended is abstract "Live" that
// would otherwise wedge the widget in live mode until the resumption).
// A game whose date does not parse is dropped rather than mis-sorted.
function parseSchedule(raw, myTeamId) {
  var out = []
  var s = String(raw || "")
  if (s.length > MAX_BODY_CHARS) return out
  var data
  try { data = JSON.parse(s) } catch (e) { return out }
  if (!data || !data.dates) return out
  for (var i = 0; i < data.dates.length; i++) {
    var games = data.dates[i].games || []
    for (var j = 0; j < games.length; j++) {
      var g = games[j]
      var startMs = Date.parse(g.gameDate)
      if (isNaN(startMs)) continue
      var detail = clean(g.status ? g.status.detailedState : "", 32)
      var abstract = g.status ? String(g.status.abstractGameState) : ""
      var state
      if (/^(Postponed|Cancelled|Suspended)/.test(detail)) state = "postponed"
      else if (abstract === "Live") state = "live"
      else if (abstract === "Final") state = "final"
      else state = "pre"
      var home = sideInfo(g.teams && g.teams.home)
      var away = sideInfo(g.teams && g.teams.away)
      out.push({
        gamePk: num(g.gamePk),
        startMs: startMs,
        state: state,
        detail: detail,
        home: home,
        away: away,
        isHome: home.id === myTeamId
      })
    }
  }
  out.sort(function(a, b) { return a.startMs - b.startMs })
  return out
}

function sideInfo(side) {
  var t = side && side.team ? side.team : {}
  return {
    id: num(t.id),
    abbr: clean(t.abbreviation || "", 6),
    name: clean(t.teamName || t.name || "", 32),
    score: side && side.score !== undefined && side.score !== null ? num(side.score) : -1
  }
}

// How far past the scheduled first pitch a game may run late (rain delay,
// statsapi lagging the status flip) while still holding the pill. Without
// this grace, a "Delayed Start: Rain" game — which statsapi keeps in
// abstract Preview — would collapse the widget at exactly the moment the
// user is looking for it.
var NEXT_GRACE_MS = 6 * 3600000

// A finished game reads on the pill for this long past its estimated end.
var FINAL_FRESH_MS = 8 * 3600000

// Rough game length, used to estimate the final out from first pitch. The
// postgame window measures from the END of a game; measuring from first
// pitch silently ate the whole window on a split doubleheader.
var GAME_EST_MS = Math.round(3.25 * 3600000)

// The bar's one question: what matters right now? Returns
//   { status: "live",  game }             a game is in progress
//   { status: "final", game }             most recent completed final, shown
//                                         while fresh and nothing is closer
//   { status: "next",  game, msUntil }    between games (msUntil can be
//                                         negative during a delayed start)
//   { status: "off" }                     nothing usable in the window
// Postponed/cancelled/suspended games are skipped everywhere: they carry no
// score, no live feed, and no reliable restart time.
function currentOrNext(games, nowMs) {
  var live = null
  var lastFinal = null
  var next = null
  for (var i = 0; i < games.length; i++) {
    var g = games[i]
    if (g.state === "live") { live = g; break }
    if (g.state === "final" && g.home.score >= 0 && g.away.score >= 0
        && (!lastFinal || g.startMs > lastFinal.startMs)) lastFinal = g
    if (g.state === "pre" && g.startMs > nowMs - NEXT_GRACE_MS
        && (!next || g.startMs < next.startMs)) next = g
  }
  if (live) return { status: "live", game: live }
  if (lastFinal) {
    var age = nowMs - (lastFinal.startMs + GAME_EST_MS)
    if (age < 0) age = 0
    var timeToNext = next ? next.startMs - nowMs : -1
    if (age < FINAL_FRESH_MS && (!next || timeToNext < 0 || age < timeToNext))
      return { status: "final", game: lastFinal }
  }
  if (next) return { status: "next", game: next, msUntil: next.startMs - nowMs }
  return { status: "off" }
}

// Compact countdown: keeps the two most significant units so the pill stays
// narrow. "2d 4h" -> "1h 05m" -> "14m" -> "now" (which also covers a
// delayed start already past its scheduled time).
function countdown(msUntil) {
  if (msUntil <= 30000) return "now"
  var totalMinutes = Math.round(msUntil / 60000)
  var days = Math.floor(totalMinutes / 1440)
  var hours = Math.floor((totalMinutes % 1440) / 60)
  var minutes = totalMinutes % 60
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m"
  return (minutes < 10 ? "0" : "") + minutes + "m"
}

// The fully-populated zero object the panel holds before the first GUMBO
// poll and between games. Every field a binding touches exists, so no
// binding ever evaluates to undefined (which logs a scene warning even
// inside an invisible section).
function emptyGumbo() {
  return {
    valid: false,
    state: "",
    awayAbbr: "", homeAbbr: "",
    awayRuns: 0, homeRuns: 0,
    awayHits: 0, homeHits: 0,
    awayErrors: 0, homeErrors: 0,
    inning: 0, inningOrdinal: "", inningState: "", isTop: false,
    balls: 0, strikes: 0, outs: 0,
    bases: { first: false, second: false, third: false },
    batter: "", pitcher: "",
    lastPlay: "",
    innings: []
  }
}

// GUMBO /game/<pk>/feed/live -> the live-view model. Malformed or oversized
// input returns the empty shape so the panel keeps last-good state.
function parseGumbo(raw) {
  var invalid = emptyGumbo()
  var s = String(raw || "")
  if (s.length > MAX_BODY_CHARS) return invalid
  var data
  try { data = JSON.parse(s) } catch (e) { return invalid }
  if (!data || !data.liveData || !data.gameData) return invalid
  var ls = data.liveData.linescore || {}
  var plays = data.liveData.plays || {}
  var cp = plays.currentPlay || {}
  var count = cp.count || {}
  var offense = ls.offense || {}
  var teams = data.gameData.teams || {}
  var lsTeams = ls.teams || {}

  var currentInning = num(ls.currentInning)
  var inningState = clean(ls.inningState, 10)

  // Cap the innings list: a real game has ~9-20; the cap means a hostile or
  // corrupt feed cannot turn the Repeater into 10^5 items on the UI thread.
  var innings = []
  var rawInnings = ls.innings || []
  var maxInnings = rawInnings.length > 30 ? 30 : rawInnings.length
  for (var i = 0; i < maxInnings; i++) {
    var inn = rawInnings[i]
    var n = num(inn.num) || (i + 1)
    var away = inn.away && inn.away.runs !== undefined && inn.away.runs !== null ? num(inn.away.runs) : -1
    var home = inn.home && inn.home.runs !== undefined && inn.home.runs !== null ? num(inn.home.runs) : -1
    // The half being batted right now is a 0 in progress, not an unplayed
    // dash — a box score never shows "-" for the inning on the field.
    if (n === currentInning) {
      if (inningState === "Top" && away < 0) away = 0
      if (inningState === "Bottom" && home < 0) home = 0
    }
    innings.push({ n: n, away: away, home: home })
  }

  var lastPlay = ""
  var all = plays.allPlays || []
  for (var j = all.length - 1; j >= 0; j--) {
    var p = all[j]
    if (p.about && p.about.isComplete === true && p.result && p.result.description) {
      lastPlay = clean(p.result.description, 160)
      break
    }
  }

  // At the instant an at-bat ends, currentPlay IS the completed play, so its
  // matchup still names the batter who just made the out — right above a
  // last-play line describing that same out. Blank the matchup at that
  // boundary; the panel hides the row until the next batter steps in.
  var batter = ""
  var pitcher = ""
  if (!(cp.about && cp.about.isComplete === true)) {
    batter = clean(cp.matchup && cp.matchup.batter ? cp.matchup.batter.fullName : "", 32)
    pitcher = clean(cp.matchup && cp.matchup.pitcher ? cp.matchup.pitcher.fullName : "", 32)
  }

  return {
    valid: true,
    state: data.gameData.status ? String(data.gameData.status.abstractGameState) : "",
    awayAbbr: clean(teams.away ? teams.away.abbreviation : "", 6),
    homeAbbr: clean(teams.home ? teams.home.abbreviation : "", 6),
    awayRuns: num(lsTeams.away ? lsTeams.away.runs : 0),
    homeRuns: num(lsTeams.home ? lsTeams.home.runs : 0),
    awayHits: num(lsTeams.away ? lsTeams.away.hits : 0),
    homeHits: num(lsTeams.home ? lsTeams.home.hits : 0),
    awayErrors: num(lsTeams.away ? lsTeams.away.errors : 0),
    homeErrors: num(lsTeams.home ? lsTeams.home.errors : 0),
    inning: currentInning,
    inningOrdinal: clean(ls.currentInningOrdinal, 6),
    inningState: inningState,
    isTop: ls.isTopInning === true,
    balls: num(count.balls !== undefined ? count.balls : ls.balls),
    strikes: num(count.strikes !== undefined ? count.strikes : ls.strikes),
    outs: num(count.outs !== undefined ? count.outs : ls.outs),
    bases: {
      first: !!offense.first,
      second: !!offense.second,
      third: !!offense.third
    },
    batter: batter,
    pitcher: pitcher,
    lastPlay: lastPlay,
    innings: innings
  }
}

// Count for display. At the instant an at-bat ends, GUMBO's currentPlay
// still carries the completed count (a strikeout reads strikes=3, a walk
// balls=4). Broadcast convention resets the graphic to 0-0 for the next
// batter; caught live on the rig when the pill read "3-3".
function countText(balls, strikes) {
  var b = num(balls)
  var s = num(strikes)
  if (b > 3 || s > 2) return "0-0"
  return b + "-" + s
}

// Base-out state in broadcast words: "Empty", "1st", "1st & 3rd",
// "Bases loaded".
function basesText(bases) {
  if (!bases) return "Empty"
  var on = []
  if (bases.first) on.push("1st")
  if (bases.second) on.push("2nd")
  if (bases.third) on.push("3rd")
  if (on.length === 0) return "Empty"
  if (on.length === 3) return "Bases loaded"
  return on.join(" & ")
}

// Half-inning tag for the pill: T4 / B7. Between halves GUMBO says
// "Middle"/"End"; both display with their own letter.
function inningTag(gumbo) {
  if (!gumbo || !gumbo.inning) return ""
  var st = String(gumbo.inningState || "")
  if (st === "Top") return "T" + gumbo.inning
  if (st === "Bottom") return "B" + gumbo.inning
  if (st === "Middle") return "M" + gumbo.inning
  if (st === "End") return "E" + gumbo.inning
  return (gumbo.isTop ? "T" : "B") + gumbo.inning
}

// The team's own score first, regardless of home/away.
function scorePair(state, myTeamId) {
  var g = state.game
  var mine = g.home.id === myTeamId ? g.home : g.away
  var theirs = g.home.id === myTeamId ? g.away : g.home
  return { mine: mine, theirs: theirs }
}

// Bar pill text.
//   live, gumbo known : "ATL 1-0 · T4 · 2-2, 0 out"
//   live, gumbo not yet: "ATL 1-0 · LIVE"
//   next              : "ATL @ CWS 1h 05m" (or "... now" in a delayed start)
//   final             : "ATL W 4-2"
//   off               : ""
function pillText(state, myTeamId, gumbo) {
  if (!state || state.status === "off") return ""
  var s = scorePair(state, myTeamId)
  var sep = state.game.isHome ? "vs" : "@"
  if (state.status === "live") {
    var score = s.mine.abbr + " " + Math.max(0, s.mine.score) + "-" + Math.max(0, s.theirs.score)
    if (gumbo && gumbo.valid && gumbo.inning) {
      // GUMBO score is fresher than the schedule hydrate; prefer it.
      var mineRuns = state.game.isHome ? gumbo.homeRuns : gumbo.awayRuns
      var theirRuns = state.game.isHome ? gumbo.awayRuns : gumbo.homeRuns
      score = s.mine.abbr + " " + mineRuns + "-" + theirRuns
      return score + " · " + inningTag(gumbo) + " · "
        + countText(gumbo.balls, gumbo.strikes) + ", " + gumbo.outs + " out"
    }
    return score + " · LIVE"
  }
  if (state.status === "final") {
    var mineScore = Math.max(0, s.mine.score)
    var theirScore = Math.max(0, s.theirs.score)
    var wl = mineScore > theirScore ? "W" : (mineScore < theirScore ? "L" : "T")
    return s.mine.abbr + " " + wl + " " + mineScore + "-" + theirScore
  }
  return s.mine.abbr + " " + sep + " " + s.theirs.abbr + " " + countdown(state.msUntil)
}

// statsapi /standings (leagueId=103,104) -> the division holding teamId:
// { division, rows: [{rank, id, name, wins, losses, gb, streak}] }.
function parseStandings(raw, myTeamId) {
  var empty = { division: "", rows: [] }
  var s = String(raw || "")
  if (s.length > MAX_BODY_CHARS) return empty
  var data
  try { data = JSON.parse(s) } catch (e) { return empty }
  if (!data || !data.records) return empty
  for (var i = 0; i < data.records.length; i++) {
    var rec = data.records[i]
    var teamRecords = rec.teamRecords || []
    var hasMine = false
    for (var j = 0; j < teamRecords.length; j++) {
      if (teamRecords[j].team && teamRecords[j].team.id === myTeamId) { hasMine = true; break }
    }
    if (!hasMine) continue
    var rows = []
    for (var k = 0; k < teamRecords.length; k++) {
      var tr = teamRecords[k]
      rows.push({
        rank: parseInt(tr.divisionRank, 10) || (k + 1),
        id: tr.team ? num(tr.team.id) : 0,
        name: clean(tr.team ? tr.team.name : "", 32),
        wins: num(tr.wins),
        losses: num(tr.losses),
        gb: clean(tr.gamesBack || "-", 8),
        streak: clean(tr.streak ? tr.streak.streakCode : "", 6)
      })
    }
    rows.sort(function(a, b) { return a.rank - b.rank })
    var divId = rec.division ? rec.division.id : 0
    return { division: DIVISIONS[divId] || "", rows: rows }
  }
  return empty
}

// ---- Optional BYOK recap (OpenAI-compatible chat completions). Fills the
//      dead air between games; never used during live play.

// A stable key for "the game situation the recap describes". The panel only
// regenerates when this changes, so one storyline per game state, cached
// hard, not one per refresh tick.
function recapCacheKey(state) {
  if (!state || state.status === "off") return "off"
  if (state.status === "live") return "live"
  var g = state.game
  return state.status + ":" + g.gamePk
}

// Compact context for the prompt. Plain facts only — the model writes the
// color, the widget supplies the truth.
function recapContext(teamAbbr, state, standings, games, nowMs) {
  var t = TEAMS[String(teamAbbr || "").toUpperCase()]
  var lines = []
  lines.push("Team: " + (t ? t.name : teamAbbr))
  if (standings && standings.rows.length) {
    for (var i = 0; i < standings.rows.length; i++) {
      var r = standings.rows[i]
      if (t && r.id === t.id) {
        lines.push("Record: " + r.wins + "-" + r.losses + ", " + ordinal(r.rank)
          + " in the " + standings.division + ", " + r.gb + " GB"
          + (r.streak ? ", streak " + r.streak : ""))
        break
      }
    }
  }
  if (state && state.status === "final") {
    var s = scorePair(state, t ? t.id : 0)
    var verb = s.mine.score > s.theirs.score ? "beat"
      : (s.mine.score < s.theirs.score ? "lost to" : "tied")
    lines.push("Last game: " + verb + " " + s.theirs.name + " " + s.mine.score + "-" + s.theirs.score)
  }
  if (games) {
    for (var j = 0; j < games.length; j++) {
      var g = games[j]
      if (g.state === "pre" && g.startMs > nowMs) {
        var opp = g.isHome ? g.away : g.home
        lines.push("Next game: " + (g.isHome ? "home vs " : "away at ") + opp.name
          + " in " + countdown(g.startMs - nowMs))
        break
      }
    }
  }
  return lines.join("\n")
}

function ordinal(n) {
  if (n === 1) return "1st"
  if (n === 2) return "2nd"
  if (n === 3) return "3rd"
  return n + "th"
}

// Request body for POST {base}/chat/completions. One short completion per
// game-state change. max_tokens leaves headroom for reasoning models that
// spend tokens thinking before answering: proven live with 220 against a
// hosted reasoning model, which returned finish_reason "length" and an
// empty content field.
function recapRequestBody(model, context) {
  return JSON.stringify({
    model: String(model || ""),
    max_tokens: 700,
    temperature: 0.7,
    messages: [
      {
        role: "system",
        content: "You write two or three tight sentences of baseball color for a desktop widget. "
          + "Plain language, no hype words, no emoji, no hashtags, no em dashes. "
          + "Use only the facts provided. Do not invent scores, players, or dates."
      },
      { role: "user", content: "Write tonight's storyline from these facts:\n" + String(context || "") }
    ]
  })
}

// choices[0].message.content, sanitized and capped. Some OpenAI-compatible
// servers return content as an array of typed parts; join the text parts.
// Anything malformed or oversized returns "" and the panel simply shows no
// recap section.
function parseRecap(raw) {
  var s = String(raw || "")
  if (s.length > MAX_BODY_CHARS) return ""
  var data
  try { data = JSON.parse(s) } catch (e) { return "" }
  var c = data && data.choices && data.choices[0]
  var content = c && c.message ? c.message.content : ""
  if (content && content.length !== undefined && typeof content !== "string") {
    var parts = []
    for (var i = 0; i < content.length; i++) {
      var p = content[i]
      if (p && typeof p.text === "string") parts.push(p.text)
    }
    content = parts.join(" ")
  }
  return clean(content, 600)
}

if (typeof module !== "undefined") {
  module.exports = {
    teamAbbrs: teamAbbrs,
    teamId: teamId,
    clean: clean,
    parseSchedule: parseSchedule,
    currentOrNext: currentOrNext,
    countdown: countdown,
    emptyGumbo: emptyGumbo,
    parseGumbo: parseGumbo,
    countText: countText,
    basesText: basesText,
    inningTag: inningTag,
    scorePair: scorePair,
    pillText: pillText,
    parseStandings: parseStandings,
    recapCacheKey: recapCacheKey,
    recapContext: recapContext,
    recapRequestBody: recapRequestBody,
    parseRecap: parseRecap
  }
}
