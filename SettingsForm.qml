import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Inline settings: favourite club and 12h/24h wall clocks. Drafts live here
// until Save, so a cancelled edit never writes shell.json.
Column {
  id: root
  property var bar: null
  property string team: "ATL"
  property string timeFormat: "24h"

  signal saved(string team, string timeFormat)
  signal cancelled()

  property string draftTeam: "ATL"
  property string draftTimeFormat: "24h"

  spacing: Style.space(12)
  width: parent ? parent.width : Style.space(420)

  function begin() {
    draftTeam = Model.normalizedTeam(team)
    draftTimeFormat = Model.normalizedTimeFormat(timeFormat)
  }

  onVisibleChanged: if (visible) begin()

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    text: "TEAM"
    textFormat: Text.PlainText
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
    color: root.bar ? root.bar.foreground : Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.title
    font.bold: true
    elide: Text.ElideRight
  }

  Flow {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    spacing: Style.space(4)
    width: parent.width - Style.space(32)

    Repeater {
      model: Model.teamAbbrs()

      Rectangle {
        required property var modelData
        readonly property string abbr: String(modelData || "")
        readonly property bool selected: abbr === root.draftTeam
        width: Style.space(52)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: selected
          ? Qt.hsla(Model.clubHue(Model.teamName(abbr)), 0.62, 0.55, 0.28)
          : (chipArea.containsMouse
            ? (root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "#333")
            : "transparent")
        border.width: selected ? 1 : 0
        border.color: Qt.hsla(Model.clubHue(Model.teamName(abbr)), 0.62, 0.55, 0.9)

        Text {
          anchors.centerIn: parent
          text: abbr
          textFormat: Text.PlainText
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
          onClicked: root.draftTeam = abbr
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
        { id: "12h", label: "12-hour" },
        { id: "24h", label: "24-hour" }
      ]

      Rectangle {
        required property var modelData
        readonly property string fmtId: String(modelData.id || "")
        readonly property bool selected: fmtId === root.draftTimeFormat
        width: fmtLabel.implicitWidth + Style.space(24)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: selected
          ? (root.bar ? root.bar.foreground : Color.foreground)
          : (fmtArea.containsMouse
            ? (root.bar ? Style.hoverFillFor(root.bar.foreground, Color.accent) : "#333")
            : "transparent")
        border.width: selected ? 0 : 1
        border.color: root.bar ? root.bar.foreground : Color.foreground

        Text {
          id: fmtLabel
          anchors.centerIn: parent
          text: String(modelData.label || "")
          textFormat: Text.PlainText
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
          onClicked: root.draftTimeFormat = fmtId
        }
      }
    }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    spacing: Style.space(10)

    Rectangle {
      width: saveLabel.implicitWidth + Style.space(28)
      height: Style.space(30)
      radius: Style.cornerRadius
      color: root.bar ? root.bar.foreground : Color.foreground

      Text {
        id: saveLabel
        anchors.centerIn: parent
        text: "Save"
        textFormat: Text.PlainText
        color: root.bar ? root.bar.background : Color.background
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.saved(root.draftTeam, root.draftTimeFormat)
      }
    }

    Rectangle {
      width: cancelLabel.implicitWidth + Style.space(28)
      height: Style.space(30)
      radius: Style.cornerRadius
      color: "transparent"
      border.width: 1
      border.color: root.bar ? root.bar.foreground : Color.foreground

      Text {
        id: cancelLabel
        anchors.centerIn: parent
        text: "Cancel"
        textFormat: Text.PlainText
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.cancelled()
      }
    }
  }
}
