const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")

const root = path.join(__dirname, "..")
const read = name => fs.readFileSync(path.join(root, name), "utf8")

test("marketplace copy uses all 500 characters for the shipped baseball story", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(manifest.description.length, 500)
  assert.equal(manifest.barWidget.description.length, 500)
  assert.equal(manifest.description, manifest.barWidget.description)
  for (const claim of [
    "first-pitch countdowns", "score and inning, count, outs, bases, and last play",
    "local schedule, division race, and line score", "keyless MLB Stats API",
    "every 15 minutes", "Gameday every 20 seconds", "selected club and public game data",
    "not an account or identifying data", "recaps are off by default", "post nothing"
  ]) assert.match(manifest.description, new RegExp(claim))
})

test("banner names and illustrates MLB Booth rather than a generic widget", () => {
  const banner = read("assets/banner.svg")
  assert.match(banner, /MLB BOOTH/)
  assert.match(banner, /ATL 1-0/)
  assert.match(banner, /line score|LINE SCORE/i)
  assert.match(banner, /<(?:path|circle|radialGradient)\b/)
})

test("render tooling requires exact 1280x720 provenance and approval", () => {
  const render = read("scripts/rig-render.sh")
  assert.match(render, /OMARCHY_RIG_RESOLUTION:-1280x720/)
  assert.match(render, /e2e\/bin/)
  assert.match(render, /export PATH=.*e2e\/bin/)
  assert.match(render, /rawShellLogSha256/)
  assert.match(render, /visualInspection:\{status:"pending"/)
  assert.match(render, /rig-after-open\.sh/)
  assert.match(read("scripts/approve-preview.sh"), /product value is visible without reading the README/)
  const afterOpen = read("e2e/rig-after-open.sh")
  assert.match(afterOpen, /ipc call "\$MOD" settings/)
  assert.match(afterOpen, /schedule standings gumbo/)
  assert.match(afterOpen, /while \[ "\$attempt" -lt 12 \]/)
  assert.ok(fs.statSync(path.join(root, "e2e/rig-after-open.sh")).mode & 0o111, "rig-after-open.sh must be executable")
})

test("render fixture tells the complete live baseball story without network access", () => {
  const fixtureCurl = path.join(root, "e2e/bin/curl")
  assert.ok(fs.statSync(fixtureCurl).mode & 0o111, "fixture curl must be executable")

  const env = { ...process.env, XDG_RUNTIME_DIR: process.env.TMPDIR || "/tmp" }
  const run = url => execFileSync(fixtureCurl, ["-fsS", "--", url], { env, encoding: "utf8" })
  const schedule = JSON.parse(run("https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId=144"))
  const standings = JSON.parse(run("https://statsapi.mlb.com/api/v1/standings?leagueId=103,104"))
  const gumbo = JSON.parse(run("https://statsapi.mlb.com/api/v1.1/game/824589/feed/live"))

  assert.equal(schedule.dates[0].games[0].status.abstractGameState, "Live")
  assert.ok(schedule.dates.length >= 4, "live game and upcoming schedule must render")
  assert.equal(standings.records[0].teamRecords.length, 5)
  assert.equal(gumbo.liveData.linescore.currentInning, 7)
  assert.equal(gumbo.liveData.plays.currentPlay.count.strikes, 2)
  assert.match(gumbo.liveData.plays.allPlays[0].result.description, /scoring/)
  const captureGuard = read("e2e/rig-before-capture.sh")
  assert.match(captureGuard, /schedule standings/)
  assert.match(captureGuard, /while \[ "\$attempt" -lt 12 \]/)
  assert.match(captureGuard, /exit 1/)

  assert.throws(() => run("https://example.com/not-the-mlb-api"), /Command failed/)
})

test("tracked source contains no unresolved merge-conflict markers", () => {
  const files = execFileSync("git", ["ls-files", "-z"], { cwd: root })
    .toString().split("\0").filter(Boolean)
  for (const file of files) {
    const absolute = path.join(root, file)
    if (!fs.existsSync(absolute)) continue
    const body = fs.readFileSync(absolute)
    if (body.includes(0)) continue
    assert.doesNotMatch(body.toString("utf8"), /^(?:<{7}|={7}|>{7})(?: |$)/m, file)
  }
})

test("a live schedule response starts the first GUMBO fetch immediately", () => {
  const panel = read("Panel.qml")
  assert.match(panel, /root\.games = parsed[\s\S]*root\.scheduleLoaded = true[\s\S]*Qt\.callLater\(root\.liveTick\)/)
})

test("CI pins actions and runs every local quality gate", () => {
  const workflow = read(".github/workflows/test.yml")
  assert.doesNotMatch(workflow, /uses:\s+[^\s]+@v\d+/)
  for (const command of ["npm ci", "npm run audit:deps", "npm test", "npm run test:race", "npm run test:mutation", "npm run audit", "shellcheck"])
    assert.match(workflow, new RegExp(command.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.match(workflow, /e2e\/bin\/\*/)
})

test("a stopped schedule fetch restarts from onExited, never from a running guess", () => {
  const panel = read("Panel.qml")
  // The restart used to be Qt.callLater guarded by `!scheduleProc.running`. A
  // stopped process is still running until it has exited, so on a real network
  // the guard was false and the restart was skipped: no schedule on first run.
  const refresh = panel.slice(panel.indexOf("function refresh()"), panel.indexOf("function liveTick"))
  assert.match(refresh, /root\.scheduleRestartPending = true\s*\n\s*scheduleProc\.running = false/)
  assert.doesNotMatch(refresh, /Qt\.callLater/)
  assert.match(panel, /id: scheduleProc\s*\n\s*onExited: function \(code\) \{[\s\S]*?root\.scheduleRestartPending = false[\s\S]*?scheduleProc\.running = true/)
})
