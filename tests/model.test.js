const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const Model = require("../Model.js")

// TEMPLATE: capture real API responses into tests/fixtures/ and load them
// here. Tests run against captured bodies, never the network.
const fixture = (name) =>
  fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")

test("clean strips angle brackets so AutoText can never promote to StyledText", () => {
  assert.equal(Model.clean('<img src="http://x/y.png">Bo'), 'img src="http://x/y.png"Bo')
})

test("clean strips control characters", () => {
  assert.equal(Model.clean("a\x00b\x1fc\x7fd"), "abcd")
})

test("clean caps pathological length", () => {
  assert.equal(Model.clean("x".repeat(500), 64).length, 64)
})

test("clean tolerates null and undefined", () => {
  assert.equal(Model.clean(null), "")
  assert.equal(Model.clean(undefined), "")
})

test("parseExample returns [] on malformed input, keeping last-good state", () => {
  assert.deepEqual(Model.parseExample("not json"), [])
  assert.deepEqual(Model.parseExample(""), [])
  assert.deepEqual(Model.parseExample(null), [])
})

test("parseExample maps rows through clean", () => {
  const rows = Model.parseExample(JSON.stringify([{ name: "<b>alpha</b>", value: "1" }]))
  assert.equal(rows.length, 1)
  assert.equal(rows[0].name, "balpha/b")
})

test("pillText is empty when there is nothing to say", () => {
  assert.equal(Model.pillText([]), "")
  assert.equal(Model.pillText(null), "")
})
