// graphite-agent: managed copy (graphite-agent toggle refreshes this file from
// /usr/share/graphite-agent/quickshell; delete this line to keep your own edits).
// Graphite Agent panel (Super+Shift+A): local assistant. Tabs: Ask, Notes (what it may remember,
// with Forget / Export) and History (changes with Undo, recent questions). A change the model
// proposes shows as a card with exactly what will happen; only Approve here runs it
// (`graphite-agent approve ID`, snapshot first), and Undo reverses it.
// Every request goes through the `graphite-agent` CLI, which talks to the session daemon
// (llama.cpp on 127.0.0.1); this window holds no model, no memory and no tools of its own.
// Colors.qml is the theme palette.
// Several agents (Stage 5): the line under the answer shows which specialist did what
// ("System: ✓ os_release → Settings: ✓ change_setting"); History shows them per question.
// Grok tier (Stage 6, off by default): the Grok tab takes your own xAI API key (password field,
// handed to `graphite-agent cloud key` on stdin, stored in your keyring or a 0600 file) and the
// on/off switch. While an answer goes to the cloud the header pill turns amber: "Grok · cloud".
// Window title "Graphite Agent"; IPC target "agent" (ask/stop/state/tab/quit).
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
    property string tab: "ask"
    property var notesList: []
    property var historyList: []
    property string cited: ""
    property var steps: []
    property string via: ""             // this answer: "cloud" | "local" | "" (Grok tier off)
    property string viaWhy: ""          // why it stayed / went back local
    property var cl: st.cloud || ({})
    readonly property color amber: "#e0a030"   // cloud indicator (same in every theme: "leaves this computer")
    property string agentNow: ""        // label of the agent working on the current hop
    property var agentNames: ({"system": "System", "settings": "Settings", "software": "Software", "notes": "Notes", "help": "Help", "general": "Assistant"})
    property var acts: []
    property var pending: acts.filter(a => a.state === "awaiting_approval")
    property bool acting: actP.running
    property string phase: ""          // voice input: "" | "listening" | "transcribing"
    property int heardFor: 0           // seconds listened so far
    property bool spoken: false        // the last question was spoken: read the answer aloud
    property bool speaking: sayP.running

    function refresh() { if (!notesP.running) notesP.running = true; if (!histP.running) histP.running = true; if (!actsP.running) actsP.running = true; }
    function decide(verb, id) { if (actP.running) return; actP.command = ["graphite-agent", verb, String(id), "--jsonl"]; actP.running = true; }
    function run(cmd) { act.command = cmd; act.running = true; }

    function send(q, byVoice) {
        q = q.trim();
        if (!q.length || ask.running) return;
        root.spoken = !!byVoice; root.shutUp();
        root.question = q; root.answer = ""; root.note = ""; root.cited = ""; root.steps = []; root.agentNow = ""; root.via = ""; root.viaWhy = "";
        ask.command = ["graphite-agent", "ask", "--jsonl", q];
        ask.running = true;
    }
    // model output stays PlainText (rich text could load remote images); drop markdown markup
    function plain(t) {
        return t.replace(/\*\*(.+?)\*\*/g, "$1").replace(/`([^`]+)`/g, "$1")
                .replace(/^#{1,6}\s+/gm, "").replace(/^\s*[-*]\s+/gm, "• ");
    }
    // voice: audio stays in RAM (XDG_RUNTIME_DIR) and is deleted once transcribed
    function listen() {
        if (listenP.running) { if (root.phase === "listening") listenP.signal(2); return; }
        if (ask.running || !root.st.stt) return;
        root.shutUp(); root.tab = "ask"; root.note = ""; root.heardFor = 0; root.phase = "listening";
        listenP.running = true;
    }
    function say(t) { root.shutUp(); sayP.command = ["graphite-agent", "say", root.plain(t)]; sayP.running = true; }
    function shutUp() { if (sayP.running) sayP.signal(15); }
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
            else if (m.type === "backend") { root.via = m.name; root.viaWhy = m.reason || ""; if (m.name === "local" && m.reason) root.note = "On this computer: " + m.reason; }
            else if (m.type === "plan") { if (m.fallback) root.note = "Plan didn't parse: one agent answers"; }
            else if (m.type === "agent") { root.agentNow = m.label; root.note = m.label + " agent" + (m.of > 1 ? " (" + m.n + "/" + m.of + ")" : "") + "…";
                root.steps = root.steps.concat([(root.steps.length ? "→ " : "") + m.label + ":"]); }
            else if (m.type === "tool") { root.note = (m.ok ? "Checked " : "Refused tool ") + m.name; root.steps = root.steps.concat([(m.ok ? "✓ " : "✗ ") + m.name]); }
            else if (m.type === "notes") root.cited = m.ids.join(", ");
            else if (m.type === "action") root.refresh();
            else if (m.type === "cancelled") root.note = "Stopped.";
            else if (m.type === "error") root.note = m.text;
            else if (m.type === "done" && root.note.startsWith("Checked")) root.note = "";
        } }
        onExited: (code) => { if (code !== 0 && code !== 130 && !root.note.length) root.note = "The agent stopped (exit " + code + ")."; statusP.running = true; root.refresh();
            if (code === 0 && root.spoken && root.answer.length && root.st.tts) root.say(root.answer); }
    }
    Process { id: listenP; command: ["graphite-agent", "listen", "--jsonl"]
        stdout: SplitParser { onRead: data => {
            let m; try { m = JSON.parse(data); } catch (e) { return; }
            if (m.type === "listening") root.phase = "listening";
            else if (m.type === "transcribing") root.phase = "transcribing";
            else if (m.type === "heard") { root.phase = ""; root.send(m.text, true); }
            else if (m.type === "error") root.note = m.text;
        } }
        onExited: root.phase = "" }
    Timer { interval: 1000; repeat: true; running: root.phase === "listening"; onTriggered: root.heardFor += 1 }
    Process { id: sayP }
    Process { id: cancelP; command: ["graphite-agent", "cancel"] }
    Process { id: unloadP; command: ["graphite-agent", "unload"]; onExited: { root.note = "Model unloaded; memory freed."; statusP.running = true; } }
    Process { id: setupP; command: ["kitty", "--title", "Graphite Agent: set up model", "sh", "-c", "graphite-agent setup-model; echo; read -r -p 'Press Enter to close' _"]
        onExited: statusP.running = true }
    Process { id: statusP; command: ["graphite-agent", "status", "--json"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { root.st = JSON.parse(this.text); } catch (e) {} } } }
    Process { id: notesP; command: ["graphite-agent", "notes", "--json"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { root.notesList = JSON.parse(this.text); } catch (e) {} } } }
    Process { id: histP; command: ["graphite-agent", "history", "--json", "15"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { root.historyList = JSON.parse(this.text); } catch (e) {} } } }
    Process { id: actsP; command: ["graphite-agent", "actions", "--json"]; running: true
        stdout: StdioCollector { onStreamFinished: { try { root.acts = JSON.parse(this.text); } catch (e) {} } } }
    Process { id: actP   // approve / deny / undo: the only way a proposed change runs
        stdout: SplitParser { onRead: data => {
            let m; try { m = JSON.parse(data); } catch (e) { return; }
            if (m.type === "status" || m.type === "result" || m.type === "error") root.note = m.text;
        } }
        onExited: root.refresh() }
    Process { id: keyP   // the API key goes to the CLI on stdin, never as an argument
        command: ["graphite-agent", "cloud", "key"]; stdinEnabled: true
        onStarted: { write(keyIn.text.trim() + "\n"); keyIn.text = ""; stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: { if (this.text.trim().length) root.note = this.text.trim(); } }
        stderr: StdioCollector { onStreamFinished: { if (this.text.trim().length) root.note = this.text.trim(); } }
        onExited: { stdinEnabled = true; statusP.running = true; } }
    Process { id: act   // one short CLI action (remember / forget / export / history on|off|clear)
        stdout: StdioCollector { onStreamFinished: { if (this.text.trim().length) root.note = this.text.trim().split("\n").pop(); } }
        stderr: StdioCollector { onStreamFinished: { if (this.text.trim().length) root.note = this.text.trim(); } }
        onExited: { root.refresh(); statusP.running = true; } }
    Timer { interval: 3000; repeat: true; running: true; onTriggered: if (!statusP.running) statusP.running = true }

    IpcHandler {
        target: "agent"
        function ask(q: string): void { root.send(q); }
        function stop(): void { root.stop(); }
        function state(): string { return root.busy ? "busy" : (root.st.server || "unknown"); }
        function voice(): void { root.listen(); }
        function tab(t: string): void { if (["ask", "notes", "history", "grok"].indexOf(t) >= 0) { root.tab = t; root.refresh(); } }
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
        implicitWidth: 600; implicitHeight: 540
        color: Colors.background
        onClosed: { if (listenP.running) listenP.signal(2); root.shutUp(); root.stop(); Qt.quit(); }

        ColumnLayout {
            anchors { fill: parent; margins: 18 } spacing: 12

            RowLayout { Layout.fillWidth: true; spacing: 10
                Text { text: "Graphite Agent"; color: Colors.foreground; font.pixelSize: 20; font.bold: true }
                Item { Layout.fillWidth: true }
                Rectangle {   // microphone indicator: visible whenever the mic is recording
                    visible: root.phase !== ""; implicitHeight: 26; implicitWidth: mic.implicitWidth + 22; radius: 13
                    color: root.phase === "listening" ? Colors.red : Colors.surface; border.color: Colors.overlay; border.width: 1
                    Row { id: mic; anchors.centerIn: parent; spacing: 6
                        Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: Colors.background; visible: root.phase === "listening" }
                        Text { color: root.phase === "listening" ? Colors.background : Colors.foreground; font.pixelSize: 12; font.bold: root.phase === "listening"
                            text: root.phase === "listening" ? "Mic on · " + root.heardFor + " s / 30 s" : "Transcribing…" } }
                }
                Rectangle {   // cloud indicator: amber whenever the current answer goes to xAI
                    visible: root.via === "cloud" || (root.via === "" && !!root.cl.enabled)
                    implicitHeight: 26; implicitWidth: cloudPill.implicitWidth + 22; radius: 13
                    color: root.via === "cloud" ? root.amber : Colors.surface; border.color: root.amber; border.width: 1
                    Text { id: cloudPill; anchors.centerIn: parent; font.pixelSize: 12; font.bold: root.via === "cloud"
                        color: root.via === "cloud" ? Colors.background : Colors.foreground
                        text: root.via === "cloud" ? "☁ Grok · cloud · " + root.cl.model : "Grok tier on · " + (root.cl.used_today || 0) + "/" + root.cl.cap + " today" } }
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

            RowLayout { Layout.fillWidth: true; spacing: 6
                Btn { label: "Ask"; on: root.tab === "ask"; onClicked: root.tab = "ask" }
                Btn { label: "Notes (" + root.notesList.length + ")"; on: root.tab === "notes"; onClicked: { root.tab = "notes"; root.refresh(); } }
                Btn { label: "History"; on: root.tab === "history"; onClicked: { root.tab = "history"; root.refresh(); } }
                Btn { label: root.cl.enabled ? "Grok ☁" : "Grok"; on: root.tab === "grok"; onClicked: { root.tab = "grok"; statusP.running = true; } }
                Item { Layout.fillWidth: true }
            }

            StackLayout { Layout.fillWidth: true; Layout.fillHeight: true
                currentIndex: ["ask", "notes", "history", "grok"].indexOf(root.tab)

            ColumnLayout { spacing: 12   // Ask
            Rectangle { Layout.fillWidth: true; implicitHeight: 38; radius: 8; color: Colors.surface; border.color: Colors.overlay; border.width: 1
                TextInput { id: q; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter
                    color: Colors.foreground; font.pixelSize: 14; clip: true; focus: true
                    onAccepted: { root.send(text); text = ""; }
                    Keys.onEscapePressed: listenP.running ? root.listen() : root.speaking ? root.shutUp() : root.busy ? root.stop() : Qt.quit()
                    Text { visible: !q.text.length; anchors.verticalCenter: parent.verticalCenter; color: Colors.muted; font.pixelSize: 14
                        text: root.st.model === false ? "The model is missing: Set up model… below"
                            : root.phase === "listening" ? "Listening… speak now, then Stop (or Esc)"
                            : "Ask about Graphite or this computer (Enter)" + (root.st.stt ? ", or Speak" : "") } } }

            Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: 8; color: Colors.surface; clip: true
                Flickable { id: fl; anchors { fill: parent; margins: 12 } contentHeight: col.implicitHeight; clip: true
                    onContentHeightChanged: if (root.busy) contentY = Math.max(0, contentHeight - height)
                    ColumnLayout { id: col; width: fl.width; spacing: 8
                        Text { visible: root.question.length > 0; text: root.question; color: Colors.muted; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Text { visible: root.via !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 12; font.bold: root.via === "cloud"
                            color: root.via === "cloud" ? root.amber : Colors.muted
                            text: root.via === "cloud" ? "☁ Sent to Grok in the cloud (xAI, " + root.cl.model + "). Notes and file contents stay here unless you allowed them."
                                                       : "Answered on this computer" + (root.viaWhy ? ": " + root.viaWhy : "") }
                        Text { text: root.answer.length ? root.plain(root.answer) : (root.question.length ? (root.busy ? "Thinking…" : "") :
                                     "I can check your Graphite version, disk, memory, network, battery, updates and failed services, read your config files and help with keybinds and settings. Say \"remember …\" to save a note. I can propose a settings change or installing/removing an app; nothing changes until you click Approve, and you can undo it. Speak (Super+Alt+A) to ask out loud; voice stays on this computer and no audio is kept.")
                               color: root.answer.length ? Colors.foreground : Colors.muted; font.pixelSize: 14; wrapMode: Text.Wrap; textFormat: Text.PlainText; Layout.fillWidth: true }
                        Text { visible: root.steps.length > 0; text: "Agents: " + root.steps.join(" "); color: Colors.muted; font.pixelSize: 12; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        Text { visible: root.cited.length > 0; text: "From your notes: " + root.cited; color: Colors.muted; font.pixelSize: 12; Layout.fillWidth: true }
                        Repeater { model: root.pending   // proposed changes: nothing happens until Approve
                            delegate: Rectangle { Layout.fillWidth: true; radius: 8; color: Colors.overlay
                                border.color: Colors.accent; border.width: 1; implicitHeight: card.implicitHeight + 20
                                ColumnLayout { id: card; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 } spacing: 4
                                    Text { text: (modelData.kind === "system" ? "System change · " : "Your settings · ") + "a" + modelData.id + (modelData.agent && modelData.agent !== "general" ? " · proposed by the " + (root.agentNames[modelData.agent] || modelData.agent) + " agent" : ""); color: Colors.muted; font.pixelSize: 11 }
                                    Text { text: modelData.summary; color: Colors.foreground; font.pixelSize: 14; font.bold: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; Layout.fillWidth: true }
                                    Repeater { model: modelData.details
                                        delegate: Text { text: "• " + modelData; color: Colors.muted; font.pixelSize: 12; wrapMode: Text.Wrap; textFormat: Text.PlainText; Layout.fillWidth: true } }
                                    RowLayout { spacing: 8
                                        Btn { label: root.acting ? "Working…" : "Approve"; on: true; onClicked: root.decide("approve", modelData.id) }
                                        Btn { label: "Deny"; onClicked: root.decide("deny", modelData.id) } } } } }
                    } } }
            }

            ColumnLayout { spacing: 8   // Notes: saved only when you ask; data, never instructions
                Rectangle { Layout.fillWidth: true; implicitHeight: 38; radius: 8; color: Colors.surface; border.color: Colors.overlay; border.width: 1
                    TextInput { id: noteIn; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter
                        color: Colors.foreground; font.pixelSize: 14; clip: true; maximumLength: 500
                        onAccepted: { if (text.trim().length) root.run(["graphite-agent", "remember", text.trim()]); text = ""; }
                        Text { visible: !noteIn.text.length; anchors.verticalCenter: parent.verticalCenter; color: Colors.muted; font.pixelSize: 14
                            text: "Add a note for the assistant (Enter). No passwords." } } }
                Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: 8; color: Colors.surface; clip: true
                    Text { visible: root.notesList.length === 0; anchors.centerIn: parent; color: Colors.muted; font.pixelSize: 13
                        text: "No notes. Notes stay on this computer." }
                    ListView { id: nl; anchors { fill: parent; margins: 10 } clip: true; spacing: 6; model: root.notesList
                        delegate: RowLayout { width: nl.width; spacing: 8
                            Text { text: "n" + modelData.id; color: Colors.muted; font.pixelSize: 12 }
                            Text { text: modelData.text; color: Colors.foreground; font.pixelSize: 13; wrapMode: Text.Wrap; textFormat: Text.PlainText; Layout.fillWidth: true }
                            Btn { label: "Forget"; implicitHeight: 26; onClicked: root.run(["graphite-agent", "forget", String(modelData.id)]) } } } }
                RowLayout { spacing: 8
                    Btn { label: "Export…"; onClicked: root.run(["graphite-agent", "export", "~/graphite-agent-export.json"]) }
                    Btn { label: "Forget all"; visible: root.notesList.length > 0; onClicked: root.run(["graphite-agent", "forget", "--all"]) } }
            }

            ColumnLayout { spacing: 8   // History: changes (with Undo), then questions (30 days)
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 170; radius: 8; color: Colors.surface; clip: true
                    Text { visible: root.acts.length === 0; anchors.centerIn: parent; color: Colors.muted; font.pixelSize: 13
                        text: "No changes yet. Changes the assistant proposes appear here." }
                    ListView { id: al; anchors { fill: parent; margins: 10 } clip: true; spacing: 6; model: root.acts
                        delegate: RowLayout { width: al.width; spacing: 8
                            Text { text: modelData.state.replace("_", " "); font.pixelSize: 12; Layout.preferredWidth: 110
                                color: modelData.state === "done" ? Colors.accent : (modelData.state.indexOf("fail") >= 0 ? Colors.red : Colors.muted) }
                            Text { text: modelData.summary + (modelData.error ? " — " + modelData.error : ""); color: Colors.foreground; font.pixelSize: 13
                                elide: Text.ElideRight; textFormat: Text.PlainText; Layout.fillWidth: true }
                            Btn { label: "Undo"; implicitHeight: 26; visible: modelData.undoable; onClicked: root.decide("undo", modelData.id) } } } }
                Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: 8; color: Colors.surface; clip: true
                    Text { visible: root.historyList.length === 0; anchors.centerIn: parent; color: Colors.muted; font.pixelSize: 13
                        text: root.st.history === "off" ? "History is off." : "No questions yet." }
                    ListView { id: hl; anchors { fill: parent; margins: 10 } clip: true; spacing: 6; model: root.historyList
                        delegate: RowLayout { width: hl.width; spacing: 8
                            Text { text: modelData.cloud ? "☁" : ""; color: root.amber; font.pixelSize: 12; Layout.preferredWidth: 14 }
                            Text { text: modelData.state; font.pixelSize: 12; Layout.preferredWidth: 80
                                color: modelData.state === "done" ? Colors.accent : Colors.muted }
                            Text { text: modelData.question || "(not kept)"; color: Colors.foreground; font.pixelSize: 13; elide: Text.ElideRight; textFormat: Text.PlainText; Layout.fillWidth: true }
                            Text { text: (modelData.agents || []).map(a => root.agentNames[a] || a).join(" → "); color: Colors.muted; font.pixelSize: 11 } } } }
                RowLayout { spacing: 8
                    Btn { label: root.st.history === "off" ? "Keep history: off" : "Keep history: on"
                        onClicked: root.run(["graphite-agent", "history", root.st.history === "off" ? "on" : "off"]) }
                    Btn { label: "Clear history"; onClicked: root.run(["graphite-agent", "history", "clear"]) }
                    Btn { label: root.st.agents === "off" ? "Multiple agents: off" : "Multiple agents: on"
                        onClicked: root.run(["graphite-agent", "agents", root.st.agents === "off" ? "on" : "off"]) } }
            }

            ColumnLayout { spacing: 10   // Grok: optional cloud tier, your own xAI key, off by default
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Colors.foreground; font.pixelSize: 13; textFormat: Text.PlainText
                    text: "Optional: answer with xAI's Grok in the cloud, using your own xAI API key (billed to your xAI account). Off by default. "
                        + "What is sent: your question, the assistant's instructions and the results of the system tools it calls (version, memory, disk, network, battery, updates). "
                        + "Notes and config-file contents stay on this computer unless you allow them below; history is never sent. "
                        + "Approvals and undo work the same. If the cloud fails, you're offline or the daily limit is reached, the local model answers." }
                Rectangle { Layout.fillWidth: true; implicitHeight: 38; radius: 8; color: Colors.surface; border.color: Colors.overlay; border.width: 1
                    TextInput { id: keyIn; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter
                        color: Colors.foreground; font.pixelSize: 14; clip: true; echoMode: TextInput.Password; maximumLength: 256
                        onAccepted: if (text.trim().length && !keyP.running) keyP.running = true
                        Text { visible: !keyIn.text.length; anchors.verticalCenter: parent.verticalCenter; color: Colors.muted; font.pixelSize: 14
                            text: root.cl.key && root.cl.key !== "none" ? "Key saved (" + root.cl.key + "). Paste a new one to replace it" : "Paste your xAI API key (Enter to save)" } } }
                RowLayout { spacing: 8
                    Btn { label: "Save key"; onClicked: if (keyIn.text.trim().length && !keyP.running) keyP.running = true }
                    Btn { label: "Forget key"; visible: !!root.cl.key && root.cl.key !== "none"; onClicked: root.run(["graphite-agent", "cloud", "forget-key"]) }
                    Btn { label: root.cl.enabled ? "Grok: on" : "Grok: off"; on: !!root.cl.enabled
                        onClicked: root.run(["graphite-agent", "cloud", root.cl.enabled ? "off" : "on"]) } }
                RowLayout { spacing: 8
                    Btn { label: root.cl.share_notes ? "Send notes: on" : "Send notes: off"; onClicked: root.run(["graphite-agent", "cloud", "share-notes", root.cl.share_notes ? "off" : "on"]) }
                    Btn { label: root.cl.share_files ? "Send config files: on" : "Send config files: off"; onClicked: root.run(["graphite-agent", "cloud", "share-files", root.cl.share_files ? "off" : "on"]) } }
                Text { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Colors.muted; font.pixelSize: 12
                    text: "Model " + (root.cl.model || "") + " at " + (root.cl.endpoint || "") + " · " + (root.cl.used_today || 0) + " of " + (root.cl.cap || 0) + " cloud requests used today (a question uses 1-4). "
                        + "Change with: graphite-agent cloud model NAME, cloud cap N." }
                Item { Layout.fillHeight: true }
            }
            }

            RowLayout { Layout.fillWidth: true; spacing: 8
                Btn { label: root.busy ? "Stop" : "Ask"; on: root.busy; onClicked: root.busy ? root.stop() : (root.send(q.text), q.text = "") }
                Btn { label: root.phase === "listening" ? "Stop listening" : root.phase === "transcribing" ? "…" : "Speak"
                      on: root.phase === "listening"; visible: !!root.st.stt; onClicked: root.listen() }
                Btn { label: root.speaking ? "Stop reading" : "Read aloud"; visible: !!root.st.tts && root.answer.length > 0 && !root.busy
                      onClicked: root.speaking ? root.shutUp() : root.say(root.answer) }
                Btn { label: "Unload model"; visible: !!root.st.model && root.st.server !== "down"; onClicked: { root.stop(); unloadP.running = true; } }
                Btn { label: "Set up model…"; visible: root.st.model === false; onClicked: if (!setupP.running) setupP.running = true }
                Text { text: root.note; color: Colors.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
    }
}
