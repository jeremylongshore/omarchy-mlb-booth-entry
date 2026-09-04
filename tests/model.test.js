const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const Model = require("../Model.js")

// Fixtures are real MLB Stats API bodies captured 2026-08-20 during a live
// ATL @ CWS game (gamePk 824589, top 4th). Tests run against captured
// bodies, never the network.
const fixture = (name) =>
  fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")

const scheduleRaw = fixture("statsapi-schedule.json")
const gumboRaw = fixture("statsapi-gumbo-live.json")
const standingsRaw = fixture("statsapi-standings.json")

const ATL = Model.teamId("ATL")

// The capture moment, mid-game: 2026-08-20 ~19:15Z.
const DURING_GAME_MS = Date.parse("2026-08-20T19:15:00Z")

// ---- clean ----

test("clean strips angle brackets so AutoText can never promote to StyledText", () => {
  assert.equal(Model.clean('<img src="http://x/y.png">Acuna'), 'img src="http://x/y.png"Acuna')
})

test("clean strips control characters and caps length", () => {
  assert.equal(Model.clean("a\x00b\x1fc\x7fd"), "abcd")
  assert.equal(Model.clean("x".repeat(500), 64).length, 64)
})

test("clean tolerates null and undefined", () => {
  assert.equal(Model.clean(null), "")
  assert.equal(Model.clean(undefined), "")
})

// ---- team table ----

test("all 30 clubs are present with unique ids", () => {
  const abbrs = Model.teamAbbrs()
  assert.equal(abbrs.length, 30)
  const ids = new Set(abbrs.map(Model.teamId))
  assert.equal(ids.size, 30)
})

test("teamId resolves case-insensitively and unknown maps to 0", () => {
  assert.equal(Model.teamId("atl"), 144)
  assert.equal(Model.teamId("XYZ"), 0)
})

// ---- parseSchedule ----

test("parseSchedule reads every game ordered by start time", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  assert.equal(games.length, 8)
  const starts = games.map((g) => g.startMs)
  assert.deepEqual(starts, [...starts].sort((a, b) => a - b))
})

test("parseSchedule maps states and hydrated scores", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const final = games.find((g) => g.gamePk === 823664)
  assert.equal(final.state, "final")
  assert.equal(final.away.abbr, "ATL")
  assert.equal(final.away.score, 4)
  assert.equal(final.home.score, 6)
  assert.equal(final.isHome, false)
  const live = games.find((g) => g.gamePk === 824589)
  assert.equal(live.state, "live")
  assert.equal(games.filter((g) => g.state === "pre").length, 6)
})

test("scheduleBelongsToTeam rejects another club's stale payload", () => {
  const pit = Model.teamId("PIT")
  const atl = Model.teamId("ATL")
  const games = Model.parseSchedule(scheduleRaw, atl)
  assert.equal(Model.scheduleBelongsToTeam(games, atl), true)
  assert.equal(Model.scheduleBelongsToTeam(games, pit), false)
  assert.equal(Model.scheduleBelongsToTeam([], pit), true)
  assert.equal(Model.scheduleBelongsToTeam(null, pit), false)
})

test("parseSchedule returns [] on malformed input, keeping last-good state", () => {
  assert.deepEqual(Model.parseSchedule("not json", ATL), [])
  assert.deepEqual(Model.parseSchedule("", ATL), [])
  assert.deepEqual(Model.parseSchedule("{}", ATL), [])
})

// ---- currentOrNext ----

test("currentOrNext finds the live game during its window", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const state = Model.currentOrNext(games, DURING_GAME_MS)
  assert.equal(state.status, "live")
  assert.equal(state.game.gamePk, 824589)
})

test("currentOrNext counts down to the next game when nothing is live", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL).map((g) =>
    g.state === "live" ? { ...g, state: "final" } : g)
  // 20 hours after the (now final) game: past the postgame window relative
  // to the next day's game.
  const later = DURING_GAME_MS + 20 * 3600000
  const state = Model.currentOrNext(games, later)
  assert.equal(state.status, "next")
  assert.ok(state.msUntil > 0)
})

test("currentOrNext holds a fresh final in the postgame window", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL).map((g) =>
    g.state === "live" ? { ...g, state: "final" } : g)
  const justAfter = DURING_GAME_MS + 3600000
  const state = Model.currentOrNext(games, justAfter)
  assert.equal(state.status, "final")
  assert.equal(state.game.gamePk, 824589)
})

test("currentOrNext is off when the window holds no games", () => {
  assert.deepEqual(Model.currentOrNext([], DURING_GAME_MS), { status: "off" })
})

// ---- parseGumbo ----

test("parseGumbo reads score, inning, count, and matchup from the live feed", () => {
  const g = Model.parseGumbo(gumboRaw)
  assert.equal(g.valid, true)
  assert.equal(g.awayAbbr, "ATL")
  assert.equal(g.homeAbbr, "CWS")
  assert.equal(g.awayRuns, 1)
  assert.equal(g.homeRuns, 0)
  assert.equal(g.inning, 4)
  assert.equal(g.inningState, "Top")
  assert.equal(g.isTop, true)
  assert.equal(g.balls, 2)
  assert.equal(g.strikes, 2)
  assert.equal(g.outs, 0)
  assert.equal(g.batter, "Matt Olson")
  assert.equal(g.pitcher, "Anthony Kay")
})

