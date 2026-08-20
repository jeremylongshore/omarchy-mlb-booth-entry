// MLB Booth data layer: pure parse/format functions over MLB Stats API
// responses (schedule, GUMBO live feed, standings) plus the optional BYOK
// recap request/response shapes. No QML or network access here — the same
// file loads in Quickshell (via `import "Model.js" as Model`) and in node
// for the unit suite.

// The 30 clubs, keyed by statsapi abbreviation. Fixed data: ids and
// abbreviations are stable season over season, and shipping them beats a
// fourth network fetch just to fill the team picker.
var TEAMS = {
  ATH: { id: 133, div: 200, name: "Athletics" },
  ATL: { id: 144, div: 204, name: "Atlanta Braves" },
  AZ:  { id: 109, div: 203, name: "Arizona Diamondbacks" },
  BAL: { id: 110, div: 201, name: "Baltimore Orioles" },
  BOS: { id: 111, div: 201, name: "Boston Red Sox" },
  CHC: { id: 112, div: 205, name: "Chicago Cubs" },
  CIN: { id: 113, div: 205, name: "Cincinnati Reds" },
  CLE: { id: 114, div: 202, name: "Cleveland Guardians" },
  COL: { id: 115, div: 203, name: "Colorado Rockies" },
  CWS: { id: 145, div: 202, name: "Chicago White Sox" },
  DET: { id: 116, div: 202, name: "Detroit Tigers" },
  HOU: { id: 117, div: 200, name: "Houston Astros" },
  KC:  { id: 118, div: 202, name: "Kansas City Royals" },
  LAA: { id: 108, div: 200, name: "Los Angeles Angels" },
  LAD: { id: 119, div: 203, name: "Los Angeles Dodgers" },
  MIA: { id: 146, div: 204, name: "Miami Marlins" },
  MIL: { id: 158, div: 205, name: "Milwaukee Brewers" },
  MIN: { id: 142, div: 202, name: "Minnesota Twins" },
  NYM: { id: 121, div: 204, name: "New York Mets" },
  NYY: { id: 147, div: 201, name: "New York Yankees" },
  PHI: { id: 143, div: 204, name: "Philadelphia Phillies" },
  PIT: { id: 134, div: 205, name: "Pittsburgh Pirates" },
  SD:  { id: 135, div: 203, name: "San Diego Padres" },
  SEA: { id: 136, div: 200, name: "Seattle Mariners" },
  SF:  { id: 137, div: 203, name: "San Francisco Giants" },
  STL: { id: 138, div: 205, name: "St. Louis Cardinals" },
  TB:  { id: 139, div: 201, name: "Tampa Bay Rays" },
  TEX: { id: 140, div: 200, name: "Texas Rangers" },
  TOR: { id: 141, div: 201, name: "Toronto Blue Jays" },
  WSH: { id: 120, div: 204, name: "Washington Nationals" }
}

var DIVISIONS = {
  200: "AL West",
  201: "AL East",
  202: "AL Central",
  203: "NL West",
  204: "NL East",
  205: "NL Central"
}

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

function teamDivision(abbr) {
  var t = TEAMS[String(abbr || "").toUpperCase()]
  return t ? t.div : 0
}

// Sanitize every string that comes from the API before it reaches a QML
// Text. Two reasons: (1) a first-party bar label renders as Qt AutoText,
// which promotes an HTML-looking string to StyledText — an `<img src=...>`
// in a name or play description would make the shell process fetch a URL;
// stripping angle brackets defuses that. (2) A pathologically long field is
// a layout-cost problem, so cap it.
function clean(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[<>]/g, "").replace(/[\x00-\x1f\x7f]/g, "")
  var cap = max || 64
  return s.length > cap ? s.slice(0, cap) : s
}

