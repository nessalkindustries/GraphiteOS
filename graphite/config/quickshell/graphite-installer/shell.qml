// Graphite graphical installer (eco-4). Opened on the live ISO by `graphite-installer auto`;
// all work goes through graphite-installer -> graphite-iso-install (same backend as the
// unattended install). Window title "Install Graphite"; IPC target "installer".
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root
    property int step: 0
    readonly property var steps: ["Welcome", "Disk", "Account", "Encryption", "Region", "Summary", "Install"]
    property var disks: []
    property string disk: ""
    property var d: ({ timezone: "UTC", keymap: "us", locale: "en_US.UTF-8", hostname: "graphite", profile: "full", nvidia: "0" })
    property string err: ""
    property string istate: "idle"
    property string progress: ""
    property string last: ""
    property bool dryRun: false     // IPC/tests: validate but never start the install

    function kv(t) { const o = {}; for (const l of t.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); } return o; }
    function answers() {
        const a = { disk: root.disk, user: userF.text, password: pw1.text, luks: lk1.text, hostname: hostF.text,
                    timezone: tzF.text, keymap: kmF.text, locale: locF.text, profile: root.d.profile, nvidia: root.d.nvidia };
        return Object.keys(a).map(k => k + "=" + String(a[k]).replace(/\n/g, "")).join("\n") + "\n";
    }
    function localErr() {
        if (root.step === 1 && !root.disk) return "Pick a disk.";
        if (root.step === 2 && !/^[a-z_][a-z0-9_-]{0,31}$/.test(userF.text)) return "Username: lowercase letters, digits, - and _.";
        if (root.step === 2 && (pw1.text.length === 0 || pw1.text !== pw2.text)) return "Passwords are empty or do not match.";
        if (root.step === 3 && (lk1.text.length < 8 || lk1.text !== lk2.text)) return "Passphrase needs 8+ characters and must match.";
        return "";
    }
    function next() { root.err = localErr(); if (!root.err && root.step < 5) root.step++; }
    function validate() { saveP.running = false; saveP.stdinEnabled = true; saveP.running = true; }

    Process { id: diskP; command: ["graphite-installer", "disks"]; running: true
        stdout: StdioCollector { onStreamFinished: root.disks = this.text.split("\n").filter(x => x.length).map(x => x.split("\t")) } }
    Process { id: defP; command: ["graphite-installer", "defaults"]; running: true
        stdout: StdioCollector { onStreamFinished: { const o = root.kv(this.text); root.d = Object.assign({}, root.d, o);
            tzF.text = root.d.timezone; kmF.text = root.d.keymap; locF.text = root.d.locale; hostF.text = root.d.hostname; } } }
    // writes the 0600 answers file and validates it; on "ok" either starts or (dry run) stops
    Process { id: saveP; command: ["graphite-installer", "answers"]; stdinEnabled: true
        onStarted: { write(root.answers()); stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: {
            const t = this.text.trim();
            if (t === "ok") { root.err = ""; if (!root.dryRun) { startP.running = true; root.step = 6; } else root.err = "Answers OK (test mode: not installing)."; }
            else root.err = t.replace(/error: /g, ""); } } }
    Process { id: startP; command: ["graphite-installer", "start"]; onExited: poll.running = true }
    Process { id: statP; command: ["graphite-installer", "status"]
        stdout: StdioCollector { onStreamFinished: { const o = root.kv(this.text);
            root.istate = o.state || "idle"; root.progress = o.step || ""; root.last = o.last || "";
            if (root.istate === "done" || root.istate === "failed") poll.running = false; } } }
    Timer { id: poll; interval: 2000; repeat: true; onTriggered: statP.running = true }
    Process { id: rebootP; command: ["systemctl", "reboot"] }

    IpcHandler {
        target: "installer"
        function step(n: int): void { root.step = Math.max(0, Math.min(5, n)); }
        function current(): string { return root.steps[root.step]; }
        function diskCount(): int { return root.disks.length; }
        function testMode(): void { root.dryRun = true; }
        function fill(disk: string, user: string, pass: string, luks: string): void {
            root.disk = disk; userF.text = user; pw1.text = pass; pw2.text = pass; lk1.text = luks; lk2.text = luks; }
        function confirm(): void { root.validate(); }
        function error(): string { return root.err; }
        function quit(): void { Qt.quit(); }
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool on: false
        property bool primary: false
        property bool danger: false
        signal clicked()
        implicitWidth: Math.max(96, t.implicitWidth + 28); implicitHeight: 36; radius: 9
        color: danger ? Colors.red : (on || primary) ? Colors.accent : (m.containsMouse ? Colors.overlay : Colors.surface)
        Text { id: t; anchors.centerIn: parent; text: b.label; font.pixelSize: 14; color: (b.on || b.primary || b.danger) ? Colors.accentText : Colors.foreground }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }
    component Field: ColumnLayout {
        property alias text: inp.text
        property string label: ""
        property bool secret: false
        Layout.fillWidth: true; spacing: 4
        Text { text: parent.label; color: Colors.muted; font.pixelSize: 12 }
        Rectangle { Layout.fillWidth: true; implicitHeight: 36; radius: 8; color: Colors.surface
            TextInput { id: inp; anchors { fill: parent; margins: 9 } color: Colors.foreground; font.pixelSize: 14
                echoMode: parent.parent.secret ? TextInput.Password : TextInput.Normal; clip: true } }
    }
    component Para: Text { color: Colors.muted; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }

    FloatingWindow {
        title: "Install Graphite"
        implicitWidth: 860; implicitHeight: 600
        color: Colors.background
        onClosed: Qt.quit()

        ColumnLayout {
            anchors { fill: parent; margins: 28 } spacing: 16
            Text { text: "Install Graphite"; color: Colors.foreground; font.pixelSize: 26; font.bold: true }
            RowLayout { spacing: 8
                Repeater { model: root.steps
                    Rectangle { required property string modelData; required property int index
                        implicitWidth: lbl.implicitWidth + 24; implicitHeight: 28; radius: 14
                        color: index === root.step ? Colors.accent : (index < root.step ? Colors.overlay : Colors.surface)
                        Text { id: lbl; anchors.centerIn: parent; text: (index + 1) + ". " + modelData; font.pixelSize: 12
                               color: index === root.step ? Colors.accentText : Colors.foreground } } } }

            Item { Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout { anchors.fill: parent; visible: root.step === 0; spacing: 12
                    Para { text: "This installs Graphite (Arch Linux + Hyprland) to a disk with full-disk encryption (LUKS2), Btrfs snapshots and the signed Graphite repo. You can keep trying the live system and install later from the launcher." }
                    Para { text: "The disk you pick will be completely erased. Back up anything you need first." }
                    Item { Layout.fillHeight: true } }
                ColumnLayout { anchors.fill: parent; visible: root.step === 1; spacing: 10
                    Para { text: "Pick the disk to install to. Everything on it will be erased." }
                    Repeater { model: root.disks
                        Btn { required property var modelData; Layout.fillWidth: true
                              label: modelData[0] + "   " + modelData[1] + "   " + modelData[2]; on: root.disk === modelData[0]
                              onClicked: root.disk = modelData[0] } }
                    Para { visible: root.disks.length === 0; text: "No installable disks found." }
                    Item { Layout.fillHeight: true } }
                ColumnLayout { anchors.fill: parent; visible: root.step === 2; spacing: 10
                    Field { id: userF; label: "Username" }
                    Field { id: pw1; label: "Password"; secret: true }
                    Field { id: pw2; label: "Confirm password"; secret: true }
                    Field { id: hostF; label: "Computer name" }
                    Item { Layout.fillHeight: true } }
                ColumnLayout { anchors.fill: parent; visible: root.step === 3; spacing: 10
                    Para { text: "Your disk is encrypted. This passphrase is asked at every boot; if you lose it the data cannot be recovered." }
                    Field { id: lk1; label: "Encryption passphrase (8+ characters)"; secret: true }
                    Field { id: lk2; label: "Confirm passphrase"; secret: true }
                    Item { Layout.fillHeight: true } }
                ColumnLayout { anchors.fill: parent; visible: root.step === 4; spacing: 10
                    Field { id: tzF; label: "Timezone (e.g. America/Toronto)" }
                    Field { id: kmF; label: "Console keymap (e.g. us, de, fr)" }
                    Field { id: locF; label: "Locale (e.g. en_US.UTF-8)" }
                    RowLayout { spacing: 8
                        Text { text: "Packages:"; color: Colors.foreground; font.pixelSize: 14 }
                        Btn { label: "Full"; on: root.d.profile === "full"; onClicked: root.d = Object.assign({}, root.d, { profile: "full" }) }
                        Btn { label: "Desktop only"; on: root.d.profile === "desktop"; onClicked: root.d = Object.assign({}, root.d, { profile: "desktop" }) }
                        Item { implicitWidth: 24 }
                        Btn { label: root.d.nvidia === "1" ? "NVIDIA driver: on" : "NVIDIA driver: off"; on: root.d.nvidia === "1"
                              onClicked: root.d = Object.assign({}, root.d, { nvidia: root.d.nvidia === "1" ? "0" : "1" }) } }
                    Item { Layout.fillHeight: true } }
                ColumnLayout { anchors.fill: parent; visible: root.step === 5; spacing: 8
                    Para { text: "Review, then install. " + root.disk + " will be ERASED." }
                    Repeater { model: [["Disk", root.disk], ["User", userF.text], ["Computer name", hostF.text], ["Timezone", tzF.text],
                                       ["Keymap", kmF.text], ["Locale", locF.text], ["Packages", root.d.profile], ["NVIDIA", root.d.nvidia === "1" ? "yes" : "no"], ["Encryption", "LUKS2"]]
                        RowLayout { required property var modelData; spacing: 12
                            Text { text: modelData[0]; color: Colors.muted; font.pixelSize: 14; Layout.preferredWidth: 140 }
                            Text { text: modelData[1]; color: Colors.foreground; font.pixelSize: 14 } } }
                    Item { Layout.fillHeight: true } }
                ColumnLayout { anchors.fill: parent; visible: root.step === 6; spacing: 12
                    Text { text: root.istate === "done" ? "Graphite is installed." : root.istate === "failed" ? "The install failed." : "Installing…"
                           color: Colors.foreground; font.pixelSize: 20 }
                    Para { text: "Step " + root.progress + (root.last ? ": " + root.last : "") }
                    Para { visible: root.istate === "failed"; text: "Full log: /tmp/graphite-installer/install.log" }
                    Btn { visible: root.istate === "done"; primary: true; label: "Reboot now"; onClicked: rebootP.running = true }
                    Item { Layout.fillHeight: true } } }

            Text { visible: root.err.length > 0; text: root.err; color: Colors.red; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
            RowLayout { visible: root.step < 6; Layout.fillWidth: true; spacing: 10
                Btn { label: "Quit"; onClicked: Qt.quit() }
                Item { Layout.fillWidth: true }
                Btn { visible: root.step > 0; label: "Back"; onClicked: { root.err = ""; root.step--; } }
                Btn { visible: root.step < 5; primary: true; label: root.step === 0 ? "Start" : "Next"; onClicked: root.next() }
                Btn { visible: root.step === 5; danger: true; label: "Erase disk and install"; onClicked: root.validate() } }
        }
    }
}