test("parseGumbo reads base state", () => {
  const g = Model.parseGumbo(gumboRaw)
  assert.deepEqual(g.bases, { first: false, second: false, third: false })
})

test("parseGumbo surfaces the last completed play, not the in-progress at-bat", () => {
  const g = Model.parseGumbo(gumboRaw)
  assert.match(g.lastPlay, /grounds out/)
})

test("parseGumbo maps innings: batting half is a 0 in progress, unreached half stays -1", () => {
  const g = Model.parseGumbo(gumboRaw)
  assert.equal(g.innings.length, 4)
  assert.deepEqual(g.innings[2], { n: 3, away: 1, home: 0 })
  // Capture moment is Top 4: ATL batting (0 so far), CWS half not reached.
  assert.equal(g.innings[3].away, 0)
  assert.equal(g.innings[3].home, -1)
})

test("parseGumbo rejects malformed input", () => {
  assert.equal(Model.parseGumbo("not json").valid, false)
  assert.equal(Model.parseGumbo("{}").valid, false)
})

// ---- display helpers ----

test("basesText covers empty, singles, pairs, and loaded", () => {
  assert.equal(Model.basesText({ first: false, second: false, third: false }), "Empty")
  assert.equal(Model.basesText({ first: true, second: false, third: false }), "1st")
  assert.equal(Model.basesText({ first: true, second: false, third: true }), "1st & 3rd")
  assert.equal(Model.basesText({ first: true, second: true, third: true }), "Bases loaded")
})

test("countText resets a completed at-bat's count to 0-0, broadcast style", () => {
  assert.equal(Model.countText(2, 2), "2-2")
  assert.equal(Model.countText(3, 3), "0-0")
  assert.equal(Model.countText(4, 2), "0-0")
  assert.equal(Model.countText(0, 0), "0-0")
})

test("inningTag renders half-inning states", () => {
  assert.equal(Model.inningTag(Model.parseGumbo(gumboRaw)), "T4")
  assert.equal(Model.inningTag({ inning: 7, inningState: "Bottom" }), "B7")
  assert.equal(Model.inningTag({ inning: 5, inningState: "Middle" }), "M5")
})

test("countdown keeps the two most significant units and zero-pads minutes", () => {
  assert.equal(Model.countdown(2 * 86400000 + 4 * 3600000), "2d 4h")
  assert.equal(Model.countdown(65 * 60000), "1h 05m")
  assert.equal(Model.countdown(9 * 60000), "09m")
  assert.equal(Model.countdown(10000), "now")
})

// ---- pillText ----

test("pillText live with GUMBO carries score, half inning, count, and outs", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const state = Model.currentOrNext(games, DURING_GAME_MS)
  const g = Model.parseGumbo(gumboRaw)
  assert.equal(Model.pillText(state, ATL, g), "ATL 1-0 · T4 · 2-2, 0 out")
})

test("pillText live before the first GUMBO poll shows the schedule score", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const state = Model.currentOrNext(games, DURING_GAME_MS)
  assert.equal(Model.pillText(state, ATL, { valid: false }), "ATL 1-0 · LIVE")
})

test("pillText final reads win-loss with the team's score first", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const finalState = { status: "final", game: games.find((g) => g.gamePk === 823664) }
  assert.equal(Model.pillText(finalState, ATL, null), "ATL L 4-6")
})

test("pillText next carries the matchup and countdown", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const next = games.find((g) => g.state === "pre")
  const state = { status: "next", game: next, msUntil: 65 * 60000 }
  const pill = Model.pillText(state, ATL, null)
  assert.match(pill, /^ATL (@|vs) [A-Z]{2,3} 1h 05m$/)
})

test("pillText off is empty so the slot collapses", () => {
  assert.equal(Model.pillText({ status: "off" }, ATL, null), "")
  assert.equal(Model.pillText(null, ATL, null), "")
})

// ---- parseStandings ----

test("parseStandings finds the team's division with ranked rows", () => {
  const s = Model.parseStandings(standingsRaw, ATL)
  assert.equal(s.division, "NL East")
  assert.equal(s.rows.length, 5)
  assert.equal(s.rows[0].name, "Braves")
  assert.equal(s.rows[0].wins, 74)
  assert.equal(s.rows[0].gb, "-")
  assert.equal(s.rows[1].name, "Phillies")
  assert.equal(s.rows[1].gb, "4.5")
})

test("parseStandings returns the empty shape on malformed input", () => {
  assert.deepEqual(Model.parseStandings("not json", ATL), { division: "", rows: [] })
  assert.deepEqual(Model.parseStandings("{}", ATL), { division: "", rows: [] })
})

// ---- BYOK recap ----

test("recapCacheKey changes per game, not per refresh", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const finalState = { status: "final", game: games.find((g) => g.gamePk === 823664) }
  assert.equal(Model.recapCacheKey(finalState), "final:823664")
  assert.equal(Model.recapCacheKey({ status: "live", game: games[0] }), "live")
  assert.equal(Model.recapCacheKey({ status: "off" }), "off")
})

