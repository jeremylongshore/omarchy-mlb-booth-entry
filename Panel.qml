import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// MLB Booth panel: owns the schedule/standings fetch cycle, the GUMBO live
// polling loop, the optional BYOK recap, and the popup UI. Hosted invisibly
// by BarWidget.qml, which renders `label` in the bar slot.
//
// Data is the MLB Stats API (statsapi.mlb.com), free and keyless. The only
// setting a user must own is the team; the three AI fields are optional and
// the widget is complete without them.
Panel {
  id: root
  moduleName: "io.github.jeremylongshore.mlb-booth"
  ipcTarget: "io.github.jeremylongshore.mlb-booth"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar identifies this plugin by the widget mounted in its slot, not by
  // this nested panel.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Settings. Team is the one real choice; the AI trio is optional and
  //      off until all three are filled.
  readonly property string teamAbbr: String(setting("team", "ATL")).toUpperCase()
  readonly property int myTeamId: Model.teamId(teamAbbr)
  readonly property string aiBaseUrl: String(setting("aiBaseUrl", ""))
  readonly property string aiModel: String(setting("aiModel", ""))
  readonly property string aiApiKey: String(setting("aiApiKey", ""))
  readonly property bool aiEnabled: aiBaseUrl !== "" && aiModel !== "" && aiApiKey !== ""

  // ---- Fixed behavior. Omakase constants, not knobs.
  readonly property int refreshSec: 900        // schedule + standings cadence
  readonly property int liveRefreshSec: 20     // GUMBO poll cadence while live
  readonly property int scheduleRows: 5        // upcoming games shown
  readonly property int standingsRowsMax: 5    // division table rows

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
  property var games: []
  property bool scheduleLoaded: false
  property var standings: ({ division: "", rows: [] })
  property var gumbo: ({ valid: false })
  property string recapText: ""
  property string recapShownKey: ""

  // Re-evaluated every 30s so the countdown ticks without any fetch.
  property double nowMs: Date.now()

  readonly property var gameState: Model.currentOrNext(games, nowMs)
  readonly property bool isLive: gameState.status === "live"
  // BarWidget lights the pill from this (template contract name).
  readonly property bool isAlert: isLive

  // Bar pill. Never silently vanishes: the ball glyph is always present so an
  // unreachable API reads as "loading", not "widget gone".
  //   loading            : "󰡒 …"
  //   pregame            : "󰡒 ATL @ CWS 1h 05m"
  //   live               : "󰡒 ATL 1-0 · T4 · 2-2, 0 out"
  //   postgame           : "󰡒 ATL W 4-2"
  //   nothing in 8 days  : ""  (legitimately quiet; slot collapses)
  readonly property string label: {
    if (!scheduleLoaded) return "󰡒 …"
    if (gameState.status === "off") return ""
    return "󰡒 " + Model.pillText(gameState, myTeamId, gumbo)
  }

  readonly property string tooltip: {
    if (!scheduleLoaded) return "MLB Booth — loading schedule…"
    if (gameState.status === "off") return "MLB Booth — no games in the next week"
    var s = Model.scorePair(gameState, myTeamId)
    var vs = gameState.game.isHome ? " vs " : " at "
    if (isLive) return s.mine.name + vs + s.theirs.name + " · LIVE"
    if (gameState.status === "final") return s.mine.name + vs + s.theirs.name + " · Final"
    return s.mine.name + vs + s.theirs.name + " · "
      + Qt.formatDateTime(new Date(gameState.game.startMs), "ddd d MMM · HH:mm")
  }

  function refresh() {
    var d0 = new Date(nowMs - 86400000).toISOString().slice(0, 10)
    var d1 = new Date(nowMs + 7 * 86400000).toISOString().slice(0, 10)
    scheduleProc.command = curl("https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId="
      + myTeamId + "&hydrate=team,linescore&startDate=" + d0 + "&endDate=" + d1)
    if (!scheduleProc.running) scheduleProc.running = true
    var season = new Date(nowMs).getFullYear()
    standingsProc.command = curl("https://statsapi.mlb.com/api/v1/standings?leagueId=103,104&season=" + season)
    if (!standingsProc.running) standingsProc.running = true
  }

  // ---- Live polling. While a game runs, poll the GUMBO feed on the fast
  //      timer. Every fetch is byte-bounded (--max-filesize) so an oversized
  //      body can never freeze the shell's UI thread on JSON.parse.
  function liveTick() {
    nowMs = Date.now()
    if (!isLive || !gameState.game.gamePk) return
    if (!gumboProc.running) {
      gumboProc.command = curl("https://statsapi.mlb.com/api/v1.1/game/"
        + gameState.game.gamePk + "/feed/live")
      gumboProc.running = true
    }
  }

  // Shared curl argv. --max-filesize caps the body (a GUMBO feed runs a few
  // hundred KB and grows through a game); curl exits non-zero past the cap,
  // the collector gets nothing, and the parser keeps last-good.
  function curl(url) {
    return ["curl", "-fsS", "--max-time", "15", "--max-filesize", "8000000", url]
  }

  onIsLiveChanged: {
    if (!isLive) {
      // Game over: drop the live view so the next game starts clean, then
      // let the recap fill the dead air.
      gumbo = ({ valid: false })
      maybeRecap()
    }
  }

  // ---- Optional BYOK recap. One short completion per game-state change
  //      (cached by key), never while a game is live. The widget is complete
  //      without it.
  function maybeRecap() {
    if (!aiEnabled || isLive || !scheduleLoaded) return
    var key = Model.recapCacheKey(gameState, myTeamId)
    if (key === "off" || key === "live" || key === recapShownKey) return
    if (recapProc.running) return
    recapShownKey = key
    var context = Model.recapContext(teamAbbr, gameState, standings, games, nowMs)
    var body = Model.recapRequestBody(aiModel, context)
    var url = aiBaseUrl.replace(/\/+$/, "") + "/chat/completions"
    recapProc.command = [
      "curl", "-fsS", "--max-time", "30", "--max-filesize", "1000000",
      "-H", "Content-Type: application/json",
      "-H", "Authorization: Bearer " + aiApiKey,
      "-d", body, url
    ]
    recapProc.running = true
  }

  Process {
    id: scheduleProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseSchedule(text, root.myTeamId)
        if (parsed.length) {
          root.games = parsed
          root.scheduleLoaded = true
          root.maybeRecap()
        }
      }
    }
  }

  Process {
    id: standingsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseStandings(text, root.myTeamId)
        if (parsed.rows.length) root.standings = parsed
      }
    }
  }

  Process {
    id: gumboProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseGumbo(text)
        if (parsed.valid) {
          root.gumbo = parsed
          // GUMBO knows the game ended before the slow schedule refresh does.
          if (parsed.state === "Final") root.refresh()
        }
      }
    }
  }

  Process {
    id: recapProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var textOut = Model.parseRecap(text)
        if (textOut !== "") root.recapText = textOut
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
    interval: root.liveRefreshSec * 1000
    running: root.isLive
    repeat: true
    triggeredOnStart: true
    onTriggered: root.liveTick()
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

          // ---- Hero: matchup, live badge or countdown or final.
          Item {
            width: parent.width
            height: heroCol.implicitHeight

            Column {
              id: heroCol
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              spacing: Style.space(4)

              Text {
                text: {
                  if (!root.scheduleLoaded) return "LOADING…"
                  if (root.gameState.status === "off") return "NO GAMES THIS WEEK"
                  var s = Model.scorePair(root.gameState, root.myTeamId)
                  return (s.mine.name + (root.gameState.game.isHome ? " VS " : " AT ") + s.theirs.name).toUpperCase()
                }
                textFormat: Text.PlainText
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 1
              }

              Text {
                visible: !root.scheduleLoaded || root.gameState.status !== "off"
                text: {
                  if (!root.scheduleLoaded) return "Fetching schedule from the MLB Stats API…"
                  if (root.gameState.status === "final") return root.gameState.game.detail.toUpperCase()
                  return root.gameState.game.detail.toUpperCase()
                }
                textFormat: Text.PlainText
                color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
              }

              Row {
                visible: root.scheduleLoaded && root.gameState.status !== "off"
                spacing: Style.space(8)

                Rectangle {
                  visible: root.isLive
                  width: liveText.implicitWidth + Style.space(12)
                  height: liveText.implicitHeight + Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  radius: Style.cornerRadius
                  color: root.bar ? root.bar.urgent : Color.urgent

                  Text {
                    id: liveText
                    anchors.centerIn: parent
                    text: "● LIVE"
                    textFormat: Text.PlainText
                    color: root.bar ? root.bar.background : Color.background
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Text {
                  text: {
                    if (root.gameState.status === "next")
                      return "First pitch in " + Model.countdown(root.gameState.msUntil)
                    if (root.gameState.status === "final") {
                      var s = Model.scorePair(root.gameState, root.myTeamId)
                      return "FINAL " + Math.max(0, s.mine.score) + "-" + Math.max(0, s.theirs.score)
                    }
                    if (root.isLive && root.gumbo.valid && root.gumbo.inning)
                      return root.gumbo.inningState + " " + root.gumbo.inningOrdinal
                    return ""
                  }
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.display
                  font.bold: root.isLive
                }
              }
            }
          }

          // ---- Live: line score, count and bases, last play.
          Column {
            visible: root.isLive && root.gumbo.valid
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: "LINE SCORE"
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            // Inning-by-inning grid: label column then one narrow column per
            // inning, then R H E.
            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              spacing: Style.space(8)

              Column {
                spacing: Style.space(2)
                Text {
                  text: " "
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  // "||""" keeps the binding a QString before the first GUMBO
                  // poll fills the object (undefined logs a scene warning).
                  text: root.gumbo.awayAbbr || ""
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  text: root.gumbo.homeAbbr || ""
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              Repeater {
                model: root.gumbo.innings

                Column {
                  required property var modelData
                  spacing: Style.space(2)
                  Text {
                    text: String(modelData.n)
                    textFormat: Text.PlainText
                    color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: modelData.away < 0 ? "-" : String(modelData.away)
                    textFormat: Text.PlainText
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: modelData.home < 0 ? "-" : String(modelData.home)
                    textFormat: Text.PlainText
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }

              Column {
                spacing: Style.space(2)
                Text {
                  text: "R H E"
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  text: root.gumbo.awayRuns + " " + root.gumbo.awayHits + " " + root.gumbo.awayErrors
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  text: root.gumbo.homeRuns + " " + root.gumbo.homeHits + " " + root.gumbo.homeErrors
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
            }

            Item { width: 1; height: Style.space(6) }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              text: Model.countText(root.gumbo.balls, root.gumbo.strikes) + ", "
                + root.gumbo.outs + " out · On base: " + Model.basesText(root.gumbo.bases)
              textFormat: Text.PlainText
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              visible: root.gumbo.batter !== ""
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              text: "At bat: " + root.gumbo.batter + " · Pitching: " + root.gumbo.pitcher
              textFormat: Text.PlainText
              color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              visible: root.gumbo.lastPlay !== ""
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              text: "Last play: " + root.gumbo.lastPlay
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.bar ? Qt.darker(root.bar.foreground, 1.2) : Color.muted
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }

          // ---- The Booth: optional AI storyline between games.
          Column {
            visible: !root.isLive && root.recapText !== ""
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: "THE BOOTH"
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              text: root.recapText
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          // ---- Upcoming games.
          Column {
            visible: root.scheduleLoaded
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: "SCHEDULE · LOCAL TIME"
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Repeater {
              model: {
                var upcoming = []
                for (var i = 0; i < root.games.length; i++) {
                  var g = root.games[i]
                  if (g.state === "pre" && g.startMs > root.nowMs) upcoming.push(g)
                  if (upcoming.length >= root.scheduleRows) break
                }
                return upcoming
              }

              Item {
                required property var modelData
                width: contentColumn.width
                height: Style.space(22)

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (modelData.isHome ? "vs " : "@ ")
                    + (modelData.isHome ? modelData.away.name : modelData.home.name)
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: Qt.formatDateTime(new Date(modelData.startMs), "ddd HH:mm")
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }
          }

          // ---- Division standings.
          Column {
            visible: root.standings.rows.length > 0
            width: parent.width
            spacing: Style.space(2)

            PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

            PanelSectionHeader {
              text: root.standings.division.toUpperCase()
              leftPadding: Style.space(16)
              foreground: root.bar ? root.bar.foreground : Color.foreground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Repeater {
              model: root.standings.rows.slice(0, root.standingsRowsMax)

              Item {
                required property var modelData
                readonly property bool isMine: modelData.id === root.myTeamId
                width: contentColumn.width
                height: Style.space(20)

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.rank + "  " + modelData.name
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: isMine
                  elide: Text.ElideRight
                  width: parent.width - Style.space(140)
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  // Leader shows the bare record; the pack shows games back.
                  text: modelData.wins + "-" + modelData.losses
                    + (modelData.gb === "-" ? "" : "  " + modelData.gb + " back")
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, isMine ? 1.0 : 1.3) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: isMine
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
