// Graphite SDDM greeter (Qt 6). Static Graphite palette; teal accent.
import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    width: 1920; height: 1080
    color: "#18191c"
    readonly property color accent: "#5eead4"
    readonly property color accent2: "#38bdf8"
    readonly property color fg: "#d7d9dd"
    readonly property color muted: "#868a92"
    readonly property color surface: "#222428"
    property int sessionIndex: sessionModel.lastIndex
    property string failMsg: ""

    Connections {
        target: sddm
        function onLoginFailed() { root.failMsg = "Wrong password"; pass.text = ""; pass.forceActiveFocus() }
    }

    Image {
        anchors.fill: parent
        source: "/usr/share/backgrounds/graphite/graphite-teal.png"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: "#18191c"; opacity: 0.35 }

    // clock
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        spacing: 4
        Text {
            id: clock
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.fg; font.family: "Inter"; font.weight: Font.Light; font.pixelSize: 112
            text: Qt.formatTime(new Date(), "HH:mm")
        }
        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.muted; font.family: "Inter"; font.pixelSize: 22
            text: Qt.formatDate(new Date(), "dddd, d MMMM")
        }
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: { clock.text = Qt.formatTime(new Date(), "HH:mm"); date.text = Qt.formatDate(new Date(), "dddd, d MMMM") }
        }
    }

    // login card
    Rectangle {
        id: card
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 110
        width: 380; height: 250; radius: 20
        color: "#d9222428"
        border.color: "#3a3d43"; border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 14
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64; height: 64; radius: 32
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: root.accent }
                    GradientStop { position: 1; color: root.accent2 }
                }
                Text {
                    anchors.centerIn: parent
                    text: user.text.length ? user.text.charAt(0).toUpperCase() : "G"
                    color: "#0f1a19"; font.family: "Inter"; font.pixelSize: 28; font.weight: Font.DemiBold
                }
            }
            TextField {
                id: user
                width: 300; height: 40
                text: userModel.lastUser
                placeholderText: "user"
                horizontalAlignment: TextInput.AlignHCenter
                color: root.fg; font.family: "Inter"; font.pixelSize: 16
                background: Rectangle { color: "transparent" }
                KeyNavigation.tab: pass
            }
            TextField {
                id: pass
                width: 300; height: 44
                echoMode: TextInput.Password
                placeholderText: "password"
                placeholderTextColor: root.muted
                horizontalAlignment: TextInput.AlignHCenter
                color: root.fg; font.family: "Inter"; font.pixelSize: 15
                focus: true
                background: Rectangle {
                    radius: 22; color: "#18191c"
                    border.width: 2; border.color: pass.activeFocus ? root.accent : "#3a3d43"
                }
                onAccepted: sddm.login(user.text, pass.text, root.sessionIndex)
                Component.onCompleted: forceActiveFocus()
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.failMsg; color: "#f2777a"; font.family: "Inter"; font.pixelSize: 13
                height: 14
            }
        }
    }

    // bottom bar: session + power
    Row {
        anchors.bottom: parent.bottom; anchors.right: parent.right
        anchors.margins: 28
        spacing: 22
        Text {
            text: "󰧨  " + (sessionModel.data(sessionModel.index(root.sessionIndex, 0), Qt.UserRole + 4) || "Hyprland")
            color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 15
            MouseArea { anchors.fill: parent; onClicked: root.sessionIndex = (root.sessionIndex + 1) % sessionModel.rowCount() }
        }
        Text {
            text: "󰜉"; color: root.muted; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18
            visible: sddm.canReboot
            MouseArea { anchors.fill: parent; onClicked: sddm.reboot() }
        }
        Text {
            text: "󰐥"; color: "#f2777a"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 18
            visible: sddm.canPowerOff
            MouseArea { anchors.fill: parent; onClicked: sddm.powerOff() }
        }
    }
    // no wordmark here: the wallpaper already carries "graphite" (it showed twice)
}
