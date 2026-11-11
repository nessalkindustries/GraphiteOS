// graphite-agent: managed copy (graphite-agent toggle refreshes this file from
// /usr/share/graphite-agent/quickshell; delete this line to keep your own edits).
// Graphite Agent panel (Stage 1, Super+Shift+A): read-only local assistant.
// Every question goes through `graphite-agent ask --jsonl` (llama.cpp on 127.0.0.1); this
// window holds no model, no memory and no tools of its own. Colors.qml is the theme palette.
// Window title "Graphite Agent"; IPC target "agent" (ask/stop/state/quit).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root
    property var st: ({})            // graphite-agent status --json
    property string answer: ""
    property string question: ""
    property string note: ""
    property bool busy: ask.running

    function send(q) {
        q = q.trim();
        if (!q.length || ask.running) return;
        root.question = q; root.answer = ""; root.note = "";
        ask.command = ["graphite-agent", "ask", "--jsonl", q];
        ask.running = true;
    }
    // model output stays PlainText (rich text could load remote images); drop markdown markup
    function plain(t) {
        return t.replace(/\*\*(.+?)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1")
                .replace(/^#{1,6}\s+/gm, "").replace(/^\s*[-*]\s+/gm, "• ");
    }
    function stop() {
        if (ask.running) { ask.signal(15); ask.running = false; }
        cancelP.running = true;      // belt and braces: no answer keeps running in the background
        root.note = "Stopped.";
    }

    Process { id: ask
        stdout: SplitParser { onRead: data => {
            let m; try { m = JSON.parse(data); } catch (e) { return; }
            if (m.type === "token") root.answer += m.text;
            else if (m.type === "status") root.note = m.text;
            else if (m.type === "tool") root.note = (m.ok ? "Checked " : "Refused tool ") + m.name;
            else if (m.type === "error") root.note = m.text;
            else if (m.type === "done" && root.note.startsWith("Checked")) root.note = "";
        } }
        onExited: (code) => { if (code !== 0 && !root.note.length) root.note = "The agent stopped (exit " + code + ")."; statusP.running = true; }
    }
    Process { id: cancelP; command: ["graphite-agent", "cancel"] }
    Process { id: unloadP; command: ["graphite-agent", "unload"]; onExited: { root.note = "Model unloaded; memory freed."; statusP.running = true; } }
    Process { id: setupP; command: ["kitty", "--title", "Graphite Agent: set up model", "sh", "-c", "graphite-agent setup-model; echo; read -r -p 'Press Enter to close' _"]
        onExited: statusP.running = true }
    Process { id: statusP; command: ["graphite-agent", "status", "--json"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { root.st = JSON.parse(this.text); } catch (e) {} } } }
    Timer { interval: 3000; repeat: true; running: true; onTriggered: if (!statusP.running) statusP.running = true }

    IpcHandler {
        target: "agent"
        function ask(q: string): void { root.send(q); }
        function stop(): void { root.stop(); }
        function state(): string { return root.busy ? "busy" : (root.st.server || "unknown"); }
        function quit(): void { Qt.quit(); }
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool on: false
        signal clicked()
        implicitWidth: Math.max(80, t.implicitWidth + 24); implicitHeight: 32; radius: 8
        color: on ? Colors.accent : (m.containsMouse ? Colors.overlay : Colors.surface)
        border.color: Colors.overlay; border.width: on ? 0 : 1
        Text { id: t; anchors.centerIn: parent; text: b.label; font.pixelSize: 13; color: b.on ? Colors.accentText : Colors.foreground }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }

    FloatingWindow {
        id: win
        title: "Graphite Agent"
        implicitWidth: 560; implicitHeight: 480
        color: Colors.background
        onClosed: { root.stop(); Qt.quit(); }

        ColumnLayout {
            anchors { fill: parent; margins: 18 } spacing: 12

            RowLayout { Layout.fillWidth: true; spacing: 10
                Text { text: "Graphite Agent"; color: Colors.foreground; font.pixelSize: 20; font.bold: true }
                Item { Layout.fillWidth: true }
                Rectangle {   // local / offline indicator + model state
                    implicitHeight: 26; implicitWidth: pill.implicitWidth + 22; radius: 13
                    color: Colors.surface; border.color: Colors.overlay; border.width: 1
                    Row { id: pill; anchors.centerIn: parent; spacing: 6
                        Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                            color: !root.st.model ? Colors.red : (root.st.server === "ready" ? Colors.accent : Colors.muted) }
                        Text { color: Colors.foreground; font.pixelSize: 12
                            text: "Local model · offline" + (!root.st.model ? " · no model" : root.st.server === "ready" ? "" : root.st.server === "loading" ? " · loading" : " · unloaded") } }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 38; radius: 8; color: Colors.surface; border.color: Colors.overlay; border.width: 1
                TextInput { id: q; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter
                    color: Colors.foreground; font.pixelSize: 14; clip: true; focus: true
                    onAccepted: { root.send(text); text = ""; }
                    Keys.onEscapePressed: root.busy ? root.stop() : Qt.quit()
                    Text { visible: !q.text.length; anchors.verticalCenter: parent.verticalCenter; color: Colors.muted; font.pixelSize: 14
                        text: root.st.model === false ? "The model is missing: Set up model… below" : "Ask about Graphite or this computer (Enter)" } } }

            Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: 8; color: Colors.surface; clip: true
                Flickable { id: fl; anchors { fill: parent; margins: 12 } contentHeight: col.implicitHeight; clip: true
                    onContentHeightChanged: if (root.busy) contentY = Math.max(0, contentHeight - height)
                    ColumnLayout { id: col; width: fl.width; spacing: 8
                        Text { visible: root.question.length > 0; text: root.question; color: Colors.muted; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Text { text: root.answer.length ? root.plain(root.answer) : (root.question.length ? (root.busy ? "Thinking…" : "") :
                                     "I can tell you your Graphite version, free disk space, memory and uptime, and help with keybinds and settings. I can't change anything on this computer.")
                               color: root.answer.length ? Colors.foreground : Colors.muted; font.pixelSize: 14; wrapMode: Text.Wrap; textFormat: Text.PlainText; Layout.fillWidth: true }
                    } } }

            RowLayout { Layout.fillWidth: true; spacing: 8
                Btn { label: root.busy ? "Stop" : "Ask"; on: root.busy; onClicked: root.busy ? root.stop() : (root.send(q.text), q.text = "") }
                Btn { label: "Unload model"; visible: !!root.st.model && root.st.server !== "down"; onClicked: { root.stop(); unloadP.running = true; } }
                Btn { label: "Set up model…"; visible: root.st.model === false; onClicked: if (!setupP.running) setupP.running = true }
                Text { text: root.note; color: Colors.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
    }
}
