// Graphite bar (Quickshell): the default bar. Same layout as the Waybar config:
//   left: logo (launcher), workspaces 1-5   centre: clock   right: tray, network, audio, battery, power
// Switch bars with `graphite bar waybar|quickshell` (graphite-bar starts the chosen one).
// Colours come from Colors.qml, rendered by graphite-theme from the active colors.toml.
// Layer namespace "graphite-bar" (Hyprland blur rule, tests).
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    // the launcher (Super+Space): apps, calculator, commands. See Launcher.qml
    Launcher { id: launcher }
    // notification daemon, popups, center and do-not-disturb. See Notifications.qml
    Notifications { id: notifications }

    // ---- audio: default sink via PipeWire (bind it so volume/mute are live) ----
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    // ---- network: NetworkManager via nmcli (polled; same data Waybar shows) ----
    property string netType: ""      // "ethernet" | "wifi" | ""
    property int netSignal: 0
    property string netName: ""
    Process {
        id: nmcli
        command: ["nmcli", "-t", "-e", "no", "-f", "TYPE,STATE,CONNECTION", "device"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = "", n = "";
                for (const l of this.text.split("\n")) {
                    const f = l.split(":");
                    if (f.length >= 3 && f[1] === "connected" && (f[0] === "ethernet" || f[0] === "wifi")) {
                        if (t !== "ethernet") { t = f[0]; n = f.slice(2).join(":"); }
                    }
                }
                root.netType = t; root.netName = n;
                if (t === "wifi") wifi.running = true;
            }
        }
    }
    Process {
        id: wifi
        command: ["nmcli", "-t", "-f", "ACTIVE,SIGNAL", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const a = this.text.split("\n").find(l => l.startsWith("yes:"));
                root.netSignal = a ? parseInt(a.split(":")[1]) : 0;
            }
        }
    }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: nmcli.running = true }

    component Glyph: Text {
        color: Colors.foreground; font.family: root.iconFont; font.pixelSize: 15
        verticalAlignment: Text.AlignVCenter
    }
    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]); }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "graphite-bar"
            WlrLayershell.layer: WlrLayer.Top
            anchors { top: true; left: true; right: true }
            margins { top: 8; left: 12; right: 12 }
            implicitHeight: 34
            exclusiveZone: 34
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                radius: 12; color: Colors.background; border.color: Colors.overlay; border.width: 1

                // left: logo + workspaces
                RowLayout {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Glyph {
                        text: "󰣇"; color: Colors.accent; font.pixelSize: 17
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: launcher.toggle() }
                    }
                    Row {
                        spacing: 5
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                property var ws: Hyprland.workspaces.values.find(w => w.id === index + 1)
                                property bool active: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === index + 1
                                width: active ? 30 : 20; height: 20; radius: 10
                                color: active ? Colors.accent : (ws ? Colors.overlay : Colors.surface)
                                Behavior on width { NumberAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent; text: index + 1; font.pixelSize: 11; font.bold: active
                                    color: active ? Colors.accentText : Colors.muted
                                }
                                MouseArea { anchors.fill: parent; onClicked: Hyprland.dispatch("workspace " + (index + 1)) }
                            }
                        }
                        WheelHandler {
                            onWheel: e => Hyprland.dispatch(e.angleDelta.y > 0 ? "workspace e-1" : "workspace e+1")
                        }
                    }
                }

                // centre: clock (tooltip: full date)
                Text {
                    id: clock
                    anchors.centerIn: parent
                    color: Colors.foreground; font.family: root.iconFont; font.pixelSize: 13; font.bold: true
                    property date now: new Date()
                    text: Qt.formatDateTime(now, "ddd dd MMM  HH:mm")
                    Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }
                }

                // right: tray, status group, power
                RowLayout {
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Repeater {
                        model: SystemTray.items
                        IconImage {
                            required property SystemTrayItem modelData
                            source: modelData.icon; implicitSize: 15
                            MouseArea {
                                anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: e => {
                                    if (e.button === Qt.LeftButton && !modelData.onlyMenu) modelData.activate();
                                    else if (e.button === Qt.MiddleButton) modelData.secondaryActivate();
                                    else if (modelData.hasMenu) {
                                        const p = mapToItem(null, 0, height);
                                        modelData.display(bar, p.x, p.y + 6);
                                    }
                                }
                                onWheel: w => modelData.scroll(w.angleDelta.y / 120, false)
                            }
                        }
                    }

                    Rectangle {
                        implicitHeight: 24; implicitWidth: status.implicitWidth + 18; radius: 12; color: Colors.surface
                        Row {
                            id: status; anchors.centerIn: parent; spacing: 12
                            // network
                            Glyph {
                                text: root.netType === "ethernet" ? "󰈀"
                                    : root.netType === "wifi" ? ["󰤟", "󰤢", "󰤥", "󰤨"][Math.min(3, Math.floor(root.netSignal / 25))]
                                    : "󰤭"
                                color: root.netType ? Colors.foreground : Colors.muted
                                MouseArea { anchors.fill: parent; onClicked: root.run("kitty --class nmtui -e nmtui") }
                            }
                            // audio
                            Glyph {
                                readonly property var a: root.sink && root.sink.audio ? root.sink.audio : null
                                text: !a ? "󰝟" : a.muted ? "󰝟" : a.volume < 0.34 ? "󰕿" : a.volume < 0.67 ? "󰖀" : "󰕾"
                                color: a && !a.muted ? Colors.foreground : Colors.muted
                                MouseArea {
                                    anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: e => e.button === Qt.RightButton
                                        ? root.run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") : root.run("pavucontrol")
                                    onWheel: w => root.run(w.angleDelta.y > 0 ? "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
                                                                              : "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-")
                                }
                            }
                            // battery (laptops only; hidden without a battery, like Waybar)
                            Glyph {
                                readonly property var d: UPower.displayDevice
                                readonly property real pct: d ? d.percentage * (d.percentage <= 1 ? 100 : 1) : 0
                                visible: d !== null && d.isLaptopBattery
                                text: d && d.state === UPowerDeviceState.Charging ? "󰂄"
                                    : ["󰁺", "󰁼", "󰁾", "󰂀", "󰁹"][Math.min(4, Math.floor(pct / 20))]
                                color: pct <= 12 ? Colors.red : pct <= 25 ? Colors.accent2 : Colors.foreground
                            }
                        }
                    }

                    // notifications: bell (count / do-not-disturb); click opens the center
                    Glyph {
                        text: notifications.dnd ? "󰂛" : notifications.count > 0 ? "󰂚" : "󰂜"
                        color: notifications.dnd ? Colors.muted : notifications.count > 0 ? Colors.accent : Colors.foreground
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: e => e.button === Qt.RightButton ? notifications.setDnd(!notifications.dnd)
                                                                       : notifications.centerOpen = !notifications.centerOpen
                        }
                    }
                    Glyph {
                        text: "󰐥"; color: Colors.red
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.run("graphite-menu power") }
                    }
                }
            }
        }
    }
}
