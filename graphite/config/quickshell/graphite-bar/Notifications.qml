// Graphite notifications (Quickshell): the notification daemon (org.freedesktop.Notifications),
// popups and the notification center, with do-not-disturb. Replaces mako for the Quickshell bar
// (graphite-bar starts mako only for the Waybar opt-out).
//   popups: top right, auto-expire (critical ones stay); click to dismiss, buttons run actions
//   center: bell in the bar, Super+N or `graphite-notify center`; history of this session
//   do-not-disturb: `graphite-notify dnd on|off|toggle` or the center's switch; popups are held
//     back (critical ones still show) but land in the center. Kept across restarts in
//     ~/.local/state/graphite/dnd.
// Layer namespaces "graphite-notifications" (popups) and "graphite-notification-center".
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

Scope {
    id: notif
    property bool dnd: false
    property bool centerOpen: false
    // ids of notifications currently shown as popups
    property var popupIds: []
    readonly property var list: server.trackedNotifications.values
    readonly property int count: list.length
    readonly property string dndFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/graphite/dnd"

    function setDnd(on) {
        dnd = on;
        Quickshell.execDetached(["sh", "-c", on ? 'mkdir -p "$(dirname "$1")" && : > "$1"' : 'rm -f "$1"', "sh", dndFile]);
    }
    function dropPopup(id) { popupIds = popupIds.filter(i => i !== id) }
    function clearAll() { for (const n of list.slice()) n.dismiss(); popupIds = [] }

    Process {   // restore do-not-disturb
        running: true
        command: ["test", "-e", notif.dndFile]
        onExited: code => notif.dnd = code === 0
    }

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        onNotification: n => {
            n.tracked = true;
            if (!notif.dnd || n.urgency === NotificationUrgency.Critical)
                notif.popupIds = notif.popupIds.concat([n.id]).slice(-5);
        }
    }

    component Card: Rectangle {
        id: card
        required property var n
        property bool popup: false
        width: 360; radius: 12
        implicitHeight: col.implicitHeight + 20
        color: Colors.background
        border.width: 1
        border.color: n && n.urgency === NotificationUrgency.Critical ? Colors.red : Colors.overlay
        Timer {
            // expire popups: the app's timeout, else 6 s; critical ones stay until dismissed
            running: card.popup && card.n && card.n.urgency !== NotificationUrgency.Critical
            interval: card.n && card.n.expireTimeout > 0 ? card.n.expireTimeout * (card.n.expireTimeout < 100 ? 1000 : 1) : 6000
            onTriggered: notif.dropPopup(card.n.id)
        }
        MouseArea {
            anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: e => {
                if (card.popup && e.button === Qt.LeftButton) notif.dropPopup(card.n.id);
                else { notif.dropPopup(card.n.id); card.n.dismiss(); }
            }
        }
        RowLayout {
            anchors { fill: parent; margins: 10 }
            spacing: 10
            IconImage {
                Layout.alignment: Qt.AlignTop
                visible: source != ""
                implicitSize: 32
                source: card.n ? (card.n.image || (card.n.appIcon ? Quickshell.iconPath(card.n.appIcon, true) : "")) : ""
            }
            ColumnLayout {
                id: col
                Layout.fillWidth: true; spacing: 3
                Text {
                    Layout.fillWidth: true; elide: Text.ElideRight
                    text: card.n ? card.n.appName : ""; color: Colors.muted; font.pixelSize: 11
                    visible: text !== ""
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    text: card.n ? card.n.summary : ""; color: Colors.foreground; font.pixelSize: 14; font.bold: true
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 5; elide: Text.ElideRight
                    text: card.n ? card.n.body : ""; color: Colors.foreground; font.pixelSize: 12
                    textFormat: Text.PlainText; visible: text !== ""
                }
                Flow {
                    Layout.fillWidth: true; spacing: 6
                    visible: card.n && card.n.actions.length > 0
                    Repeater {
                        model: card.n ? card.n.actions : []
                        Rectangle {
                            required property var modelData
                            width: at.implicitWidth + 16; height: 24; radius: 8; color: Colors.surface
                            Text { id: at; anchors.centerIn: parent; text: modelData.text; color: Colors.foreground; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; onClicked: { notif.dropPopup(card.n.id); modelData.invoke() } }
                        }
                    }
                }
            }
        }
    }

    // ---- popups ----
    PanelWindow {
        id: popups
        visible: notif.popupIds.length > 0 && !notif.centerOpen
        WlrLayershell.namespace: "graphite-notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Normal
        anchors { top: true; right: true }
        margins { top: 8; right: 12 }
        implicitWidth: 360
        implicitHeight: Math.max(1, popupCol.implicitHeight)
        color: "transparent"
        Column {
            id: popupCol
            spacing: 8
            Repeater {
                model: notif.list.filter(n => notif.popupIds.indexOf(n.id) >= 0)
                Card { required property var modelData; n: modelData; popup: true }
            }
        }
    }

    // ---- notification center ----
    PanelWindow {
        id: center
        visible: notif.centerOpen
        WlrLayershell.namespace: "graphite-notification-center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        anchors { top: true; right: true; bottom: true }
        margins { top: 8; right: 12; bottom: 12 }
        implicitWidth: 384
        color: "transparent"
        Rectangle {
            anchors.fill: parent; radius: 14; color: Colors.background; border.color: Colors.overlay; border.width: 1
            focus: true
            Keys.onEscapePressed: notif.centerOpen = false
            ColumnLayout {
                anchors { fill: parent; margins: 12 }
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Notifications"; color: Colors.foreground; font.pixelSize: 16; font.bold: true; Layout.fillWidth: true }
                    Rectangle {   // do-not-disturb switch
                        width: dndText.implicitWidth + 16; height: 24; radius: 12
                        color: notif.dnd ? Colors.accent : Colors.surface
                        Text { id: dndText; anchors.centerIn: parent; text: "Do not disturb"; font.pixelSize: 12
                               color: notif.dnd ? Colors.accentText : Colors.foreground }
                        MouseArea { anchors.fill: parent; onClicked: notif.setDnd(!notif.dnd) }
                    }
                    Rectangle {
                        width: 52; height: 24; radius: 12; color: Colors.surface
                        Text { anchors.centerIn: parent; text: "Clear"; color: Colors.foreground; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; onClicked: notif.clearAll() }
                    }
                }
                Text {
                    visible: notif.count === 0
                    text: "No notifications"; color: Colors.muted; font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 20
                }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true; spacing: 8
                    model: notif.list.slice().reverse()
                    delegate: Card { required property var modelData; n: modelData }
                }
            }
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { notif.centerOpen = !notif.centerOpen }
        function open(): void { notif.centerOpen = true }
        function close(): void { notif.centerOpen = false }
        function isOpen(): bool { return notif.centerOpen }
        function dnd(state: string): string {
            if (state === "on" || state === "off" || state === "toggle")
                notif.setDnd(state === "toggle" ? !notif.dnd : state === "on");
            return notif.dnd ? "on" : "off";
        }
        function count(): int { return notif.count }
        function popups(): int { return notif.popupIds.length }
        function clear(): void { notif.clearAll() }
        // summaries, newest first (scripts/tests)
        function list(): string { return notif.list.slice().reverse().map(n => n.summary).join("\n") }
    }
}
