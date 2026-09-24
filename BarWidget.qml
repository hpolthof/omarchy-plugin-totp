import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Host of all state. Every read and write goes through here; Panel.qml is a
// passive mirror that calls back via hostWidget.
BarWidget {
  id: root
  moduleName: "io.github.hpolthof.totp"

  readonly property string binPath: String(Qt.resolvedUrl("bin/totp")).replace(/^file:\/\//, "")

  property var accounts: []
  property int remaining: 30
  property bool busy: false
  property string lastError: ""

  // Epoch used to detect 30-second window changes without relying on
  // exact-second timer alignment.
  property int lastEpoch: Math.floor(Date.now() / 1000 / 30)

  readonly property var mirroredProperties: [
    "bar", "settings", "accounts", "remaining", "busy", "lastError"
  ]

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    for (var i = 0; i < root.mirroredProperties.length; i++) {
      var name = root.mirroredProperties[i]
      if (name in target) target[name] = root[name]
    }
  }

  // ---------------------------------------------------------------- reading

  function refreshList() {
    if (listProc.running) return
    listProc.command = [root.binPath, "list"]
    listProc.running = true
  }

  // ---------------------------------------------------------------- writing

  function addAccount(name, secret, issuer) {
    if (actionProc.running) return
    root.busy = true
    root.lastError = ""
    root.injectPanel()
    var args = [root.binPath, "add", String(name), String(secret)]
    if (issuer && String(issuer).trim() !== "") args.push(String(issuer))
    actionProc.command = args
    actionProc.running = true
  }

  function deleteAccount(id) {
    if (actionProc.running) return
    root.busy = true
    root.lastError = ""
    root.injectPanel()
    actionProc.command = [root.binPath, "delete", String(id)]
    actionProc.running = true
  }

  // -------------------------------------------------------------- lifecycle

  function open() {
    if (panelLoader.item) panelLoader.item.open()
    root.refreshList()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  Component.onCompleted: root.refreshList()
  onBarChanged: root.injectPanel()
  onSettingsChanged: root.injectPanel()

  // ---------------------------------------------------------------- processes

  Process {
    id: listProc
    property string outText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: listProc.outText = text }
    onExited: function(code) {
      if (code === 0) {
        var result = Model.parse(listProc.outText, null)
        if (result) {
          root.accounts = result.accounts || []
          root.remaining = result.remaining || 30
        }
      }
      listProc.outText = ""
      root.injectPanel()
    }
  }

  Process {
    id: actionProc
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: actionProc.errText = text }
    onExited: function(code) {
      if (code !== 0) root.lastError = Model.clean(actionProc.errText) || "Operation failed"
      actionProc.errText = ""
      root.busy = false
      root.refreshList()
    }
  }

  // Countdown timer — runs only while the panel is open so we don't hammer
  // the process every second on every monitor when the panel is closed.
  // Detects epoch changes to refresh codes at the 30-second window boundary.
  Timer {
    interval: 1000
    repeat: true
    running: root.opened
    onTriggered: {
      var now = Math.floor(Date.now() / 1000)
      var epoch = Math.floor(now / 30)
      var newRemaining = 30 - (now % 30)
      if (epoch !== root.lastEpoch) {
        root.lastEpoch = epoch
        root.refreshList()
      } else {
        root.remaining = newRemaining
        root.injectPanel()
      }
    }
  }

  // ---------------------------------------------------------------- panel

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "io.github.hpolthof.totp"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refreshList() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Model.GLYPH.shield
    fontSize: Style.font.icon
    dimmed: root.accounts.length === 0
    tooltipText: root.accounts.length === 0
      ? "Authenticator — no accounts yet"
      : (root.accounts.length === 1 ? "1 account" : root.accounts.length + " accounts")
    onPressed: function(mouseButton) { root.toggle() }
  }
}
