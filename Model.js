// Shared helpers for BarWidget.qml and Panel.qml.

var GLYPH = {
  shield:  "󰯣",
  copy:    "󰆒",
  check:   "󰄬",
  trash:   "󰆴",
  add:     "󰐕",
  cancel:  "󰅖",
  eye:     "󰛐",
  eyeOff:  "󰛑"
}

function parse(text, fallback) {
  try {
    var v = JSON.parse(String(text || ""))
    return v === null ? fallback : v
  } catch (e) {
    return fallback
  }
}

function clean(text) {
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== "") return lines[i].trim()
  }
  return ""
}

// "123456" → "123 456"
function formatCode(code) {
  var s = String(code || "------")
  return s.length === 6 ? s.substring(0, 3) + " " + s.substring(3) : s
}
