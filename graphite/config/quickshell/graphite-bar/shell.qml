// Graphite bar, Quickshell PROTOTYPE (opt-in; Waybar stays the default).
// Try it: `pkill waybar; qs -c graphite-bar`   Back: `pkill -x qs; hyprctl dispatch exec waybar`
// Colours come from Colors.qml, rendered by graphite-theme from the active colors.toml.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

ShellRoot {
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; left: true; right: true }
            implicitHeight: 34
            color: "transparent"
            Rectangle {
                anchors.fill: parent; anchors.margins: 4; anchors.bottomMargin: 0
                radius: 10; color: Colors.background; border.color: Colors.overlay; border.width: 1
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 6
                    // workspaces (always show 1-5, like the Waybar config; the active one is an accent pill)
                    Repeater {
                        model: 5
                        Rectangle {
                            required property int index
                            property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                            property bool active: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === index + 1
                            implicitWidth: active ? 28 : 18; implicitHeight: 18; radius: 9
                            color: active ? Colors.accent : (ws ? Colors.overlay : Colors.surface)
                            Behavior on implicitWidth { NumberAnimation { duration: 120 } }
                            MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + (index + 1)) }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        id: clock
                        color: Colors.foreground; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 13
                        text: Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")
                        Timer { interval: 10000; running: true; repeat: true; onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm") }
                    }
                }
            }
        }
    }
}
