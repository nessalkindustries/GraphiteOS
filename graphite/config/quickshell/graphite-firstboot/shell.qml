// Graphite first-boot setup (desk-7). Opened by `graphite-firstboot auto` at login until
// Finish or Skip; every action goes through graphite-firstboot / graphite-theme.
// Window title "Graphite Setup"; IPC target "firstboot" (step/next/current/quit).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root
    property int step: 0
    readonly property var steps: ["Theme", "Wallpaper", "Privacy", "Profiles", "Secure Boot"]
    property var themes: []
    property string theme: ""
    property var walls: []
    property string wall: ""
    property var priv: ({})
    property var profs: ({})
    property string sb: ""
    property string msg: ""

    function kv(t) { const o = {}; for (const l of t.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); } return o; }
    function run(cmd, note) { act.command = cmd; msg = note || ""; act.running = true; }
    function reload() { themeP.running = true; privP.running = true; profP.running = true; }

    Process { id: themeP; command: ["graphite-theme", "list"]; running: true
        stdout: StdioCollector { onStreamFinished: {
            const l = this.text.split("\n").filter(x => x.length > 2);
            root.themes = l.map(x => x.slice(2)); const c = l.find(x => x[0] === "*"); root.theme = c ? c.slice(2) : ""; } } }
    Process { id: wallP; command: ["graphite-firstboot", "wallpapers"]; running: true
        stdout: StdioCollector { onStreamFinished: root.walls = this.text.split("\n").filter(x => x.length) } }
    Process { id: privP; command: ["graphite-firstboot", "privacy", "get"]; running: true
        stdout: StdioCollector { onStreamFinished: root.priv = root.kv(this.text) } }
    Process { id: profP; command: ["graphite-firstboot", "profiles"]; running: true
        stdout: StdioCollector { onStreamFinished: root.profs = root.kv(this.text) } }
    Process { id: sbP; command: ["graphite-firstboot", "secureboot"]; running: true
        stdout: StdioCollector { onStreamFinished: root.sb = this.text.trim() } }
    Process { id: act; onExited: (code) => { root.msg = code === 0 ? "Done" : "Failed (exit " + code + ")"; root.reload(); } }
    Process { id: finP; command: ["graphite-firstboot", "finish"] }

    IpcHandler {
        target: "firstboot"
        function step(n: int): void { root.step = Math.max(0, Math.min(4, n)); }
        function next(): void { if (root.step < 4) root.step++; }
        function current(): string { return root.steps[root.step]; }
        function quit(): void { Qt.quit(); }
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool on: false
        property bool primary: false
        signal clicked()
        implicitWidth: Math.max(96, t.implicitWidth + 28); implicitHeight: 36; radius: 9
        color: (on || primary) ? Colors.accent : (m.containsMouse ? Colors.overlay : Colors.surface)
        Text { id: t; anchors.centerIn: parent; text: b.label; font.pixelSize: 14; color: (b.on || b.primary) ? Colors.accentText : Colors.foreground }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }
    component Toggle: RowLayout {
        id: tg
        property string key: ""
        property string label: ""
        property string hint: ""
        Layout.fillWidth: true; spacing: 16
        ColumnLayout { Layout.fillWidth: true; spacing: 2
            Text { text: tg.label; color: Colors.foreground; font.pixelSize: 15 }
            Text { text: tg.hint; color: Colors.muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true } }
        Btn { label: "On"; on: root.priv[tg.key] === "on"; onClicked: root.run(["graphite-firstboot", "privacy", "set", tg.key, "on"]) }
        Btn { label: "Off"; on: root.priv[tg.key] === "off"; onClicked: root.run(["graphite-firstboot", "privacy", "set", tg.key, "off"]) }
    }

    FloatingWindow {
        title: "Graphite Setup"
        implicitWidth: 820; implicitHeight: 560
        color: Colors.background
        onClosed: Qt.quit()

        ColumnLayout {
            anchors { fill: parent; margins: 28 } spacing: 18
            Text { text: "Welcome to Graphite"; color: Colors.foreground; font.pixelSize: 26; font.bold: true }
            RowLayout { spacing: 8   // step indicator
                Repeater { model: root.steps
                    Rectangle { required property string modelData; required property int index
                        implicitWidth: lbl.implicitWidth + 24; implicitHeight: 28; radius: 14
                        color: index === root.step ? Colors.accent : (index < root.step ? Colors.overlay : Colors.surface)
                        Text { id: lbl; anchors.centerIn: parent; text: (index + 1) + ". " + modelData; font.pixelSize: 12
                               color: index === root.step ? Colors.accentText : Colors.foreground }
                        MouseArea { anchors.fill: parent; onClicked: root.step = index } } } }

            Item { Layout.fillWidth: true; Layout.fillHeight: true
                // 1. Theme
                ColumnLayout { anchors.fill: parent; visible: root.step === 0; spacing: 12
                    Text { text: "Pick a theme. It colors the bar, terminal, launcher and notifications; change it later with Super+T or Settings (Super+I)."; color: Colors.muted; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Flow { Layout.fillWidth: true; spacing: 8
                        Repeater { model: root.themes
                            Btn { required property string modelData; label: modelData; on: root.theme === modelData
                                  onClicked: root.run(["graphite-theme", "set", modelData], "Applying " + modelData + "…") } } } }
                // 2. Wallpaper
                ColumnLayout { anchors.fill: parent; visible: root.step === 1; spacing: 12
                    Text { text: "Pick a wallpaper. Graphite builds a matching color theme from it (you can go back to a regular theme any time)."; color: Colors.muted; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Flow { Layout.fillWidth: true; spacing: 12
                        Repeater { model: root.walls
                            Rectangle { required property string modelData
                                width: 168; height: 105; radius: 8; color: Colors.surface
                                border.width: root.wall === modelData ? 3 : 0; border.color: Colors.accent
                                Image { anchors { fill: parent; margins: 4 } source: "file://" + modelData; fillMode: Image.PreserveAspectCrop; asynchronous: true; sourceSize.width: 320 }
                                MouseArea { anchors.fill: parent; onClicked: { root.wall = modelData; root.run(["graphite-theme", "from-wallpaper", modelData], "Building a theme from the wallpaper…"); } } } } }
                    Text { visible: root.walls.length === 0; text: "No bundled wallpapers found."; color: Colors.muted } }
                // 3. Privacy
                ColumnLayout { anchors.fill: parent; visible: root.step === 2; spacing: 16
                    Text { text: "Graphite sends no telemetry. These are the only things that store history or go online on their own:"; color: Colors.muted; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Toggle { key: "news"; label: "Arch news check"; hint: "'graphite update' fetches archlinux.org/news before upgrading" }
                    Toggle { key: "clipboard"; label: "Clipboard history"; hint: "cliphist keeps copied text (turning it off also wipes it)" }
                    Toggle { key: "recent"; label: "Recent files"; hint: "GTK apps remember recently opened files" }
                    Item { Layout.fillHeight: true } }
                // 4. Profiles
                ColumnLayout { anchors.fill: parent; visible: root.step === 3; spacing: 14
                    Text { text: "Optional package profiles from the signed Graphite repo. Installing opens a terminal and asks for your password."; color: Colors.muted; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Repeater { model: [["gaming", "Gaming", "Steam, gamemode, MangoHud, Wine/Proton, gamescope session"], ["creator", "Creator", "OBS Studio, screen capture, hardware encoding"], ["dev", "Developer", "compilers, containers, editors"], ["nvidia", "NVIDIA", "proprietary NVIDIA driver stack (only for NVIDIA GPUs)"]]
                        RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 16
                            ColumnLayout { Layout.fillWidth: true; spacing: 2
                                Text { text: modelData[1]; color: Colors.foreground; font.pixelSize: 15 }
                                Text { text: modelData[2]; color: Colors.muted; font.pixelSize: 12 } }
                            Btn { label: root.profs[modelData[0]] === "installed" ? "Installed" : "Install"; on: root.profs[modelData[0]] === "installed"
                                  onClicked: if (root.profs[modelData[0]] !== "installed") root.run(["graphite-firstboot", "profile", modelData[0]], "Opening a terminal…") } } }
                    Item { Layout.fillHeight: true } }
                // 5. Secure Boot
                ColumnLayout { anchors.fill: parent; visible: root.step === 4; spacing: 14
                    Text { text: root.sb; color: Colors.foreground; font.pixelSize: 15; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Text { text: "Secure Boot is opt-in on Graphite: it signs your own boot chain with sbctl. Run 'graphite secureboot plan' to see the steps first."; color: Colors.muted; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Text { text: "You can reopen this setup with 'graphite firstboot open'. Settings: Super+I · Keybindings: Super+K"; color: Colors.muted; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true } }
            }

            RowLayout { Layout.fillWidth: true; spacing: 10
                Btn { label: "Skip setup"; onClicked: finP.running = true }
                Text { text: root.msg; color: Colors.muted; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                Btn { label: "Back"; visible: root.step > 0; onClicked: root.step-- }
                Btn { label: root.step < 4 ? "Next" : "Finish"; primary: true; onClicked: root.step < 4 ? root.step++ : finP.running = true }
            }
        }
    }
}