test("recapContext states record, last result, and next game as plain facts", () => {
  const games = Model.parseSchedule(scheduleRaw, ATL)
  const finalState = { status: "final", game: games.find((g) => g.gamePk === 823664) }
  const standings = Model.parseStandings(standingsRaw, ATL)
  const ctx = Model.recapContext("ATL", finalState, standings, games, DURING_GAME_MS)
  assert.match(ctx, /Atlanta Braves/)
  assert.match(ctx, /74-53, 1st in the NL East/)
  assert.match(ctx, /lost to Twins 4-6/)
  assert.match(ctx, /Next game:/)
})

test("recapRequestBody is valid JSON with bounded output and the facts inline", () => {
  const body = JSON.parse(Model.recapRequestBody("gpt-4o-mini", "Team: Atlanta Braves"))
  assert.equal(body.model, "gpt-4o-mini")
  // Bounded, with headroom for reasoning models that think before answering
  // (proven live: 220 starved one into finish_reason "length", empty content).
  assert.ok(body.max_tokens >= 500 && body.max_tokens <= 1000)
  assert.equal(body.messages.length, 2)
  assert.match(body.messages[1].content, /Atlanta Braves/)
})

test("parseRecap joins typed content-part arrays some servers return", () => {
  const raw = JSON.stringify({
    choices: [{ message: { content: [{ type: "text", text: "First." }, { type: "text", text: "Second." }] } }]
  })
  assert.equal(Model.parseRecap(raw), "First. Second.")
})

test("parseRecap extracts the completion and sanitizes it", () => {
  const raw = JSON.stringify({
    choices: [{ message: { content: "The Braves <b>lead</b> the East." } }]
  })
  assert.equal(Model.parseRecap(raw), "The Braves blead/b the East.")
})

test("parseRecap returns empty string on malformed input", () => {
  assert.equal(Model.parseRecap("not json"), "")
  assert.equal(Model.parseRecap("{}"), "")
})

// ---- Status shapes statsapi rarely serves: synthesized from the documented
//      status codes, because no capture window reliably contains them.

const mkGame = (over) => Object.assign({
  gamePk: 900001,
  startMs: DURING_GAME_MS - 3600000,
  state: "pre",
  detail: "Scheduled",
  home: { id: 145, abbr: "CWS", name: "White Sox", score: -1 },
  away: { id: 144, abbr: "ATL", name: "Braves", score: -1 },
  isHome: false
}, over)

test("a postponed game is its own state and never a phantom 0-0 final", () => {
  const raw = JSON.stringify({ dates: [{ games: [{
    gamePk: 900002, gameDate: "2026-08-20T18:10:00Z",
    status: { abstractGameState: "Final", detailedState: "Postponed" },
    teams: {
      home: { team: { id: 145, abbreviation: "CWS", teamName: "White Sox" } },
      away: { team: { id: 144, abbreviation: "ATL", teamName: "Braves" } }
    }
  }] }] })
  const games = Model.parseSchedule(raw, ATL)
  assert.equal(games[0].state, "postponed")
  // Alone in the window it yields off, not "ATL T 0-0".
  assert.deepEqual(Model.currentOrNext(games, DURING_GAME_MS), { status: "off" })
})

test("a postponed game cannot shadow a real final in the postgame window", () => {
  const real = mkGame({ gamePk: 900003, startMs: DURING_GAME_MS - 5 * 3600000, state: "final",
    home: { id: 145, abbr: "CWS", name: "White Sox", score: 6 },
    away: { id: 144, abbr: "ATL", name: "Braves", score: 4 } })
  const post = mkGame({ gamePk: 900004, startMs: DURING_GAME_MS - 3600000, state: "postponed" })
  const state = Model.currentOrNext([real, post], DURING_GAME_MS)
  assert.equal(state.status, "final")
  assert.equal(state.game.gamePk, 900003)
})

test("a suspended game maps to postponed, not to a wedged live state", () => {
  const raw = JSON.stringify({ dates: [{ games: [{
    gamePk: 900005, gameDate: "2026-08-20T18:10:00Z",
    status: { abstractGameState: "Live", detailedState: "Suspended: Rain" },
    teams: {
      home: { team: { id: 145, abbreviation: "CWS", teamName: "White Sox" } },
      away: { team: { id: 144, abbreviation: "ATL", teamName: "Braves" } }
    }
  }] }] })
  const games = Model.parseSchedule(raw, ATL)
  assert.equal(games[0].state, "postponed")
  assert.notEqual(Model.currentOrNext(games, DURING_GAME_MS).status, "live")
})

test("a delayed start holds the pill: still Preview past first pitch stays next", () => {
  const delayed = mkGame({ detail: "Delayed Start: Rain", startMs: DURING_GAME_MS - 80 * 60000 })
  const state = Model.currentOrNext([delayed], DURING_GAME_MS)
  assert.equal(state.status, "next")
  assert.ok(state.msUntil < 0)
  // The pill renders "now" rather than a negative countdown.
  assert.equal(Model.pillText(state, ATL, null), "ATL @ CWS now")
})

