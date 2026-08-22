import QtQuick
import QtQuick.Controls as QQC2
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "user.omarchy-notion"
  ipcTarget: "user.omarchy-notion"

  readonly property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/user.omarchy-notion/omarchy-notion"
  property bool configured: false
  property string statusText: "Checking Notion setup…"
  property string databaseUrl: ""
  property string clipboardImagePath: ""

  function safeMessage(value, fallback) {
    var message = String(value || "").replace(/[\r\n]+/g, " ").trim()
    return message === "" ? fallback : message.slice(0, 512)
  }

  function refreshStatus() {
    if (!statusProcess.running) {
      statusProcess.command = [helperPath, "status", "--json"]
      statusProcess.running = true
    }
  }

  function saveCapture() {
    if (!configured || titleField.text.trim() === "" || captureProcess.running) return
    statusText = "Saving…"
    captureProcess.payload = JSON.stringify({
      title: titleField.text.trim(),
      body: bodyField.text,
      tags: tagsField.text.split(",").map(function(value) { return value.trim() }).filter(function(value) { return value !== "" }),
      source: "Widget",
      image_path: clipboardImagePath,
      delete_image: clipboardImagePath !== ""
    })
    captureProcess.command = [helperPath, "capture", "--json"]
    captureProcess.running = true
  }

  function pasteClipboard() {
    if (!configured || clipboardProcess.running) return
    statusText = "Reading clipboard…"
    clipboardProcess.command = [helperPath, "clipboard-read"]
    clipboardProcess.running = true
  }

  function open() {
    root.controller.show()
    Qt.callLater(function() { titleField.forceActiveFocus() })
    refreshStatus()
  }

  Component.onCompleted: refreshStatus()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statusProcess
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          root.configured = result.configured === true && result.has_token === true
          root.databaseUrl = String(result.url || "").slice(0, 2048)
          root.statusText = root.configured ? "Ready to capture" : "Setup required"
        } catch (error) {
          root.configured = false
          root.statusText = "Could not read setup status"
        }
      }
    }
  }

  Process {
    id: captureProcess
    property string payload: ""
    stdinEnabled: true
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.statusText = root.safeMessage(text, "Could not save to Notion")
    }
    onStarted: {
      write(payload + "\n")
      payload = ""
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.statusText = "Saved to Omarchy"
        titleField.text = ""
        bodyField.text = ""
        tagsField.text = ""
        root.clipboardImagePath = ""
        titleField.forceActiveFocus()
      } else if (root.statusText === "Saving…") {
        root.statusText = "Could not save to Notion"
      }
    }
  }

  Process {
    id: clipboardProcess
    property string errorText: ""
    onStarted: errorText = ""
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var result = JSON.parse(text)
          if (result.type === "image/png") {
            root.clipboardImagePath = String(result.path)
            root.statusText = "PNG ready to attach"
          } else if (result.type === "text") {
            bodyField.insert(bodyField.cursorPosition, String(result.text || ""))
            bodyField.forceActiveFocus()
            root.statusText = "Pasted text from clipboard"
          }
        } catch (error) {
          root.statusText = "Could not read clipboard"
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: clipboardProcess.errorText = root.safeMessage(
        text.trim().replace(/^(omarchy-notion|notion):\s*/, ""),
        "Could not read clipboard"
      )
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.statusText = clipboardProcess.errorText || "Clipboard does not contain text or PNG"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "N"
    tooltipText: root.configured ? "Quick capture to Notion" : "Notion Capture setup required"
    dimmed: !root.configured
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: popup.fittedContentWidth(Style.space(520))
    contentHeight: popup.fittedContentHeight(Style.space(430), Style.space(620))

    Column {
      anchors.fill: parent
      spacing: Style.space(12)

      Text {
        text: "Notion quick capture"
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        visible: !root.configured
        text: "First run: create a Notion connection, share a parent page with it, then run the secure setup wizard. The wizard creates an Omarchy database."
        color: Qt.darker(root.barForeground, 1.2)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
      }

      Button {
        visible: !root.configured
        width: parent.width
        text: "Open setup wizard"
        onClicked: Quickshell.execDetached(["xdg-terminal-exec", "--hold", root.helperPath, "setup"])
      }

      TextField {
        id: titleField
        visible: root.configured
        width: parent.width
        placeholderText: "Page title"
        foreground: root.barForeground
        accent: root.barForeground
      }

      Rectangle {
        visible: root.configured
        width: parent.width
        height: Style.space(180)
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.04)
        border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.28)
        border.width: 1

        QQC2.TextArea {
          id: bodyField
          anchors.fill: parent
          anchors.margins: Style.space(8)
          placeholderText: "Write a note…"
          color: root.barForeground
          wrapMode: TextEdit.Wrap
          background: null
          selectByMouse: true
        }
      }

      Button {
        visible: root.configured
        width: parent.width
        text: clipboardProcess.running ? "Pasting…" : (root.clipboardImagePath !== "" ? "PNG attached ✓" : "Paste clipboard")
        active: !clipboardProcess.running
        onClicked: root.pasteClipboard()
      }

      Text {
        visible: root.configured
        width: parent.width
        text: "PNG images up to 20 MB"
        color: Qt.darker(root.barForeground, 1.2)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      TextField {
        id: tagsField
        visible: root.configured
        width: parent.width
        placeholderText: "Tags, separated by commas"
        foreground: root.barForeground
        accent: root.barForeground
      }

      Row {
        visible: root.configured
        width: parent.width
        spacing: Style.space(8)

        Button {
          width: (parent.width - Style.space(8)) / 2
          text: captureProcess.running ? "Saving…" : "Save to Notion"
          active: titleField.text.trim() !== "" && !captureProcess.running
          onClicked: root.saveCapture()
        }
        Button {
          width: (parent.width - Style.space(8)) / 2
          text: "Open in Notion"
          onClicked: if (root.databaseUrl !== "") Quickshell.execDetached(["xdg-open", root.databaseUrl])
        }
      }

      Text {
        width: parent.width
        text: root.statusText
        textFormat: Text.PlainText
        color: Qt.darker(root.barForeground, 1.2)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Button {
        visible: !root.configured
        width: parent.width
        text: "Refresh setup status"
        onClicked: root.refreshStatus()
      }
    }
  }
}
