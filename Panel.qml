import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panel: owns the fetch cycle and the popup UI. Hosted invisibly by
// BarWidget.qml, which renders `label` in the bar slot.
//
// TEMPLATE: replace the example fetch with your data source. The security
// pattern is not optional:
//   - every network body parses in Model.js pure functions (testable in node)
//   - every string that reaches a Text passed through Model.clean()
//   - every Text that renders API data declares textFormat: Text.PlainText
//   - every curl argv carries --max-time AND --max-filesize
//   - a failed fetch keeps last-good state; the pill never silently vanishes
Panel {
  id: root
  moduleName: "io.github.YOURNAME.widget-name"
  ipcTarget: "io.github.YOURNAME.widget-name"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar identifies this plugin by the widget mounted in its slot, not by
  // this nested panel.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Fixed behavior. Prefer omakase constants over settings knobs; add a
  //      manifest settings schema only for choices a user genuinely owns.
  readonly property int refreshSec: 900

  function open() {
    openedFromHotkey = false
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // ---- Data state. Raw responses parse into these; last-good values stay
  //      visible when a fetch fails.
  property var rows: []
  property bool loaded: false

  // Re-evaluated on a slow tick so time-based text moves without a fetch.
  property double nowMs: Date.now()

  // TEMPLATE: isAlert lights the bar pill (bar's active color).
  readonly property bool isAlert: false

  // Bar pill. Never silently vanishes: keep a glyph present so an
  // unreachable API reads as "loading", not "widget gone". Return "" only
  // when the widget is legitimately quiet (slot collapses).
  readonly property string label: {
    if (!loaded) return "… "
    return Model.pillText(rows)
  }

  readonly property string tooltip: loaded ? Model.tooltipText(rows) : "Loading…"

  function refresh() {
    if (!exampleProc.running) exampleProc.running = true
  }

  // Shared curl argv. --max-filesize caps the body; curl exits non-zero past
  // the cap, the collector gets nothing, and the parser keeps last-good —
  // never a UI-thread stall on a giant JSON.parse.
  function curl(url) {
    return ["curl", "-fsS", "--max-time", "15", "--max-filesize", "8000000", url]
  }

  Process {
    id: exampleProc
    command: root.curl("https://example.invalid/replace-me.json")
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseExample(text)
        if (parsed.length) {
          root.rows = parsed
          root.loaded = true
        }
      }
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Fan the refresh out to every monitor's widget. One bar exists per
    // screen; broadcast() lives on the BarWidget host, so route through it.
    function refresh(): void {
      if (root.hostWidget && typeof root.hostWidget.broadcast === "function")
        root.hostWidget.broadcast("refresh")
      else root.refresh()
    }
  }

  // ---- Popup UI.
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(12)

          // ---- Hero.
          Column {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(16)
            spacing: Style.space(4)

            Text {
              text: root.loaded ? "WIDGET NAME" : "LOADING…"
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              font.letterSpacing: 1
            }
          }

          // ---- Example list section.
          Column {
            visible: root.rows.length > 0
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: "SECTION"
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Repeater {
              model: root.rows

              Item {
                required property var modelData
                width: contentColumn.width
                height: Style.space(22)

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.name
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.value
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          // Bottom breathing room inside the flickable.
          Item { width: 1; height: Style.space(4) }
        }
      }
    }
  }
}