// statsapi /schedule (hydrate=team,linescore) -> ordered games for one team.
// Each game: { gamePk, startMs, state ("pre"|"live"|"final"), detail,
//   home/away: {id, abbr, name, score}, isHome }.
// A game whose date does not parse is dropped rather than mis-sorted.
function parseSchedule(raw, myTeamId) {
  var out = []
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return out }
  if (!data || !data.dates) return out
  for (var i = 0; i < data.dates.length; i++) {
    var games = data.dates[i].games || []
    for (var j = 0; j < games.length; j++) {
      var g = games[j]
      var startMs = Date.parse(g.gameDate)
      if (isNaN(startMs)) continue
      var abstract = g.status ? String(g.status.abstractGameState) : ""
      var state = abstract === "Live" ? "live" : (abstract === "Final" ? "final" : "pre")
      var home = sideInfo(g.teams && g.teams.home)
      var away = sideInfo(g.teams && g.teams.away)
      out.push({
        gamePk: g.gamePk || 0,
        startMs: startMs,
        state: state,
        detail: clean(g.status ? g.status.detailedState : "", 32),
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
    id: t.id || 0,
    abbr: clean(t.abbreviation || "", 6),
    name: clean(t.teamName || t.name || "", 32),
    score: side && side.score !== undefined && side.score !== null ? side.score : -1
  }
}

// The bar's one question: what matters right now? Returns
//   { status: "live",  game }             a game is in progress
//   { status: "final", game }             most recent final, shown until the
//                                         next game is closer than the last
//                                         final is old (postgame window)
//   { status: "next",  game, msUntil }    between games
//   { status: "off" }                     nothing scheduled in the window
function currentOrNext(games, nowMs) {
  var live = null
  var lastFinal = null
  var next = null
  for (var i = 0; i < games.length; i++) {
    var g = games[i]
    if (g.state === "live") { live = g; break }
    if (g.state === "final" && (!lastFinal || g.startMs > lastFinal.startMs)) lastFinal = g
    if (g.state === "pre" && g.startMs > nowMs && (!next || g.startMs < next.startMs)) next = g
  }
  if (live) return { status: "live", game: live }
  // Postgame window: keep the final on the pill while it is fresher than the
  // wait to the next game (capped at 8 hours), so a just-finished game reads
  // W/L instead of instantly flipping to tomorrow's countdown.
  if (lastFinal) {
    var age = nowMs - lastFinal.startMs
    var freshMs = 8 * 3600000
    if (age < freshMs && (!next || age < next.startMs - nowMs))
      return { status: "final", game: lastFinal }
  }
  if (next) return { status: "next", game: next, msUntil: next.startMs - nowMs }
  return { status: "off" }
}

// Compact countdown: keeps the two most significant units so the pill stays
// narrow. "2d 4h" -> "1h 05m" -> "14m" -> "now".
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

// GUMBO /game/<pk>/feed/live -> the live-view model. Malformed input
// returns { valid: false } so the panel keeps last-good state.
function parseGumbo(raw) {
  var invalid = { valid: false }
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return invalid }
  if (!data || !data.liveData || !data.gameData) return invalid
  var ls = data.liveData.linescore || {}
  var plays = data.liveData.plays || {}
  var cp = plays.currentPlay || {}
  var count = cp.count || {}
  var offense = ls.offense || {}
  var teams = data.gameData.teams || {}
  var lsTeams = ls.teams || {}

  var innings = []
  var rawInnings = ls.innings || []
  for (var i = 0; i < rawInnings.length; i++) {
    var inn = rawInnings[i]
    innings.push({
      n: inn.num || (i + 1),
      away: inn.away && inn.away.runs !== undefined && inn.away.runs !== null ? inn.away.runs : -1,
      home: inn.home && inn.home.runs !== undefined && inn.home.runs !== null ? inn.home.runs : -1
    })
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
    inning: num(ls.currentInning),
    inningOrdinal: clean(ls.currentInningOrdinal, 6),
    inningState: clean(ls.inningState, 10),
    isTop: ls.isTopInning === true,
    balls: num(count.balls !== undefined ? count.balls : ls.balls),
    strikes: num(count.strikes !== undefined ? count.strikes : ls.strikes),
    outs: num(count.outs !== undefined ? count.outs : ls.outs),
    bases: {
      first: !!offense.first,
      second: !!offense.second,
      third: !!offense.third
    },
    batter: clean(cp.matchup && cp.matchup.batter ? cp.matchup.batter.fullName : "", 32),
    pitcher: clean(cp.matchup && cp.matchup.pitcher ? cp.matchup.pitcher.fullName : "", 32),
    lastPlay: lastPlay,
    innings: innings
  }
}

function num(v) {
  var n = Number(v)
  return isNaN(n) ? 0 : n
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
// "Middle"/"End"; both display as the side about to bat, marked with a dot.
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
//   next              : "ATL @ CWS 1h 05m"
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
        + gumbo.balls + "-" + gumbo.strikes + ", " + gumbo.outs + " out"
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
// { division, rows: [{rank, name, wins, losses, gb, streak}] }.
function parseStandings(raw, myTeamId) {
  var empty = { division: "", rows: [] }
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return empty }
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
        id: tr.team ? tr.team.id : 0,
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
function recapCacheKey(state, myTeamId) {
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
    var wl = s.mine.score > s.theirs.score ? "beat" : "lost to"
    lines.push("Last game: " + wl + " " + s.theirs.name + " " + s.mine.score + "-" + s.theirs.score)
  }
  if (games) {
    for (var j = 0; j < games.length; j++) {
      var g = games[j]
      if (g.state === "pre" && g.startMs > nowMs) {
        var opp = g.isHome ? g.away : g.home
        var hrs = Math.round((g.startMs - nowMs) / 3600000)
        lines.push("Next game: " + (g.isHome ? "home vs " : "away at ") + opp.name
          + " in about " + hrs + " hours")
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

// Request body for POST {base}/chat/completions. Kept small and cheap: one
// short completion per game-state change.
function recapRequestBody(model, context) {
  return JSON.stringify({
    model: String(model || ""),
    max_tokens: 220,
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

// choices[0].message.content, sanitized and capped. Anything malformed
// returns "" and the panel simply shows no recap section.
function parseRecap(raw) {
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return "" }
  var c = data && data.choices && data.choices[0]
  var content = c && c.message ? c.message.content : ""
  return clean(content, 600)
}

if (typeof module !== "undefined") {
  module.exports = {
    TEAMS: TEAMS,
    DIVISIONS: DIVISIONS,
    teamAbbrs: teamAbbrs,
    teamId: teamId,
    teamDivision: teamDivision,
    clean: clean,
    parseSchedule: parseSchedule,
    currentOrNext: currentOrNext,
    countdown: countdown,
    parseGumbo: parseGumbo,
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