test("split doubleheader: game 1's result holds the pill until game 2 is closer", () => {
  const g1 = mkGame({ gamePk: 900006, startMs: DURING_GAME_MS - 3.5 * 3600000, state: "final",
    home: { id: 145, abbr: "CWS", name: "White Sox", score: 2 },
    away: { id: 144, abbr: "ATL", name: "Braves", score: 5 } })
  const g2 = mkGame({ gamePk: 900007, startMs: DURING_GAME_MS + 2.5 * 3600000 })
  // Just after game 1's final out (start + ~3.25h): age is ~0, game 2 is
  // 2.5h away. The old first-pitch-age math skipped the result entirely.
  const state = Model.currentOrNext([g1, g2], DURING_GAME_MS)
  assert.equal(state.status, "final")
  assert.equal(state.game.gamePk, 900006)
  assert.equal(Model.pillText(state, ATL, null), "ATL W 5-2")
})

test("pillText renders vs for a home game and @ for a road game", () => {
  const road = { status: "next", game: mkGame({}), msUntil: 65 * 60000 }
  assert.equal(Model.pillText(road, ATL, null), "ATL @ CWS 1h 05m")
  const home = { status: "next", game: mkGame({ isHome: true,
    home: { id: 144, abbr: "ATL", name: "Braves", score: -1 },
    away: { id: 145, abbr: "CWS", name: "White Sox", score: -1 } }), msUntil: 65 * 60000 }
  assert.equal(Model.pillText(home, ATL, null), "ATL vs CWS 1h 05m")
})

test("recapContext reports a tie as tied, never as a loss", () => {
  const tied = { status: "final", game: mkGame({ state: "final",
    home: { id: 145, abbr: "CWS", name: "White Sox", score: 3 },
    away: { id: 144, abbr: "ATL", name: "Braves", score: 3 } }) }
  const ctx = Model.recapContext("ATL", tied, { division: "", rows: [] }, [], DURING_GAME_MS)
  assert.match(ctx, /tied White Sox 3-3/)
})

test("parseGumbo caps a hostile innings list at 30", () => {
  const innings = []
  for (let i = 0; i < 5000; i++) innings.push({ num: i + 1, away: { runs: 0 }, home: { runs: 0 } })
  const raw = JSON.stringify({
    gameData: { status: { abstractGameState: "Live" }, teams: {} },
    liveData: { linescore: { innings }, plays: {} }
  })
  assert.equal(Model.parseGumbo(raw).innings.length, 30)
})

test("parseGumbo blanks the matchup at the end-of-at-bat boundary", () => {
  const raw = JSON.stringify({
    gameData: { status: { abstractGameState: "Live" }, teams: {} },
    liveData: {
      linescore: { currentInning: 5, inningState: "Top" },
      plays: { currentPlay: {
        about: { isComplete: true },
        count: { balls: 3, strikes: 3, outs: 1 },
        matchup: { batter: { fullName: "Gone Batter" }, pitcher: { fullName: "Some Pitcher" } }
      }, allPlays: [] }
    }
  })
  const g = Model.parseGumbo(raw)
  assert.equal(g.batter, "")
  assert.equal(g.pitcher, "")
})

test("emptyGumbo carries every field a binding touches, so nothing is ever undefined", () => {
  const g = Model.emptyGumbo()
  for (const k of ["awayAbbr", "homeAbbr", "inningState", "batter", "pitcher", "lastPlay"])
    assert.equal(typeof g[k], "string")
  for (const k of ["awayRuns", "homeRuns", "awayHits", "homeHits", "awayErrors", "homeErrors", "inning", "balls", "strikes", "outs"])
    assert.equal(typeof g[k], "number")
  assert.deepEqual(g.bases, { first: false, second: false, third: false })
  assert.deepEqual(g.innings, [])
  assert.equal(g.valid, false)
})

test("clean strips bidi overrides and Unicode tag characters", () => {
  assert.equal(Model.clean("safe‮gnp.exe"), "safegnp.exe")
  assert.equal(Model.clean("tag󠁡󠁢ged"), "tagged")
})

test("parsers reject a body past the in-process size bound", () => {
  const huge = '{"dates": []}' + " ".repeat(4000001)
  assert.deepEqual(Model.parseSchedule(huge, ATL), [])
  assert.equal(Model.parseGumbo(huge).valid, false)
})

test("the manifest team picker cannot drift from the team table", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
  const field = manifest.barWidget.schema.find((f) => f.key === "team")
  assert.deepEqual(field.options, Model.teamAbbrs())
})

test("normalizedTeam accepts known clubs and falls back to ATL", () => {
  assert.equal(Model.normalizedTeam("pit"), "PIT")
  assert.equal(Model.normalizedTeam("PIT"), "PIT")
  assert.equal(Model.normalizedTeam("XYZ"), "ATL")
  assert.equal(Model.normalizedTeam(""), "ATL")
  assert.equal(Model.normalizedTeam(null), "ATL")
})

