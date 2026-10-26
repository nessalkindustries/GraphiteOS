// Graphite launcher (Quickshell): apps, calculator and commands in one search box.
// Super+Space / Super+D run `graphite-launcher`, which toggles this through IPC
// (`qs ipc -c graphite-bar call launcher toggle`); without Quickshell it falls back to rofi.
//   type to search apps (name, generic name, keywords) and Graphite commands
//   = 2*(3+4)  or just 2*(3+4)   calculator; Enter copies the result
//   > text      commands only; "Run: text" runs any shell command
// Layer namespace "graphite-launcher".
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: launcher
    property string query: ""
    property var results: []
    property int current: 0
    property var themes: []

    visible: false
    color: "transparent"
    // only the box's size, not a full-screen overlay: a full-screen transparent layer made
    // every redraw (the cursor blinks) recomposite the whole screen, which starved the
    // compositor under software rendering and could leave the launcher slow to appear
    anchors.top: true
    margins.top: Math.round((screen ? screen.height : 800) * 0.2)
    implicitWidth: 560; implicitHeight: 470
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function run(cmd) { Quickshell.execDetached(["sh", "-c", cmd]) }
    function open() { query = ""; input.text = ""; refresh(); themeList.running = true; visible = true; input.forceActiveFocus() }
    function close() { visible = false }
    function toggle() { visible ? close() : open() }

    // ---- built-in commands (label, icon name, shell command) ----
    readonly property var commands: [
        { name: "Lock screen", icon: "system-lock-screen", cmd: "hyprlock" },
        { name: "Power menu", icon: "system-shutdown", cmd: "graphite-menu power" },
        { name: "Log out", icon: "system-log-out", cmd: "hyprctl dispatch exit" },
        { name: "Reboot", icon: "system-reboot", cmd: "systemctl reboot" },
        { name: "Shut down", icon: "system-shutdown", cmd: "systemctl poweroff" },
        { name: "Update system", icon: "system-software-update", cmd: "kitty --hold graphite update" },
        { name: "Graphite doctor", icon: "utilities-terminal", cmd: "kitty --hold graphite doctor" },
        { name: "Keybinds", icon: "preferences-desktop-keyboard", cmd: "graphite-keybinds" },
        { name: "Clipboard history", icon: "edit-paste", cmd: "graphite-menu clipboard" },
        { name: "Emoji picker", icon: "face-smile", cmd: "graphite-menu emoji" },
        { name: "Screenshot region", icon: "applets-screenshooter", cmd: "sleep 0.3; grim -g \"$(slurp)\" - | wl-copy" },
        { name: "Screenshot screen", icon: "applets-screenshooter", cmd: "sleep 0.3; grim - | wl-copy" },
        { name: "Switch bar to Waybar", icon: "preferences-desktop", cmd: "graphite bar waybar" },
        { name: "Switch bar to Quickshell", icon: "preferences-desktop", cmd: "graphite bar quickshell" }
    ]
    Component.onCompleted: themeList.running = true
    Process {
        id: themeList
        command: ["graphite-theme", "list"]
        stdout: StdioCollector {
            onStreamFinished: launcher.themes = this.text.split("\n").map(s => s.replace(/^[*\s]+/, "").trim()).filter(s => s && !/\s/.test(s))
        }
    }

    // ---- calculator: a small parser (no eval): + - * / % ^, brackets, sqrt abs ln log sin cos tan round floor ceil, pi e ----
    function calc(q) {
        const src = q.replace(/^=\s*/, "").trim().toLowerCase();
        if (!src || !/^[0-9a-z.+\-*/%^()\s]+$/.test(src)) return null;
        if (q[0] !== "=" && !/[0-9)]\s*[-+*/%^]\s*[-0-9(a-z.]|^[a-z]+\s*\(/.test(src)) return null;
        const toks = src.match(/\d*\.?\d+(e[-+]?\d+)?|[a-z]+|[-+*/%^()]/g);
        if (!toks || toks.join("") !== src.replace(/\s+/g, "")) return null;
        const fns = { sqrt: Math.sqrt, abs: Math.abs, ln: Math.log, log: Math.log10, sin: Math.sin, cos: Math.cos,
                      tan: Math.tan, round: Math.round, floor: Math.floor, ceil: Math.ceil };
        let p = 0;
        const peek = () => toks[p], eat = t => { if (toks[p] !== t) throw "syntax"; p++ };
        function expr() { let v = term(); while (peek() === "+" || peek() === "-") v = toks[p++] === "+" ? v + term() : v - term(); return v }
        function term() { let v = unary(); while (peek() === "*" || peek() === "/" || peek() === "%") { const o = toks[p++], r = unary(); v = o === "*" ? v * r : o === "/" ? v / r : v % r } return v }
        function unary() { if (peek() === "-") { p++; return -unary() } if (peek() === "+") { p++; return unary() } return power() }
        function power() { const b = atom(); if (peek() === "^") { p++; return Math.pow(b, unary()) } return b }
        function atom() {
            const t = toks[p++];
            if (t === undefined) throw "end";
            if (t === "(") { const v = expr(); eat(")"); return v }
            if (/^[\d.]/.test(t)) return parseFloat(t);
            if (t === "pi") return Math.PI;
            if (t === "e") return Math.E;
            if (fns[t]) { eat("("); const v = expr(); eat(")"); return fns[t](v) }
            throw "token";
        }
        try {
            const v = expr();
            if (p !== toks.length || !isFinite(v)) return null;
            return String(Math.round(v * 1e10) / 1e10);
        } catch (err) { return null }
    }

    function score(hay, q) {
        // several words: every word has to match, the weakest match counts
        const ws = q.split(/\s+/).filter(w => w);
        if (ws.length > 1) return Math.min(...ws.map(w => score1(hay, w))) - 5;
        return score1(hay, q);
    }
    function score1(hay, q) {
        hay = (hay || "").toLowerCase();
        if (!hay) return 0;
        if (hay === q) return 100;
        if (hay.startsWith(q)) return 80;
        if (hay.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 60;
        return hay.includes(q) ? 40 : 0;
    }

    function refresh() {
        const raw = query.trim(), out = [];
        const cmdOnly = raw.startsWith(">"), q = (cmdOnly ? raw.slice(1) : raw).trim().toLowerCase();
        const c = cmdOnly ? null : calc(raw);
        if (c !== null) out.push({ kind: "calc", name: c, sub: "Calculator: Enter copies the result", icon: "accessories-calculator", score: 1000, value: c });
        if (!cmdOnly) {
            for (const a of DesktopEntries.applications.values) {
                if (a.noDisplay) continue;
                let s = 1;
                if (q) {
                    s = Math.max(score(a.name, q), score(a.genericName, q) - 10);
                    const kw = a.keywords || [];
                    for (let k = 0; k < kw.length; k++) s = Math.max(s, score(kw[k], q) - 20);
                }
                if (s > 0) out.push({ kind: "app", name: a.name, sub: a.genericName || a.comment || "", icon: a.icon, score: s + 5, entry: a });
            }
        }
        const cmds = launcher.commands.concat(launcher.themes.map(t => ({ name: "Theme: " + t, icon: "preferences-desktop-theme", cmd: "graphite-theme set " + t })));
        for (const m of cmds) {
            const s = q ? score(m.name, q) : (cmdOnly ? 1 : 0);
            if (s > 0) out.push({ kind: "cmd", name: m.name, sub: "Command", icon: m.icon, score: s, cmd: m.cmd });
        }
        if (cmdOnly && q) out.push({ kind: "cmd", name: "Run: " + raw.slice(1).trim(), sub: "Shell command", icon: "utilities-terminal", score: -1, cmd: raw.slice(1).trim() });
        out.sort((x, y) => y.score - x.score || x.name.localeCompare(y.name));
        results = out.slice(0, 60);
        current = 0;
    }

    function activate(i) {
        const r = results[i];
        if (!r) return;
        close();
        if (r.kind === "app") r.entry.execute();
        else if (r.kind === "calc") Quickshell.execDetached(["wl-copy", r.value]);
        else run(r.cmd);
    }

    // `qs ipc -c graphite-bar call launcher toggle|open|close|query TEXT`
    IpcHandler {
        target: "launcher"
        function toggle(): void { launcher.toggle() }
        function open(): void { launcher.open() }
        function close(): void { launcher.close() }
        function isOpen(): bool { return launcher.visible }
        // for tests and scripts: search without the UI, returns "kind: name" of the top result
        function query(text: string): string {
            launcher.query = text; launcher.refresh();
            const r = launcher.results[0];
            return r ? r.kind + ": " + r.name : "none";
        }
    }

    // click outside the launcher closes it
    HyprlandFocusGrab { windows: [launcher]; active: launcher.visible; onCleared: launcher.close() }

    Rectangle {
        id: box
        width: 560; height: Math.min(470, 64 + list.contentHeight)
        anchors.horizontalCenter: parent.horizontalCenter
        y: 0
        radius: 16; color: Colors.background; border.color: Colors.accent; border.width: 2
        MouseArea { anchors.fill: parent }   // swallow clicks inside the box

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 8
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 40; radius: 10; color: Colors.surface
                TextInput {
                    id: input
                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: Colors.foreground; selectionColor: Colors.accent; font.pixelSize: 16
                    focus: true
                    onTextChanged: { launcher.query = text; launcher.refresh() }
                    Text {
                        visible: !input.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search apps, = calculate, > commands"
                        color: Colors.muted; font.pixelSize: 16
                    }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Escape) { launcher.close(); ev.accepted = true }
                        else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) { launcher.current = Math.min(launcher.results.length - 1, launcher.current + 1); ev.accepted = true }
                        else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) { launcher.current = Math.max(0, launcher.current - 1); ev.accepted = true }
                        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { launcher.activate(launcher.current); ev.accepted = true }
                    }
                }
            }
            ListView {
                id: list
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; spacing: 2
                model: launcher.results
                currentIndex: launcher.current
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width; height: 44; radius: 10
                    color: index === launcher.current ? Colors.overlay : "transparent"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 10
                        IconImage {
                            implicitSize: 26
                            source: Quickshell.iconPath(modelData.icon || "", "application-x-executable")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            Text { text: modelData.name; color: Colors.foreground; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: modelData.sub; visible: text !== ""; color: Colors.muted; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onEntered: launcher.current = index
                        onClicked: launcher.activate(index)
                    }
                }
            }
        }
    }
}
