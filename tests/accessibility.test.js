const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.join(__dirname, "..")
const read = (file) => fs.readFileSync(path.join(root, file), "utf8")

test("settings controls expose names, roles, state, focus, and press actions", () => {
  const qml = read("SettingsForm.qml")

  assert.match(qml, /Accessible\.role: Accessible\.RadioButton/)
  assert.match(qml, /Accessible\.role: Accessible\.Button/)
  assert.match(qml, /Accessible\.name:/)
  assert.match(qml, /Accessible\.checked: selected/)
  assert.match(qml, /Accessible\.focusable: true/)
  assert.match(qml, /Accessible\.onPressAction:/)
  assert.match(qml, /activeFocusOnTab: true/)
  assert.match(qml, /border\.width: focused \? 2/)
})

test("the keyboard controller can traverse, activate, open, and close settings", () => {
  const panel = read("Panel.qml")

  assert.match(panel, /onTabRequested:[\s\S]*settingsForm\.move\(direction, 0\)/)
  assert.match(panel, /onMoveRequested:[\s\S]*settingsForm\.move\(dx, dy\)/)
  assert.match(panel, /onActivateRequested:[\s\S]*settingsForm\.activate\(\)/)
  assert.match(panel, /if \(t === "s" \|\| t === "S"\)/)
  assert.match(panel, /onCloseRequested:[\s\S]*root\.editingSettings = false/)
})

test("pointer and IPC routes open the same settings surface", () => {
  assert.match(read("BarWidget.qml"), /Qt\.RightButton\) root\.openSettings\(\)/)
  assert.match(read("Panel.qml"), /function settings\(\): void \{ root\.openSettings\(\) \}/)
})
