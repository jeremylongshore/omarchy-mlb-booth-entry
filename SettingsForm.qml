import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Inline settings: favourite club and 12h/24h wall clocks. Drafts live here
// until Save, so a cancelled edit never writes shell.json.
// Keyboard contract matches the rest of the panel: hjkl/arrows move,
// Enter/Space activate, Escape cancels (handled by the host).
Column {
  id: root
  property var bar: null
  property string team: "ATL"
  property string timeFormat: "24h"

  signal saved(string team, string timeFormat)
  signal cancelled()

  property string draftTeam: "ATL"
  property string draftTimeFormat: "24h"
  property int focusIndex: 0

  readonly property var teamList: Model.teamAbbrs()
  readonly property int teamCount: teamList.length
  readonly property int teamCols: 7
  readonly property int format12Index: teamCount
  readonly property int format24Index: teamCount + 1
  readonly property int saveIndex: teamCount + 2
  readonly property int cancelIndex: teamCount + 3
  readonly property int itemCount: teamCount + 4

  spacing: Style.space(12)
  width: parent ? parent.width : Style.space(420)

  function begin() {
    draftTeam = Model.normalizedTeam(team)
    draftTimeFormat = Model.normalizedTimeFormat(timeFormat)
    var list = Model.teamAbbrs()
    var i = 0
    focusIndex = 0
    for (i = 0; i < list.length; i++) {
      if (list[i] === draftTeam) {
        focusIndex = i
        break
      }
    }
  }

  function move(dx, dy) {
    var n = itemCount
    var i = focusIndex
    var next = i
    if (i < teamCount && dy !== 0 && dx === 0) {
      next = i + dy * teamCols
      if (next < 0) next = 0
      else if (next >= teamCount) next = format12Index
    } else {
      next = i + dx + (i >= teamCount ? dy : 0)
      if (i < teamCount) next = i + dx
      if (next < 0) next = n - 1
      if (next >= n) next = 0
    }
    if (next < 0) next = 0
    if (next >= n) next = n - 1
    focusIndex = next
  }

  function activate() {
    if (focusIndex < teamCount) {
      draftTeam = String(teamList[focusIndex] || draftTeam)
      return
    }
    if (focusIndex === format12Index) {
      draftTimeFormat = "12h"
      return
    }
    if (focusIndex === format24Index) {
      draftTimeFormat = "24h"
      return
    }
    if (focusIndex === saveIndex) {
      root.saved(draftTeam, draftTimeFormat)
      return
    }
    root.cancelled()
  }

  function focusColor() {
    return root.bar ? root.bar.urgent : Color.urgent
  }

  onVisibleChanged: if (visible) begin()

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    text: "TEAM"
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    text: Model.teamName(root.draftTeam)
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.bar ? root.bar.foreground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.title
    font.bold: true
  }

  Flow {
    id: teamFlow
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    spacing: Style.space(4)
    width: parent.width - Style.space(32)

    Repeater {
      model: root.teamList

      Rectangle {
        required property var modelData
        required property int index
        readonly property string abbr: String(modelData || "")
        readonly property bool selected: abbr === root.draftTeam
        readonly property bool focused: root.focusIndex === index
        width: Style.space(52)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: selected
          ? Qt.hsla(Model.clubHue(Model.teamName(abbr)), 0.62, 0.55, 0.28)
          : (chipArea.containsMouse
            ? (root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "#333")
            : "transparent")
        border.width: focused ? 2 : (selected ? 1 : 0)
        border.color: focused
          ? root.focusColor()
          : Qt.hsla(Model.clubHue(Model.teamName(abbr)), 0.62, 0.55, 0.9)
        focus: focused
        activeFocusOnTab: true

        Accessible.role: Accessible.RadioButton
        Accessible.name: Model.teamName(abbr) + " " + abbr
        Accessible.checkable: true
        Accessible.checked: selected
        Accessible.focusable: true
        Accessible.onPressAction: {
          root.draftTeam = abbr
          root.focusIndex = index
        }

        Text {
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: abbr
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: selected
        }

        MouseArea {
          id: chipArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.draftTeam = abbr
            root.focusIndex = index
          }
        }
      }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    text: "FIRST PITCH"
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.bar ? Qt.darker(root.bar.foreground, 1.4) : Color.muted
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    spacing: Style.space(8)

    Repeater {
      model: [
        { id: "12h", label: "12-hour", index: 0 },
        { id: "24h", label: "24-hour", index: 1 }
      ]

      Rectangle {
        required property var modelData
        readonly property string fmtId: String(modelData.id || "")
        readonly property int fmtIndex: root.format12Index + Number(modelData.index || 0)
        readonly property bool selected: fmtId === root.draftTimeFormat
        readonly property bool focused: root.focusIndex === fmtIndex
        width: Style.space(92)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: selected
          ? (root.bar ? root.bar.foreground : Color.foreground)
          : (fmtArea.containsMouse
            ? (root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "#333")
            : "transparent")
        border.width: focused ? 2 : (selected ? 0 : 1)
        border.color: focused
          ? root.focusColor()
          : (root.bar ? root.bar.foreground : Color.foreground)
        focus: focused
        activeFocusOnTab: true

        Accessible.role: Accessible.RadioButton
        Accessible.name: String(modelData.label || "") + " first pitch"
        Accessible.checkable: true
        Accessible.checked: selected
        Accessible.focusable: true
        Accessible.onPressAction: {
          root.draftTimeFormat = fmtId
          root.focusIndex = fmtIndex
        }

        Text {
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: String(modelData.label || "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: selected
            ? (root.bar ? root.bar.background : Color.background)
            : (root.bar ? root.bar.foreground : Color.foreground)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: selected
        }

        MouseArea {
          id: fmtArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.draftTimeFormat = fmtId
            root.focusIndex = fmtIndex
          }
        }
      }
    }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    spacing: Style.space(10)

    Rectangle {
      readonly property bool focused: root.focusIndex === root.saveIndex
      width: Style.space(80)
      height: Style.space(30)
      radius: Style.cornerRadius
      color: root.bar ? root.bar.foreground : Color.foreground
      border.width: focused ? 2 : 0
      border.color: root.focusColor()
      focus: focused
      activeFocusOnTab: true

      Accessible.role: Accessible.Button
      Accessible.name: "Save settings"
      Accessible.focusable: true
      Accessible.onPressAction: root.saved(root.draftTeam, root.draftTimeFormat)

      Text {
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "Save"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.bar ? root.bar.background : Color.background
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.focusIndex = root.saveIndex
          root.saved(root.draftTeam, root.draftTimeFormat)
        }
      }
    }

    Rectangle {
      readonly property bool focused: root.focusIndex === root.cancelIndex
      width: Style.space(92)
      height: Style.space(30)
      radius: Style.cornerRadius
      color: "transparent"
      border.width: focused ? 2 : 1
      border.color: focused ? root.focusColor() : (root.bar ? root.bar.foreground : Color.foreground)
      focus: focused
      activeFocusOnTab: true

      Accessible.role: Accessible.Button
      Accessible.name: "Cancel settings"
      Accessible.focusable: true
      Accessible.onPressAction: root.cancelled()

      Text {
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: "Cancel"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.focusIndex = root.cancelIndex
          root.cancelled()
        }
      }
    }
  }
}
