import QtQuick
import QtQuick.Controls
Rectangle {
    width: 1920; height: 1080; color: "#1c1d20"
    Image { anchors.fill: parent; source: "/usr/share/backgrounds/graphite/graphite.png"; fillMode: Image.PreserveAspectCrop }
    Rectangle {
        anchors.centerIn: parent; width: 380; height: 260; radius: 12
        color: "#e01c1d20"; border.color: "#5eead4"; border.width: 2
        Column {
            anchors.centerIn: parent; spacing: 14
            Text { text: "Graphite"; color: "#5eead4"; font.pixelSize: 30; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
            TextField { id: user; width: 300; placeholderText: "user"; text: userModel.lastUser }
            TextField { id: pass; width: 300; placeholderText: "password"; echoMode: TextInput.Password
                        onAccepted: sddm.login(user.text, pass.text, sessionModel.lastIndex) }
            Button { text: "Log in"; width: 300; onClicked: sddm.login(user.text, pass.text, sessionModel.lastIndex) }
        }
    }
}
