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
  // https only: curl would happily take file:// or a dash-prefixed value it
  // parses as an option, and the key must never ride cleartext http.
  readonly property bool aiUrlOk: /^https:\/\/\S+$/.test(aiBaseUrl)
  readonly property bool aiEnabled: aiUrlOk && aiModel !== "" && aiApiKey !== ""

  // ---- Fixed behavior. Omakase constants, not knobs.
  readonly property int refreshSec: 900        // schedule + standings cadence
  readonly property int liveRefreshSec: 20     // GUMBO poll cadence while live
  readonly property int scheduleRows: 5        // upcoming games shown
  readonly property int standingsRowsMax: 5    // division table rows

  function open() {
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
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

  // Popout-switch contract the BarWidget host routes to. Nothing here needs
  // special close behavior, so a switch is just a close.
  property bool popoutSwitchClosing: false
  function closeForPopoutSwitch() {
    root.close()
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
  property var gumbo: Model.emptyGumbo()
  // Which gamePk the current gumbo object belongs to — a doubleheader can
  // flip games without isLive ever dipping false.
  property int gumboPk: 0
  property string recapText: ""
  // Key of the situation recapText describes; a fetch in flight carries its
  // own key so a failed generation retries on the next refresh instead of
  // being skipped forever.
  property string recapShownKey: ""
  property string recapPendingKey: ""
  // One forced schedule refresh per game when GUMBO calls Final first.
  property int finalRefreshedPk: 0

  // Re-evaluated every 30s so the countdown ticks without any fetch.
  property double nowMs: Date.now()

  readonly property var gameState: Model.currentOrNext(games, nowMs)
  readonly property bool isLive: gameState.status === "live"
  // BarWidget lights the pill from this (template contract name).
  readonly property bool isAlert: isLive

  // Bar pill. Never silently vanishes: while loading it shows an ellipsis so
  // an unreachable API reads as "loading", not "widget gone".
  //   loading            : "…"
  //   pregame            : "ATL @ CWS 1h 05m"  (or "… now" in a rain delay)
  //   live               : "ATL 1-0 · T4 · 2-2, 0 out"
  //   postgame           : "ATL W 4-2"
  //   nothing in 8 days  : ""  (legitimately quiet; slot collapses)
  readonly property string label: {
    if (!scheduleLoaded) return "…"
    if (gameState.status === "off") return ""
    return Model.pillText(gameState, myTeamId, gumbo)
  }

  readonly property string tooltip: {
    if (!scheduleLoaded) return "MLB Booth · loading schedule…"
    if (gameState.status === "off") return "MLB Booth · no games in the next week"
    var s = Model.scorePair(gameState, myTeamId)
    var vs = gameState.game.isHome ? " vs " : " at "
    if (isLive) return s.mine.name + vs + s.theirs.name + " · LIVE"
    if (gameState.status === "final") return s.mine.name + vs + s.theirs.name + " · Final"
    return s.mine.name + vs + s.theirs.name + " · "
      + Qt.formatDateTime(new Date(gameState.game.startMs), "ddd d MMM · HH:mm")
  }

  onMyTeamIdChanged: {
    games = []
    scheduleLoaded = false
    standings = ({ division: "", rows: [] })
    gumbo = Model.emptyGumbo()
    gumboPk = 0
    recapText = ""
    recapShownKey = ""
    recapPendingKey = ""
    refresh()
  }

  function refresh() {
    var d0 = new Date(nowMs - 86400000).toISOString().slice(0, 10)
    var d1 = new Date(nowMs + 7 * 86400000).toISOString().slice(0, 10)
    scheduleProc.command = curl("https://statsapi.mlb.com/api/v1/schedule?sportId=1&teamId="
      + myTeamId + "&hydrate=team,linescore&startDate=" + d0 + "&endDate=" + d1)
    if (!scheduleProc.running) scheduleProc.running = true
    var season = new Date(nowMs).toISOString().slice(0, 4)
    standingsProc.command = curl("https://statsapi.mlb.com/api/v1/standings?leagueId=103,104&season=" + season)
    if (!standingsProc.running) standingsProc.running = true
  }

  // ---- Live polling. While a game runs, poll the GUMBO feed on the fast
  //      timer. Every fetch is byte-bounded (--max-filesize) so an oversized
  //      body can never freeze the shell's UI thread on JSON.parse.
  function liveTick() {
    nowMs = Date.now()
    if (!isLive || !(gameState.game.gamePk > 0)) return
    if (gameState.game.gamePk !== gumboPk) {
      // Game 2 of a doubleheader: never render game 1's innings under the
      // new game's header while the first fresh poll is still in flight.
      gumbo = Model.emptyGumbo()
      gumboPk = gameState.game.gamePk
    }
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
    return ["curl", "-fsS", "--max-time", "15", "--max-filesize", "4000000", "--", url]
  }

  onIsLiveChanged: {
    if (!isLive) {
      // Game over: drop the live view so the next game starts clean, then
      // let the recap fill the dead air.
      gumbo = Model.emptyGumbo()
      maybeRecap()
    }
  }

  // ---- Optional BYOK recap. One short completion per game-state change
  //      (cached by key), never while a game is live. The widget is complete
  //      without it.
  function maybeRecap() {
    if (!aiEnabled || isLive || !scheduleLoaded) return
    var key = Model.recapCacheKey(gameState)
    // A recap for a gone situation must not linger under the new one.
    if (recapText !== "" && recapShownKey !== key) recapText = ""
    if (key === "off" || key === "live" || key === recapShownKey) return
    if (recapProc.running) return
    // Wait for the record before writing the storyline; a recap generated
    // without standings caches thin and never regenerates.
    if (standings.rows.length === 0) return
    recapPendingKey = key
    var context = Model.recapContext(teamAbbr, gameState, standings, games, nowMs)
    var body = Model.recapRequestBody(aiModel, context)
    var url = aiBaseUrl.replace(/\/+$/, "") + "/chat/completions"
    // --proto =https and the -- terminator pin curl to the one thing the
    // manifest promises: an https POST to the configured base URL. Without
    // the terminator a dash-prefixed base URL would parse as curl OPTIONS
    // (-o writes files, -K loads a config); aiUrlOk already rejects those,
    // and this makes the argv safe even if that check ever regresses.
    // The key rides curl's STDIN via `--header @-`, never an argv element:
    // a process command line is readable by any same-uid process for the life
    // of the request, so an -H Authorization here would expose the user's key
    // to `ps`. The header is written in recapProc.onStarted below.
    recapProc.command = [
      "curl", "-fsS", "--proto", "=https", "--max-time", "30", "--max-filesize", "1000000",
      "-H", "Content-Type: application/json",
      "--header", "@-",
      "-d", body, "--", url
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
        if (parsed.rows.length) {
          root.standings = parsed
          root.maybeRecap()
        }
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
          // GUMBO knows the game ended before the slow schedule refresh
          // does; refresh once per game, not on every 20s poll until the
          // schedule catches up.
          if (parsed.state === "Final" && root.finalRefreshedPk !== root.gumboPk) {
            root.finalRefreshedPk = root.gumboPk
            root.refresh()
          }
        }
      }
    }
  }

  Process {
    id: recapProc
    stdinEnabled: true
    onStarted: {
      // One write, then close stdin so curl stops waiting and sends. This is
      // the same mechanism the first-party network panel uses to hand a wifi
      // passphrase to a helper without putting it in an argv.
      recapProc.write("Authorization: Bearer " + root.aiApiKey + "\n")
      recapProc.stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var textOut = Model.parseRecap(text)
        if (textOut !== "") {
          root.recapText = textOut
          root.recapShownKey = root.recapPendingKey
        }
        // On failure recapShownKey stays unset for this key, so the next
        // 15-minute refresh retries instead of skipping the game forever.
        root.recapPendingKey = ""
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
                // Team names come from the MLB Stats API, so the hero line is
                // not authored text. heroCol is anchored left and right, so its
                // width is the frame this must stay inside.
                width: heroCol.width
                elide: Text.ElideRight
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
                  if (root.gameState.status === "off") return ""
                  return root.gameState.game.detail.toUpperCase()
                }
                textFormat: Text.PlainText
                width: heroCol.width
                elide: Text.ElideRight
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
                      return root.gameState.msUntil <= 30000
                        ? root.gameState.game.detail
                        : "First pitch in " + Model.countdown(root.gameState.msUntil)
                    if (root.gameState.status === "final") {
                      var s = Model.scorePair(root.gameState, root.myTeamId)
                      return "FINAL " + Math.max(0, s.mine.score) + "-" + Math.max(0, s.theirs.score)
                    }
                    if (root.isLive && root.gumbo.valid && root.gumbo.inning)
                      return root.gumbo.inningState + " " + root.gumbo.inningOrdinal
                    return ""
                  }
                  // Sits in a Row beside the LIVE badge inside heroCol, so the
                  // column width is the only hard frame available here.
                  width: Math.min(implicitWidth, heroCol.width)
                  elide: Text.ElideRight
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
                  text: root.gumbo.awayAbbr
                  textFormat: Text.PlainText
                  width: Style.space(28)
                  elide: Text.ElideRight
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  text: root.gumbo.homeAbbr
                  textFormat: Text.PlainText
                  width: Style.space(28)
                  elide: Text.ElideRight
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              // A game past nine innings shows its trailing nine; the panel is
              // a scorecard, not a scroll, and R H E must never leave the frame.
              Repeater {
                model: root.gumbo.innings.length > 9
                  ? root.gumbo.innings.slice(root.gumbo.innings.length - 9)
                  : root.gumbo.innings

                Column {
                  required property var modelData
                  spacing: Style.space(2)
                  Text {
                    text: String(modelData.n)
                    textFormat: Text.PlainText
                    width: Style.space(16)
                    elide: Text.ElideRight
                    color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: modelData.away < 0 ? "-" : String(modelData.away)
                    textFormat: Text.PlainText
                    width: Style.space(16)
                    elide: Text.ElideRight
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: modelData.home < 0 ? "-" : String(modelData.home)
                    textFormat: Text.PlainText
                    width: Style.space(16)
                    elide: Text.ElideRight
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
                  width: Style.space(56)
                  elide: Text.ElideRight
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  text: root.gumbo.homeRuns + " " + root.gumbo.homeHits + " " + root.gumbo.homeErrors
                  textFormat: Text.PlainText
                  width: Style.space(56)
                  elide: Text.ElideRight
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
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              text: Model.countText(root.gumbo.balls, root.gumbo.strikes) + ", "
                + root.gumbo.outs + " out · On base: " + Model.basesText(root.gumbo.bases)
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }

            Text {
              visible: root.gumbo.batter !== ""
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              text: "At bat: " + root.gumbo.batter + " · Pitching: " + root.gumbo.pitcher
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
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

                // Opponent colour, same rule as the standings table, so the
                // schedule and the standings agree about who is who.
                Rectangle {
                  id: oppStripe
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(2)
                  height: Style.space(12)
                  radius: width / 2
                  color: Qt.hsla(Model.clubHue(modelData.isHome
                    ? modelData.away.name : modelData.home.name), 0.62, 0.55, 0.9)
                }

                Text {
                  anchors.left: oppStripe.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(130)
                  maximumLineCount: 1
                  elide: Text.ElideRight
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
                  width: Style.space(90)
                  horizontalAlignment: Text.AlignRight
                  maximumLineCount: 1
                  elide: Text.ElideRight
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

                // Club colour, because that is how anyone who follows the sport
                // reads a division table. Your own club also gets a brighter,
                // taller stripe so the row you care about is findable without
                // reading a single word.
                Rectangle {
                  id: clubStripe
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(2)
                  height: isMine ? Style.space(14) : Style.space(11)
                  radius: width / 2
                  color: Qt.hsla(Model.clubHue(modelData.name), 0.62, isMine ? 0.66 : 0.52,
                                 isMine ? 1.0 : 0.85)
                }

                Text {
                  anchors.left: clubStripe.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.rank + "  " + modelData.name
                  textFormat: Text.PlainText
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: isMine
                  elide: Text.ElideRight
                  width: parent.width - Style.space(150)
                }

                // Two right-anchored columns: every record lines up, and the
                // games-back slot is fixed-width so the leader simply leaves
                // it empty instead of shifting its record sideways.
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16) + Style.space(64)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(64)
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
                  text: modelData.wins + "-" + modelData.losses
                  textFormat: Text.PlainText
                  color: root.bar ? Qt.darker(root.bar.foreground, isMine ? 1.0 : 1.3) : Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: isMine
                }

                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(60)
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
                  text: modelData.gb === "-" ? "" : modelData.gb + " back"
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