test("teamName returns the club name and blanks unknowns", () => {
  assert.equal(Model.teamName("PIT"), "Pittsburgh Pirates")
  assert.equal(Model.teamName("atl"), "Atlanta Braves")
  assert.equal(Model.teamName("nope"), "")
})

test("normalizedTimeFormat is 12h or 24h", () => {
  assert.equal(Model.normalizedTimeFormat("12h"), "12h")
  assert.equal(Model.normalizedTimeFormat("12H"), "12h")
  assert.equal(Model.normalizedTimeFormat("24h"), "24h")
  assert.equal(Model.normalizedTimeFormat(""), "24h")
  assert.equal(Model.normalizedTimeFormat("nope"), "24h")
})

test("wallClockFormat switches Qt format strings", () => {
  assert.equal(Model.wallClockFormat("24h", "schedule"), "ddd HH:mm")
  assert.equal(Model.wallClockFormat("12h", "schedule"), "ddd h:mm AP")
  assert.equal(Model.wallClockFormat("12h", "tooltip"), "ddd d MMM · h:mm AP")
  assert.equal(Model.wallClockFormat("24h", "tooltip"), "ddd d MMM · HH:mm")
  assert.equal(Model.wallClockFormat("", "schedule"), "ddd HH:mm")
})

test("the manifest timeFormat picker is 12h or 24h defaulting to 24h", () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
  const field = manifest.barWidget.schema.find((f) => f.key === "timeFormat")
  assert.deepEqual(field.options, ["12h", "24h"])
  assert.equal(field.defaultValue, "24h")
})

// --------------------------------------------------------------- club colour

test("clubHue matches on nicknames, never on city names", () => {
  // "angel" matched inside "Los Angeles" and painted the Dodgers red, which is
  // the kind of mistake a baseball fan notices in the first second. Two clubs
  // share a city and a third carries another club's city in its own name, so
  // every pattern is anchored and every one of those cases is pinned here.
  const cases = {
    "St. Louis Cardinals": 0.005,
    "Los Angeles Dodgers": 0.60,
    "Los Angeles Angels": 0.005,
    "New York Yankees": 0.66,
    "New York Mets": 0.07,
    "Chicago Cubs": 0.60,
    "Chicago White Sox": 0.66,
    "Boston Red Sox": 0.005,
    "Cincinnati Reds": 0.005,
    "San Francisco Giants": 0.07,
    "Seattle Mariners": 0.60,
  }
  for (const [name, hue] of Object.entries(cases)) {
    assert.equal(Model.clubHue(name), hue, name)
  }
})

test("clubHue gives an unknown club a stable hue rather than one default", () => {
  const a = Model.clubHue("Nashville Stars")
  assert.ok(a >= 0 && a <= 1)
  assert.equal(a, Model.clubHue("Nashville Stars"))
  assert.notEqual(a, Model.clubHue("Portland Loggers"))
})

// ---- defensive API-shape and display fallbacks ---------------------------

test("team and display helpers handle empty and uncommon values", () => {
  assert.equal(Model.teamId(null), 0)
  assert.equal(Model.basesText(null), "Empty")
  assert.equal(Model.inningTag(null), "")
  assert.equal(Model.inningTag({ inning: 7, inningState: "End" }), "E7")
  assert.equal(Model.inningTag({ inning: 8, inningState: "", isTop: true }), "T8")
  assert.equal(Model.inningTag({ inning: 9, inningState: "", isTop: false }), "B9")
  assert.equal(Model.countdown(10 * 60000), "10m")
  assert.equal(Model.countdown(60 * 60000), "1h 00m")
})

test("parseSchedule tolerates sparse dates, games, statuses, teams, and scores", () => {
  const raw = JSON.stringify({ dates: [
    {},
    { games: [
      { gamePk: "7", gameDate: "bad-date" },
      {
        gamePk: "8",
        gameDate: "2026-08-21T18:00:00Z",
        teams: {
          home: { team: { id: "144", abbreviation: "ATL", name: "Atlanta" }, score: null },
          away: null
        }
      }
    ] }
  ] })
  const games = Model.parseSchedule(raw, ATL)
  assert.equal(games.length, 1)
  assert.equal(games[0].state, "pre")
  assert.equal(games[0].detail, "")
  assert.deepEqual(games[0].home, { id: 144, abbr: "ATL", name: "Atlanta", score: -1 })
  assert.deepEqual(games[0].away, { id: 0, abbr: "", name: "", score: -1 })
  assert.equal(games[0].isHome, true)
})

test("parseGumbo fills a safe model when optional live-feed fields are absent", () => {
  const raw = JSON.stringify({ gameData: {}, liveData: {} })
  const g = Model.parseGumbo(raw)
  assert.equal(g.valid, true)
  assert.equal(g.state, "")
  assert.equal(g.awayAbbr, "")
  assert.equal(g.homeAbbr, "")
  assert.equal(g.inning, 0)
  assert.deepEqual(g.bases, { first: false, second: false, third: false })
  assert.equal(g.batter, "")
  assert.equal(g.pitcher, "")
  assert.deepEqual(g.innings, [])
})

