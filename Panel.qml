import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Passive mirror of BarWidget. Renders what the widget hands it and calls
// back via hostWidget for every action that changes state.
Panel {
  id: root
  moduleName: "io.github.hpolthof.totp"

  property Item anchorItem: null
  property QtObject hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Mirrored from BarWidget — read-only here.
  property var accounts: []
  property int remaining: 30
  property bool busy: false
  property string lastError: ""

  // Panel-local UI state.
  property bool showAdd: false
  property string addName: ""
  property string addSecret: ""
  property string addIssuer: ""
  property bool secretVisible: false
  property string copiedId: ""

  // PanelKeyCatcher must be blocked whenever a TextField is on screen.
  readonly property bool typing: root.showAdd

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Qt.darker(foreground, 1.85)

  // ---------------------------------------------------------------- focus

  function restoreFocus() {
    if (!root.opened) return
    if (root.showAdd) nameField.forceActiveFocus()
    else keyCatcher.forceActiveFocus()
  }

  function open() {
    root.controller.show()
    Qt.callLater(root.restoreFocus)
  }

  function close() {
    root.controller.hide()
    root._resetAdd()
  }

  function openAddForm() {
    root.showAdd = true
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function cancelAdd() {
    root._resetAdd()
    Qt.callLater(root.restoreFocus)
  }

  function _resetAdd() {
    root.showAdd = false
    root.addName = ""
    root.addSecret = ""
    root.addIssuer = ""
    root.secretVisible = false
    root.copiedId = ""
  }

  function submitAdd() {
    var name = root.addName.trim()
    var secret = root.addSecret.trim()
    if (name === "" || secret === "" || !root.hostWidget || root.busy) return
    root.hostWidget.addAccount(name, secret, root.addIssuer.trim())
    root.cancelAdd()
  }

  onOpenedChanged: if (root.opened) Qt.callLater(root.restoreFocus)
  onShowAddChanged: Qt.callLater(root.restoreFocus)

  // ----------------------------------------------------------- clipboard

  Process {
    id: clipProc
    stdout: StdioCollector { waitForEnd: true }
  }
  Timer {
    id: copyClearTimer
    interval: 1500
    onTriggered: root.copiedId = ""
  }
  function copyCode(id, code) {
    root.copiedId = id
    clipProc.command = ["wl-copy", String(code)]
    clipProc.running = true
    copyClearTimer.restart()
  }

  // ---------------------------------------------------------------- popup

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: root.showAdd ? nameField : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(310))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(540))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.typing
      onCloseRequested: root.close()
      onReturnRequested: if (root.showAdd) root.submitAdd()
    }

    // ─────────────────────────────────────── main layout ──────────────────

    Column {
      id: mainColumn
      width: parent.width
      spacing: 0

      // ── Header ────────────────────────────────────────────────────────────
      // Uses height (not implicitHeight) — required for Column positioner.
      Item {
        width: parent.width
        height: Style.spacing.controlHeight + Style.spacing.rowGap * 2

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.controlGap

          Text {
            text: Model.GLYPH.shield
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.icon
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
          }

          Text {
            text: root.showAdd ? "Add Account" : "Authenticator"
            color: root.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
          }
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: root.showAdd ? Model.GLYPH.cancel : Model.GLYPH.add
          tooltipText: root.showAdd ? "Cancel" : "Add account"
          foreground: root.foreground
          onClicked: root.showAdd ? root.cancelAdd() : root.openAddForm()
        }
      }

      PanelSeparator { foreground: root.foreground }

      // ── Disclaimer (list mode only) ──────────────────────────────────────
      Text {
        visible: !root.showAdd
        width: parent.width
        text: "Stored locally · For development use only"
        color: root.faint
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        topPadding: Style.spacing.sm
        bottomPadding: Style.spacing.sm
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
      }

      // ── Timer progress bar (list mode only) ──────────────────────────────
      // height must be explicit on Item for Column layout.
      Item {
        visible: !root.showAdd
        width: parent.width
        height: Style.space(3) + Style.spacing.sm * 2

        Item {
          anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
          }
          height: Style.space(3)

          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            radius: height / 2
          }

          Rectangle {
            width: parent.width * (root.remaining / 30)
            height: parent.height
            radius: height / 2
            color: root.remaining <= 5 ? Color.urgent : Color.accent
            Behavior on width {
              NumberAnimation { duration: 800; easing.type: Easing.OutQuad }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.bottom: parent.top
            anchors.bottomMargin: Style.spacing.xs
            text: root.remaining + "s"
            color: root.remaining <= 5 ? Color.urgent : root.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
          }
        }
      }

      PanelSeparator {
        visible: !root.showAdd
        foreground: root.foreground
      }

      // ── Empty state (list mode, no accounts) ──────────────────────────────
      Item {
        visible: !root.showAdd && root.accounts.length === 0
        width: parent.width
        height: Style.spacing.panelGap * 4

        Column {
          anchors.centerIn: parent
          width: parent.width
          spacing: Style.spacing.sm

          Text {
            width: parent.width
            text: "No accounts yet"
            color: root.dim
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
          }

          Text {
            width: parent.width
            text: "Click + to add a TOTP secret.\nCodes refresh every 30 seconds."
            color: root.faint
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
          }
        }
      }

      // ── Account list (list mode) ──────────────────────────────────────────
      Item {
        id: accountListArea
        visible: !root.showAdd && root.accounts.length > 0
        width: parent.width
        // Cap the list height to avoid an infinitely tall panel.
        height: Math.min(accountsColumn.height, Style.space(340))

        Flickable {
          anchors.fill: parent
          contentHeight: accountsColumn.height
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: accountsColumn
            width: parent.width
            spacing: 0

            Repeater {
              model: root.accounts

              // Delegate root is a Column so it auto-sizes its height.
              delegate: Column {
                id: accountRow
                required property var modelData
                width: parent ? parent.width : 0
                topPadding: Style.spacing.rowGap
                bottomPadding: Style.spacing.rowGap
                spacing: Style.spacing.xs

                // Account name + issuer label
                Text {
                  width: parent.width
                  text: {
                    var n = String(accountRow.modelData.name || "")
                    var iss = String(accountRow.modelData.issuer || "")
                    return iss !== "" ? n + "  ·  " + iss : n
                  }
                  color: root.dim
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }

                // Code text + action buttons on the same row.
                // Item height is explicit so Column knows the size.
                Item {
                  width: parent.width
                  height: Math.max(codeText.height, Style.space(22))

                  Text {
                    id: codeText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatCode(accountRow.modelData.code || "------")
                    color: root.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                    font.bold: true
                    textFormat: Text.PlainText
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xs

                    PanelActionButton {
                      iconText: root.copiedId === accountRow.modelData.id
                                ? Model.GLYPH.check : Model.GLYPH.copy
                      foreground: root.copiedId === accountRow.modelData.id
                                  ? Color.accent : root.foreground
                      hoverColor: Color.accent
                      tooltipText: root.copiedId === accountRow.modelData.id
                                   ? "Copied!" : "Copy code"
                      onClicked: root.copyCode(
                        accountRow.modelData.id,
                        String(accountRow.modelData.code || ""))
                    }

                    PanelActionButton {
                      iconText: Model.GLYPH.trash
                      foreground: root.foreground
                      hoverColor: Color.urgent
                      tooltipText: "Delete account"
                      onClicked: {
                        if (root.hostWidget)
                          root.hostWidget.deleteAccount(accountRow.modelData.id)
                      }
                    }
                  }
                }

                PanelSeparator { foreground: root.foreground }
              }
            }
          }
        }
      }

      // ── Add form ──────────────────────────────────────────────────────────
      // All items inside this Column have proper heights (Text auto-sizes,
      // TextField/Button auto-size from QQC, explicit height on Item wrappers).
      Column {
        visible: root.showAdd
        width: parent.width
        topPadding: Style.spacing.panelGap
        bottomPadding: Style.spacing.panelGap
        spacing: Style.spacing.labelGap

        // ── Account name ────────────────────────────────────────────────────
        Text {
          text: "Account name"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }

        TextField {
          id: nameField
          width: parent.width
          placeholderText: "e.g. GitHub · test@example.com"
          text: root.addName
          onTextChanged: root.addName = text
          onAccepted: secretField.forceActiveFocus()
        }

        Item { height: Style.spacing.rowGap; width: 1 }

        // ── Secret key ──────────────────────────────────────────────────────
        Text {
          text: "Secret key (Base32)"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }

        // TextField + eye toggle on same row. Item height = TextField height.
        Item {
          width: parent.width
          height: secretField.height

          TextField {
            id: secretField
            anchors.left: parent.left
            anchors.right: showHideBtn.left
            anchors.rightMargin: Style.spacing.xs
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "JBSWY3DPEHPK3PXP"
            text: root.addSecret
            password: !root.secretVisible
            onTextChanged: root.addSecret = text
            onAccepted: issuerField.forceActiveFocus()
          }

          PanelActionButton {
            id: showHideBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: root.secretVisible ? Model.GLYPH.eyeOff : Model.GLYPH.eye
            tooltipText: root.secretVisible ? "Hide secret" : "Show secret"
            foreground: root.foreground
            onClicked: root.secretVisible = !root.secretVisible
          }
        }

        Item { height: Style.spacing.rowGap; width: 1 }

        // ── Issuer (optional) ────────────────────────────────────────────────
        Text {
          text: "Issuer (optional)"
          color: root.dim
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }

        TextField {
          id: issuerField
          width: parent.width
          placeholderText: "e.g. GitHub, Jira, AWS"
          text: root.addIssuer
          onTextChanged: root.addIssuer = text
          onAccepted: root.submitAdd()
        }

        // ── Error message ─────────────────────────────────────────────────
        Text {
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: Color.urgent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
        }

        Item { height: Style.spacing.rowGap; width: 1 }

        // ── Save button ───────────────────────────────────────────────────
        Button {
          anchors.right: parent.right
          text: root.busy ? "Saving…" : "Save account"
          enabled: root.addName.trim() !== "" && root.addSecret.trim() !== "" && !root.busy
          onClicked: root.submitAdd()
        }
      }
    }
  }
}
