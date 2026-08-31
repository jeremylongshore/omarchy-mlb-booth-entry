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
  for (const claim of ["first-pitch countdown", "count, outs, bases", "local-time schedule", "division race", "every 15 minutes", "every 20 seconds", "off by default", "no league account"]) assert.match(manifest.description, new RegExp(claim))
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
  assert.match(read("scripts/approve-preview.sh"), /product value is visible without reading the README/)
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
  assert.match(read("e2e/rig-before-capture.sh"), /schedule standings gumbo/)

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

test("CI pins actions and runs every local quality gate", () => {
  const workflow = read(".github/workflows/test.yml")
  assert.doesNotMatch(workflow, /uses:\s+[^\s]+@v\d+/)
  for (const command of ["npm ci", "npm run audit:deps", "npm test", "npm run test:race", "npm run test:mutation", "npm run audit", "shellcheck"])
    assert.match(workflow, new RegExp(command.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")))
  assert.match(workflow, /e2e\/bin\/\*/)
})