test("parseGumbo maps bottom-half zeroes, fallback counts, and sparse innings", () => {
  const raw = JSON.stringify({
    gameData: { status: { abstractGameState: "Live" }, teams: {
      away: { abbreviation: "ATL" }, home: { abbreviation: "CWS" }
    } },
    liveData: {
      linescore: {
        currentInning: 2,
        currentInningOrdinal: "2nd",
        inningState: "Bottom",
        isTopInning: false,
        balls: 1, strikes: 2, outs: 1,
        offense: { first: {}, third: {} },
        teams: { away: { runs: 2 }, home: { runs: 1, hits: 3, errors: 0 } },
        innings: [{}, { num: 2, away: { runs: 1 }, home: {} }]
      },
      plays: { currentPlay: { matchup: {
        batter: { fullName: "Next Batter" }, pitcher: { fullName: "Pitcher" }
      } }, allPlays: [{ about: { isComplete: true }, result: {} }] }
    }
  })
  const g = Model.parseGumbo(raw)
  assert.equal(g.state, "Live")
  assert.equal(g.innings[0].n, 1)
  assert.deepEqual(g.innings[1], { n: 2, away: 1, home: 0 })
  assert.deepEqual(g.bases, { first: true, second: false, third: true })
  assert.equal(Model.countText(g.balls, g.strikes), "1-2")
  assert.equal(g.batter, "Next Batter")
  assert.equal(g.lastPlay, "")
})

test("pillText prefers home-team GUMBO runs during a live home game", () => {
  const game = mkGame({
    state: "live", isHome: true,
    home: { id: ATL, abbr: "ATL", name: "Braves", score: 0 },
    away: { id: 145, abbr: "CWS", name: "White Sox", score: 0 }
  })
  const gumbo = Object.assign(Model.emptyGumbo(), {
    valid: true, inning: 5, inningState: "Bottom",
    homeRuns: 4, awayRuns: 2, balls: 0, strikes: 1, outs: 2
  })
  assert.equal(Model.pillText({ status: "live", game }, ATL, gumbo), "ATL 4-2 · B5 · 0-1, 2 out")
})

test("parseStandings handles oversized, unknown, unrelated, and sparse divisions", () => {
  assert.deepEqual(Model.parseStandings(" ".repeat(4000001), ATL), { division: "", rows: [] })
  const unrelated = JSON.stringify({ records: [{ teamRecords: [{ team: { id: 1 } }] }] })
  assert.deepEqual(Model.parseStandings(unrelated, ATL), { division: "", rows: [] })

  const sparse = JSON.stringify({ records: [{
    division: { id: 999 },
    teamRecords: [
      { team: { id: ATL } },
      { divisionRank: "1", wins: "2", losses: "3", gamesBack: "0", streak: {} }
    ]
  }] })
  const parsed = Model.parseStandings(sparse, ATL)
  assert.equal(parsed.division, "")
  assert.deepEqual(parsed.rows, [
    { rank: 1, id: 144, name: "", wins: 0, losses: 0, gb: "-", streak: "" },
    { rank: 1, id: 0, name: "", wins: 2, losses: 3, gb: "0", streak: "" }
  ])
})

test("recapContext covers unknown clubs, ordinal ranks, and both venues", () => {
  for (const [rank, suffix] of [[2, "2nd"], [3, "3rd"], [4, "4th"]]) {
    const standings = { division: "NL East", rows: [
      { id: ATL, rank, wins: 70, losses: 50, gb: "1.0", streak: "" }
    ] }
    assert.match(Model.recapContext("ATL", null, standings, [], DURING_GAME_MS), new RegExp(suffix))
  }

  const homeNext = mkGame({ state: "pre", startMs: DURING_GAME_MS + 3600000, isHome: true })
  const roadNext = mkGame({ state: "pre", startMs: DURING_GAME_MS + 7200000, isHome: false })
  assert.match(Model.recapContext("EXP", null, null, [homeNext], DURING_GAME_MS), /Team: EXP/)
  assert.match(Model.recapContext("ATL", null, null, [homeNext], DURING_GAME_MS), /home vs Braves/)
  assert.match(Model.recapContext("ATL", null, null, [roadNext], DURING_GAME_MS), /away at White Sox/)
})

test("recap request and response helpers keep malformed variants inert", () => {
  const body = JSON.parse(Model.recapRequestBody(null, null))
  assert.equal(body.model, "")
  assert.match(body.messages[1].content, /facts:\n$/)
  assert.equal(Model.parseRecap(" ".repeat(4000001)), "")
  assert.equal(Model.parseRecap(JSON.stringify({ choices: [] })), "")
  assert.equal(Model.parseRecap(JSON.stringify({
    choices: [{ message: { content: [null, { type: "image" }, { text: 3 }, { text: "Safe" }] } }]
  })), "Safe")
})

test("clubHue covers every explicit palette family and the empty fallback", () => {
  assert.equal(Model.clubHue("Athletics"), 0.42)
  assert.equal(Model.clubHue("Arizona Diamondbacks"), 0.42)
  assert.equal(Model.clubHue("Colorado Rockies"), 0.42)
  assert.equal(Model.clubHue("Pittsburgh Pirates"), 0.14)
  assert.equal(Model.clubHue("Cleveland Guardians"), 0.14)
  assert.equal(Model.clubHue("Texas Rangers"), 0.14)
  assert.equal(Model.clubHue("Minnesota Twins"), 0.14)
  assert.equal(Model.clubHue(null), 0)
})

