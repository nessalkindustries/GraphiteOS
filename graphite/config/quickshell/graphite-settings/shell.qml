// Graphite Settings (desk-6): appearance, display, input, network, about; theme store (eco-2); apps (eco-3).
// Run with `graphite-settings` (Super+I). Every read and write goes through the
// graphite-settings backend, so this window and `graphite settings` always agree.
// Window class/title "Graphite Settings"; IPC target "settings" (show/quit/page).
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root
    property var st: ({})
    property var about: ({})
    property var themes: []
    property var nets: []
    property var store: []
    property var apps: []
    property string appQuery: ""
    property string page: "appearance"
    property string msg: ""

    function kv(text) {
        const o = {};
        for (const l of text.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); }
        return o;
    }
    function refresh() { if (!getP.running) getP.running = true; }
    function set(k, v) { setP.command = ["graphite-settings", "set", k, String(v)]; msg = "Applying " + k + "…"; setP.running = true; }

    Process { id: getP; command: ["graphite-settings", "get"]; running: true
        stdout: StdioCollector { onStreamFinished: root.st = root.kv(this.text) } }
    Process { id: aboutP; command: ["graphite-settings", "about"]; running: true
        stdout: StdioCollector { onStreamFinished: root.about = root.kv(this.text) } }
    Process { id: themeP; command: ["graphite-theme", "list"]; running: true
        stdout: StdioCollector { onStreamFinished: root.themes = this.text.split("\n").filter(l => l.length > 2).map(l => l.slice(2)) } }
    Process { id: netP; command: ["graphite-settings", "wifi-list"]
        stdout: StdioCollector { onStreamFinished: root.nets = this.text.split("\n").filter(l => l.length > 0).map(l => l.split(":")) } }
    Process { id: setP
        stderr: StdioCollector { onStreamFinished: if (this.text.length) root.msg = this.text.trim() }
        onExited: (code) => { if (code === 0) root.msg = "Saved"; root.refresh(); } }
    Process { id: runP }
    Process { id: storeP; command: ["graphite-theme", "browse", "--tsv"]
        stdout: StdioCollector { onStreamFinished: root.store = this.text.split("\n").filter(l => l.length > 0).map(l => l.split("\t")) } }
    function openStore() { storeP.running = true; themeP.running = true; }
    Process { id: appsP
        stdout: StdioCollector { onStreamFinished: root.apps = this.text.split("\n").filter(l => l.length > 0).map(l => l.split("\t")) } }
    function openApps(q) {
        root.appQuery = q || "";
        appsP.command = root.appQuery.length >= 2 ? ["graphite-apps", "search", root.appQuery, "--tsv"] : ["graphite-apps", "list", "--tsv"];
        appsP.running = true;
    }
    function appAction(verb, id) {
        runP.command = ["kitty", "--title", "Graphite: " + verb + " " + id, "sh", "-c", "graphite-apps " + verb + " \"$0\"; echo; read -r -p 'Press Enter to close' _", id];
        runP.running = true; root.msg = "Opening a terminal…";
    }

    IpcHandler {
        target: "settings"
        function page(name: string): void { root.page = name; if (name === "store") root.openStore(); if (name === "apps") root.openApps(""); }
        function search(q: string): void { root.page = "apps"; root.openApps(q); }
        function results(): int { return root.apps.length; }
        function current(): string { return root.page; }
        function quit(): void { Qt.quit(); }
    }

    component Btn: Rectangle {
        id: b
        property string label: ""
        property bool on: false
        signal clicked()
        implicitWidth: Math.max(88, t.implicitWidth + 24); implicitHeight: 32; radius: 8
        color: on ? Colors.accent : (m.containsMouse ? Colors.overlay : Colors.surface)
        border.color: Colors.overlay; border.width: on ? 0 : 1
        Text { id: t; anchors.centerIn: parent; text: b.label; font.pixelSize: 13; color: b.on ? Colors.accentText : Colors.foreground }
        MouseArea { id: m; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
    }
    component Row2: RowLayout {
        property string label: ""
        default property alias content: box.data
        Layout.fillWidth: true; spacing: 16
        Text { text: parent.label; color: Colors.foreground; font.pixelSize: 14; Layout.preferredWidth: 150 }
        Flow { id: box; Layout.fillWidth: true; spacing: 8 }
    }
    component Head: Text { color: Colors.foreground; font.pixelSize: 22; font.bold: true; Layout.bottomMargin: 8 }

    FloatingWindow {
        id: win
        title: "Graphite Settings"
        implicitWidth: 860; implicitHeight: 560
        color: Colors.background
        onClosed: Qt.quit()

        RowLayout {
            anchors.fill: parent; spacing: 0
            Rectangle {   // sidebar
                Layout.fillHeight: true; Layout.preferredWidth: 200; color: Colors.surface
                ColumnLayout {
                    anchors { fill: parent; margins: 12 } spacing: 4
                    Text { text: "Settings"; color: Colors.muted; font.pixelSize: 12; Layout.bottomMargin: 6 }
                    Repeater {
                        model: [["appearance", "Appearance"], ["display", "Display"], ["input", "Input"], ["network", "Network"], ["store", "Theme store"], ["apps", "Apps"], ["about", "About"]]
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; implicitHeight: 36; radius: 8
                            color: root.page === modelData[0] ? Colors.overlay : (nm.containsMouse ? Colors.background : "transparent")
                            Text { anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 12 }
                                   text: modelData[1]; font.pixelSize: 14
                                   color: root.page === modelData[0] ? Colors.accent : Colors.foreground }
                            MouseArea { id: nm; anchors.fill: parent; hoverEnabled: true
                                onClicked: { root.page = modelData[0]; if (modelData[0] === "network") netP.running = true; if (modelData[0] === "store") root.openStore(); if (modelData[0] === "apps") root.openApps(""); } }
                        }
                    }
                    Item { Layout.fillHeight: true }
                    Text { text: root.msg; color: Colors.muted; font.pixelSize: 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
                }
            }
            ColumnLayout {   // page
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.margins: 24; spacing: 14

                // Appearance
                Head { text: "Appearance"; visible: root.page === "appearance" }
                Row2 { label: "Theme"; visible: root.page === "appearance"
                    Repeater { model: root.themes
                        Btn { required property string modelData; label: modelData; on: root.st.theme === modelData; onClicked: root.set("theme", modelData) } } }
                Row2 { label: "Bar"; visible: root.page === "appearance"
                    Btn { label: "Quickshell"; on: root.st.bar === "quickshell"; onClicked: root.set("bar", "quickshell") }
                    Btn { label: "Waybar"; on: root.st.bar === "waybar"; onClicked: root.set("bar", "waybar") } }
                Row2 { label: "From wallpaper"; visible: root.page === "appearance"
                    Btn { label: "Pick image…"; onClicked: { runP.command = ["sh", "-c", "f=$(zenity --file-selection --file-filter='Images | *.png *.jpg *.jpeg *.webp') && graphite-theme from-wallpaper \"$f\""]; runP.running = true; } } }

                // Display
                Head { text: "Display"; visible: root.page === "display" }
                Row2 { label: "Scale"; visible: root.page === "display"
                    Repeater { model: ["auto", "1", "1.25", "1.5", "1.75", "2"]
                        Btn { required property string modelData; label: modelData; on: root.st.scale === modelData; onClicked: root.set("scale", modelData) } } }

                // Input
                Head { text: "Input"; visible: root.page === "input" }
                Row2 { label: "Keyboard layout"; visible: root.page === "input"
                    Repeater { model: ["us", "gb", "de", "fr", "es", "it", "se", "no", "dk", "fi", "pl", "pt", "ca"]
                        Btn { required property string modelData; label: modelData; on: root.st.kb_layout === modelData; onClicked: root.set("kb_layout", modelData) } } }
                Row2 { label: "Pointer speed"; visible: root.page === "input"
                    Repeater { model: ["-0.5", "-0.25", "0", "0.25", "0.5"]
                        Btn { required property string modelData; label: modelData; on: Number(root.st.sensitivity) === Number(modelData); onClicked: root.set("sensitivity", modelData) } } }
                Row2 { label: "Natural scrolling"; visible: root.page === "input"
                    Btn { label: "On"; on: root.st.natural_scroll === "true"; onClicked: root.set("natural_scroll", "true") }
                    Btn { label: "Off"; on: root.st.natural_scroll === "false"; onClicked: root.set("natural_scroll", "false") } }

                // Network
                Head { text: "Network"; visible: root.page === "network" }
                Row2 { label: "Wi-Fi"; visible: root.page === "network"
                    Btn { label: "On"; on: root.st.wifi === "enabled"; onClicked: root.set("wifi", "on") }
                    Btn { label: "Off"; on: root.st.wifi === "disabled"; onClicked: root.set("wifi", "off") }
                    Btn { label: "Rescan"; onClicked: netP.running = true }
                    Btn { label: "Advanced…"; onClicked: { runP.command = ["kitty", "-e", "nmtui"]; runP.running = true; } } }
                ColumnLayout { visible: root.page === "network"; Layout.fillWidth: true; spacing: 2
                    Text { visible: root.nets.length === 0; text: "No Wi-Fi networks found"; color: Colors.muted; font.pixelSize: 13 }
                    Repeater { model: root.nets
                        Text { required property var modelData
                               text: (modelData[0] === "*" ? "● " : "   ") + (modelData[1] || "(hidden)") + "   " + (modelData[2] || "") + "%  " + (modelData[3] || "")
                               color: modelData[0] === "*" ? Colors.accent : Colors.foreground; font.pixelSize: 13 } } }

                // Theme store: graphite-theme-* packages from the signed Graphite repo
                Head { text: "Theme store"; visible: root.page === "store" }
                Text { visible: root.page === "store"; text: root.store.length ? "Themes from the signed Graphite repo. Installing opens a terminal and asks for your password." : "No store themes found (run sudo pacman -Sy)."
                       color: Colors.muted; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                Repeater { model: root.store
                    RowLayout { required property var modelData; visible: root.page === "store"; Layout.fillWidth: true; spacing: 16
                        ColumnLayout { Layout.fillWidth: true; spacing: 2
                            Text { text: modelData[0]; color: Colors.foreground; font.pixelSize: 15 }
                            Text { text: modelData[1] || ""; color: Colors.muted; font.pixelSize: 12 } }
                        Btn { visible: modelData[2] !== "installed"; label: "Install"
                              onClicked: { runP.command = ["kitty", "--title", "Graphite: install theme", "sh", "-c", "graphite-theme install " + modelData[0] + " --set; echo; read -r -p 'Press Enter to close' _"]; runP.running = true; root.msg = "Opening a terminal…"; } }
                        Btn { visible: modelData[2] === "installed"; label: root.st.theme === modelData[0] ? "In use" : "Use"; on: root.st.theme === modelData[0]
                              onClicked: root.set("theme", modelData[0]) } } }

                // Apps: curated list, search across the Arch repos and Flathub (when enabled)
                Head { text: "Apps"; visible: root.page === "apps" }
                RowLayout { visible: root.page === "apps"; Layout.fillWidth: true; spacing: 8
                    Rectangle { Layout.fillWidth: true; implicitHeight: 34; radius: 8; color: Colors.surface; border.color: Colors.overlay; border.width: 1
                        TextInput { id: q; anchors { fill: parent; leftMargin: 12; rightMargin: 12 } verticalAlignment: TextInput.AlignVCenter
                            color: Colors.foreground; font.pixelSize: 14; clip: true; onAccepted: root.openApps(text)
                            Text { visible: !q.text.length; anchors.verticalCenter: parent.verticalCenter; text: "Search apps (Enter)"; color: Colors.muted; font.pixelSize: 14 } } }
                    Btn { label: "Featured"; onClicked: { q.text = ""; root.openApps(""); } }
                    Btn { label: "Enable Flathub"; onClicked: root.appAction("flathub", "") } }
                Text { visible: root.page === "apps" && root.apps.length === 0; text: appsP.running ? "Loading…" : "No apps found"; color: Colors.muted; font.pixelSize: 13 }
                Flickable { visible: root.page === "apps"; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    contentHeight: appCol.implicitHeight
                    ColumnLayout { id: appCol; width: parent.width; spacing: 6
                        Repeater { model: root.apps
                            RowLayout { required property var modelData; Layout.fillWidth: true; spacing: 12
                                ColumnLayout { Layout.fillWidth: true; spacing: 1
                                    Text { text: modelData[3] + "  ·  " + modelData[2] + (modelData[1] === "flatpak" ? "  ·  Flathub" : ""); color: Colors.foreground; font.pixelSize: 14 }
                                    Text { text: modelData[4] || ""; color: Colors.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true } }
                                Btn { label: modelData[5] === "installed" ? "Remove" : "Install"; on: modelData[5] !== "installed"
                                      onClicked: root.appAction(modelData[5] === "installed" ? "remove" : "install", modelData[0]) } } } } }

                // About
                Head { text: "About"; visible: root.page === "about" }
                Repeater { model: [["os", "System"], ["version", "Graphite config"], ["kernel", "Kernel"], ["host", "Hostname"], ["cpu", "Processor"], ["memory", "Memory"], ["gpu", "Graphics"]]
                    RowLayout { required property var modelData; visible: root.page === "about"; spacing: 16
                        Text { text: modelData[1]; color: Colors.muted; font.pixelSize: 14; Layout.preferredWidth: 150 }
                        Text { text: root.about[modelData[0]] || "—"; color: Colors.foreground; font.pixelSize: 14 } } }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
