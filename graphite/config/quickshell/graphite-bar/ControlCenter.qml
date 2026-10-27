// Graphite control center (desk-4): quick settings in a box under the bar, top right.
// Volume + mute, brightness, Wi-Fi, Bluetooth, power profile and a light/dark theme toggle.
// Open with Super+A, a click on the bar's status group or `graphite-control`; Esc or a click
// outside closes it. Every action goes through graphite-control, so the panel and the CLI
// always agree. Layer namespace "graphite-control-center"; IPC target "control".
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Scope {
    id: cc
    property bool opened: false
    property var st: ({})          // last `graphite-control status`

    function open() { opened = true; refresh(); }
    function close() { opened = false; }
    function refresh() { if (!status.running) status.running = true; }
    function act(args) {
        actProc.command = ["graphite-control"].concat(args);
        actProc.running = true;
    }

    Process {
        id: status
        command: ["graphite-control", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of this.text.split("\n")) {
                    const i = l.indexOf("=");
                    if (i > 0) o[l.slice(0, i)] = l.slice(i + 1);
                }
                cc.st = o;
            }
        }
    }
    Process { id: actProc; onExited: cc.refresh() }
    Timer { interval: 3000; repeat: true; running: cc.opened; onTriggered: cc.refresh() }

    component Tile: Rectangle {
        id: tile
        property string glyph: ""
        property string label: ""
        property string sub: ""
        property bool on: false
        property bool avail: true
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 56; radius: 12
        opacity: avail ? 1 : 0.45
        color: on ? Colors.accent : (ma.containsMouse ? Colors.overlay : Colors.surface)
        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 10
            Text { text: tile.glyph; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18; color: tile.on ? Colors.accentText : Colors.foreground }
            ColumnLayout {
                spacing: 0; Layout.fillWidth: true
                Text { text: tile.label; font.bold: true; font.pixelSize: 13; color: tile.on ? Colors.accentText : Colors.foreground }
                Text { text: tile.sub; font.pixelSize: 11; color: tile.on ? Colors.accentText : Colors.muted; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: tile.avail; onClicked: tile.clicked() }
    }

    component Slider: RowLayout {
        id: sl
        property string glyph: ""
        property int value: 0
        property int maxValue: 100
        property bool avail: true
        signal glyphClicked()
        signal moved(int v)
        Layout.fillWidth: true
        spacing: 10
        opacity: avail ? 1 : 0.45
        Text {
            text: sl.glyph; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18; color: Colors.foreground
            Layout.preferredWidth: 24
            MouseArea { anchors.fill: parent; enabled: sl.avail; onClicked: sl.glyphClicked() }
        }
        Rectangle {
            id: track
            Layout.fillWidth: true; implicitHeight: 8; radius: 4; color: Colors.surface
            Rectangle { width: track.width * Math.min(1, sl.value / sl.maxValue); height: parent.height; radius: 4; color: Colors.accent }
            MouseArea {
                anchors { fill: parent; topMargin: -8; bottomMargin: -8 }
                enabled: sl.avail
                function at(x) { return Math.round(Math.max(0, Math.min(1, x / track.width)) * sl.maxValue); }
                onPressed: m => sl.value = at(m.x)
                onPositionChanged: m => { if (pressed) sl.value = at(m.x); }
                onReleased: sl.moved(sl.value)
                onWheel: w => { sl.value = Math.max(0, Math.min(sl.maxValue, sl.value + (w.angleDelta.y > 0 ? 5 : -5))); sl.moved(sl.value); }
            }
        }
        Text { text: sl.avail ? sl.value + "%" : "n/a"; color: Colors.muted; font.pixelSize: 12; Layout.preferredWidth: 36; horizontalAlignment: Text.AlignRight }
    }

    PanelWindow {
        id: panel
        visible: cc.opened
        WlrLayershell.namespace: "graphite-control-center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; right: true }
        margins { top: 8; right: 12 }
        implicitWidth: 360
        implicitHeight: box.implicitHeight
        color: "transparent"
        exclusiveZone: 0

        Rectangle {
            id: box
            width: parent.width
            implicitHeight: col.implicitHeight + 28
            radius: 14; color: Colors.background; border.color: Colors.overlay; border.width: 1
            focus: true
            Keys.onEscapePressed: cc.close()
            ColumnLayout {
                id: col
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 12
                Text { text: "Control center"; color: Colors.foreground; font.pixelSize: 16; font.bold: true }
                Slider {
                    glyph: cc.st.muted === "yes" ? "󰝟" : "󰕾"
                    avail: (cc.st.volume ?? "none") !== "none"
                    value: parseInt(cc.st.volume) || 0
                    maxValue: 150
                    onGlyphClicked: cc.act(["volume", "mute"])
                    onMoved: v => cc.act(["volume", String(v)])
                }
                Slider {
                    glyph: "󰃟"
                    avail: (cc.st.brightness ?? "none") !== "none"
                    value: parseInt(cc.st.brightness) || 0
                    onMoved: v => cc.act(["brightness", String(Math.max(1, v))])
                }
                GridLayout {
                    columns: 2; columnSpacing: 8; rowSpacing: 8
                    Layout.fillWidth: true
                    Tile {
                        glyph: cc.st.wifi === "on" ? "󰖩" : "󰖪"; label: "Wi-Fi"
                        on: cc.st.wifi === "on"; sub: cc.st.wifi === "on" ? "On" : "Off"
                        onClicked: cc.act(["wifi", "toggle"])
                    }
                    Tile {
                        glyph: "󰂯"; label: "Bluetooth"
                        avail: (cc.st.bluetooth ?? "none") !== "none"
                        on: cc.st.bluetooth === "on"
                        sub: cc.st.bluetooth === "none" ? "No adapter" : (cc.st.bluetooth === "on" ? "On" : "Off")
                        onClicked: cc.act(["bluetooth", "toggle"])
                    }
                    Tile {
                        glyph: "󰓅"; label: "Power"
                        avail: (cc.st.profile ?? "none") !== "none"
                        on: cc.st.profile === "performance"
                        sub: cc.st.profile ?? ""
                        onClicked: cc.act(["profile", "next"])
                    }
                    Tile {
                        glyph: cc.st.theme === "graphite-light" ? "󰖨" : "󰖔"; label: "Theme"
                        on: cc.st.theme === "graphite-light"
                        sub: cc.st.theme === "graphite-light" ? "Light" : "Dark"
                        onClicked: cc.act(["theme-toggle"])
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Network settings"; color: Colors.accent; font.pixelSize: 12
                        MouseArea { anchors.fill: parent; onClicked: { cc.close(); Quickshell.execDetached(["kitty", "--class", "nmtui", "-e", "nmtui"]); } } }
                    Item { Layout.fillWidth: true }
                    Text { text: "Sound settings"; color: Colors.accent; font.pixelSize: 12
                        MouseArea { anchors.fill: parent; onClicked: { cc.close(); Quickshell.execDetached(["pavucontrol"]); } } }
                }
            }
        }
    }
    HyprlandFocusGrab { windows: [panel]; active: panel.visible; onCleared: cc.close() }

    IpcHandler {
        target: "control"
        function toggle(): void { cc.opened ? cc.close() : cc.open() }
        function open(): void { cc.open() }
        function close(): void { cc.close() }
        function isOpen(): bool { return cc.opened }
    }
}