test("the shipped club table pins every Stats API id and display name", () => {
  const clubs = {
    ATH: [133, "Athletics"], ATL: [144, "Atlanta Braves"], AZ: [109, "Arizona Diamondbacks"],
    BAL: [110, "Baltimore Orioles"], BOS: [111, "Boston Red Sox"], CHC: [112, "Chicago Cubs"],
    CIN: [113, "Cincinnati Reds"], CLE: [114, "Cleveland Guardians"], COL: [115, "Colorado Rockies"],
    CWS: [145, "Chicago White Sox"], DET: [116, "Detroit Tigers"], HOU: [117, "Houston Astros"],
    KC: [118, "Kansas City Royals"], LAA: [108, "Los Angeles Angels"], LAD: [119, "Los Angeles Dodgers"],
    MIA: [146, "Miami Marlins"], MIL: [158, "Milwaukee Brewers"], MIN: [142, "Minnesota Twins"],
    NYM: [121, "New York Mets"], NYY: [147, "New York Yankees"], PHI: [143, "Philadelphia Phillies"],
    PIT: [134, "Pittsburgh Pirates"], SD: [135, "San Diego Padres"], SEA: [136, "Seattle Mariners"],
    SF: [137, "San Francisco Giants"], STL: [138, "St. Louis Cardinals"], TB: [139, "Tampa Bay Rays"],
    TEX: [140, "Texas Rangers"], TOR: [141, "Toronto Blue Jays"], WSH: [120, "Washington Nationals"]
  }
  assert.deepEqual(Model.teamAbbrs(), Object.keys(clubs).sort())
  for (const [abbr, [id, name]] of Object.entries(clubs)) {
    assert.equal(Model.teamId(abbr), id, `${abbr} id`)
    assert.equal(Model.recapContext(abbr, null, null, [], DURING_GAME_MS), `Team: ${name}`, `${abbr} name`)
  }
})

test("all six Stats API division ids map to their baseball names", () => {
  const divisions = {
    200: "AL West", 201: "AL East", 202: "AL Central",
    203: "NL West", 204: "NL East", 205: "NL Central"
  }
  for (const [id, name] of Object.entries(divisions)) {
    const raw = JSON.stringify({ records: [{ division: { id: Number(id) }, teamRecords: [
      { divisionRank: "1", team: { id: ATL, name: "Atlanta Braves" }, wins: 1, losses: 0 }
    ] }] })
    assert.equal(Model.parseStandings(raw, ATL).division, name)
  }
})

test("clean honors exact caps and leaves already-bounded text unchanged", () => {
  assert.equal(Model.clean("abcd", 3), "abc")
  assert.equal(Model.clean("abc", 3), "abc")
  assert.equal(Model.clean("abc", 4), "abc")
  assert.equal(Model.clean("x".repeat(65)).length, 64)
})

test("emptyGumbo's complete value contract is exact", () => {
  assert.deepEqual(Model.emptyGumbo(), {
    valid: false, state: "", awayAbbr: "", homeAbbr: "",
    awayRuns: 0, homeRuns: 0, awayHits: 0, homeHits: 0,
    awayErrors: 0, homeErrors: 0, inning: 0, inningOrdinal: "",
    inningState: "", isTop: false, balls: 0, strikes: 0, outs: 0,
    bases: { first: false, second: false, third: false },
    batter: "", pitcher: "", lastPlay: "", innings: []
  })
})

test("currentOrNext filters invalid states and selects by time, not array order", () => {
  const oldFinal = mkGame({ gamePk: 1, state: "final", startMs: DURING_GAME_MS - 5 * 3600000,
    home: { id: 145, score: 1 }, away: { id: ATL, score: 2 } })
  const newFinal = mkGame({ gamePk: 2, state: "final", startMs: DURING_GAME_MS - 4 * 3600000,
    home: { id: 145, score: 3 }, away: { id: ATL, score: 4 } })
  const invalidFinal = mkGame({ gamePk: 3, state: "final", startMs: DURING_GAME_MS - 3 * 3600000,
    home: { id: 145, score: -1 }, away: { id: ATL, score: -1 } })
  const laterNext = mkGame({ gamePk: 4, state: "pre", startMs: DURING_GAME_MS + 4 * 3600000 })
  const soonerNext = mkGame({ gamePk: 5, state: "pre", startMs: DURING_GAME_MS + 3 * 3600000 })
  const stalePreview = mkGame({ gamePk: 6, state: "pre", startMs: DURING_GAME_MS - 7 * 3600000 })
  const state = Model.currentOrNext(
    [newFinal, invalidFinal, laterNext, oldFinal, stalePreview, soonerNext], DURING_GAME_MS)
  assert.equal(state.status, "final")
  assert.equal(state.game.gamePk, 2)

  const noFinal = Model.currentOrNext([laterNext, stalePreview, soonerNext], DURING_GAME_MS)
  assert.equal(noFinal.status, "next")
  assert.equal(noFinal.game.gamePk, 5)
})

