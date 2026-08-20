// Data layer: pure parse/format functions over raw API responses. No QML or
// network access here — the same file loads in Quickshell (via
// `import "Model.js" as Model`) and in node for the unit suite.
//
// TEMPLATE: replace parseExample/pillText/tooltipText with your real data
// functions. Keep clean() and route EVERY api string through it.

// Sanitize every string that comes from an API before it reaches a QML Text.
// Two reasons: (1) a first-party bar label renders as Qt AutoText, which
// promotes an HTML-looking string to StyledText — an `<img src=...>` in an
// API field would make the shell process fetch a URL; stripping angle
// brackets defuses that. (2) A pathologically long field is a layout-cost
// problem, so cap it.
function clean(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[<>]/g, "").replace(/[\x00-\x1f\x7f]/g, "")
  var cap = max || 64
  return s.length > cap ? s.slice(0, cap) : s
}

// TEMPLATE: parse a raw response body into display rows. Malformed input
// returns [] so the panel keeps last-good state.
function parseExample(raw) {
  var data
  try { data = JSON.parse(String(raw || "")) } catch (e) { return [] }
  if (!data || !data.length) return []
  var out = []
  for (var i = 0; i < data.length; i++) {
    out.push({
      name: clean(data[i].name, 32),
      value: clean(data[i].value, 16)
    })
  }
  return out
}

// TEMPLATE: the bar pill text for the current state.
function pillText(rows) {
  return rows && rows.length ? clean(rows[0].name, 24) : ""
}

// TEMPLATE: the pill tooltip.
function tooltipText(rows) {
  return rows && rows.length ? rows.length + " item(s)" : ""
}

if (typeof module !== "undefined") {
  module.exports = {
    clean: clean,
    parseExample: parseExample,
    pillText: pillText,
    tooltipText: tooltipText
  }
}