test("currentOrNext expires old finals and yields to a closer first pitch", () => {
  const expired = mkGame({ state: "final", startMs: DURING_GAME_MS - 12 * 3600000,
    home: { id: 145, score: 1 }, away: { id: ATL, score: 2 } })
  assert.deepEqual(Model.currentOrNext([expired], DURING_GAME_MS), { status: "off" })

  const fresh = mkGame({ state: "final", startMs: DURING_GAME_MS - 4 * 3600000,
    home: { id: 145, score: 1 }, away: { id: ATL, score: 2 } })
  const close = mkGame({ state: "pre", startMs: DURING_GAME_MS + 15 * 60000 })
  const state = Model.currentOrNext([fresh, close], DURING_GAME_MS)
  assert.equal(state.status, "next")
  assert.equal(state.game, close)
})

test("GUMBO uses current-play counts and only completed described plays", () => {
  const raw = JSON.stringify({
    gameData: { status: {}, teams: {} },
    liveData: {
      linescore: {
        currentInning: 1, inningState: "Top", isTopInning: true,
        balls: 3, strikes: 2, outs: 2,
        innings: [{ num: 1, away: {}, home: {} }]
      },
      plays: {
        currentPlay: { count: { balls: 1, strikes: 0, outs: 1 }, matchup: {} },
        allPlays: [
          { about: { isComplete: true }, result: { description: "First complete play" } },
          { about: { isComplete: false }, result: { description: "Incomplete play" } },
          { about: { isComplete: true }, result: {} }
        ]
      }
    }
  })
  const g = Model.parseGumbo(raw)
  assert.equal(g.isTop, true)
  assert.deepEqual([g.balls, g.strikes, g.outs], [1, 0, 1])
  assert.deepEqual(g.innings[0], { n: 1, away: 0, home: -1 })
  assert.equal(g.lastPlay, "First complete play")
})

test("malformed GUMBO top-level shapes return the exact inert model", () => {
  const empty = Model.emptyGumbo()
  assert.deepEqual(Model.parseGumbo(JSON.stringify({ liveData: {} })), empty)
  assert.deepEqual(Model.parseGumbo(JSON.stringify({ gameData: {} })), empty)
  assert.deepEqual(Model.parseGumbo(""), empty)
})

test("standings sort numerically and preserve exact optional row fields", () => {
  const raw = JSON.stringify({ records: [{ division: { id: 204 }, teamRecords: [
    { divisionRank: "2", team: { id: 1, name: "Second" }, wins: "8", losses: "7", gamesBack: "1.5",
      streak: { streakCode: "W2" } },
    { divisionRank: "1", team: { id: ATL, name: "First" }, wins: "9", losses: "6", gamesBack: "-",
      streak: { streakCode: "L1" } }
  ] }] })
  assert.deepEqual(Model.parseStandings(raw, ATL), { division: "NL East", rows: [
    { rank: 1, id: ATL, name: "First", wins: 9, losses: 6, gb: "-", streak: "L1" },
    { rank: 2, id: 1, name: "Second", wins: 8, losses: 7, gb: "1.5", streak: "W2" }
  ] })
})

test("recapContext emits one exact, bounded fact block", () => {
  const state = { status: "final", game: mkGame({ state: "final",
    home: { id: 145, abbr: "CWS", name: "White Sox", score: 2 },
    away: { id: ATL, abbr: "ATL", name: "Braves", score: 5 } }) }
  const standings = { division: "NL East", rows: [
    { id: 999, rank: 1, wins: 80, losses: 40, gb: "-", streak: "W5" },
    { id: ATL, rank: 2, wins: 74, losses: 53, gb: "4.5", streak: "W2" }
  ] }
  const past = mkGame({ state: "pre", startMs: DURING_GAME_MS - 1000 })
  const irrelevant = mkGame({ state: "final", startMs: DURING_GAME_MS + 1000 })
  const next = mkGame({ state: "pre", startMs: DURING_GAME_MS + 65 * 60000, isHome: false })
  assert.equal(Model.recapContext("ATL", state, standings, [past, irrelevant, next], DURING_GAME_MS),
    "Team: Atlanta Braves\nRecord: 74-53, 2nd in the NL East, 4.5 GB, streak W2\n" +
    "Last game: beat White Sox 5-2\nNext game: away at White Sox in 1h 05m")
})

test("recapRequestBody pins the two-message safety prompt", () => {
  assert.deepEqual(JSON.parse(Model.recapRequestBody("local-model", "facts")), {
    model: "local-model", max_tokens: 700, temperature: 0.7,
    messages: [
      {
        role: "system",
        content: "You write two or three tight sentences of baseball color for a desktop widget. " +
          "Plain language, no hype words, no emoji, no hashtags, no em dashes. " +
          "Use only the facts provided. Do not invent scores, players, or dates."
      },
      { role: "user", content: "Write tonight's storyline from these facts:\nfacts" }
    ]
  })
})
