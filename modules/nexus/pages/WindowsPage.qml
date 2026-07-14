pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Nord
import Nord.Config
import Quickshell
import Quickshell.Io
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Windows")

    property int outTop: 0
    property int outLeft: 0
    property int outBottom: 0
    property int outRight: 0
    property int inTop: 0
    property int inLeft: 0
    property int inBottom: 0
    property int inRight: 0
    property int borderW: 1
    property int barThickness: 40

    readonly property string tokensPath: `${Paths.config}/nord/shell-tokens.json`

    data: [
        Process {
            id: readTokensProcess
            property string buffer
            command: ["cat", root.tokensPath]
            running: true
            stdout: SplitParser { onRead: data => readTokensProcess.buffer += data }
            onRunningChanged: {
                if (!running) {
                    try {
                        const d = JSON.parse(readTokensProcess.buffer);
                        if (d.sizes && d.sizes.bar && d.sizes.bar.innerWidth !== undefined)
                            root.barThickness = d.sizes.bar.innerWidth;
                    } catch (e) {}
                    readTokensProcess.buffer = "";
                }
            }
        },
        Process {
            id: readOutProcess
            property string buffer
            command: ["hyprctl", "-j", "getoption", "general:gaps_out"]
            running: true
            stdout: SplitParser { onRead: data => readOutProcess.buffer += data }
            onRunningChanged: {
                if (!running) {
                    try {
                        const d = JSON.parse(readOutProcess.buffer);
                        const parts = (d.css ?? "0").split(" ").filter(s => s.length > 0);
                        if (parts.length === 4) {
                            root.outTop = parseInt(parts[0]);
                            root.outRight = parseInt(parts[1]);
                            root.outBottom = parseInt(parts[2]);
                            root.outLeft = parseInt(parts[3]);
                        }
                    } catch (e) {}
                    readOutProcess.buffer = "";
                    readInProcess.running = true;
                }
            }
        },
        Process {
            id: readInProcess
            property string buffer
            command: ["hyprctl", "-j", "getoption", "general:gaps_in"]
            running: false
            stdout: SplitParser { onRead: data => readInProcess.buffer += data }
            onRunningChanged: {
                if (!running) {
                    try {
                        const d = JSON.parse(readInProcess.buffer);
                        const parts = (d.css ?? "0").split(" ").filter(s => s.length > 0);
                        if (parts.length === 4) {
                            root.inTop = parseInt(parts[0]);
                            root.inRight = parseInt(parts[1]);
                            root.inBottom = parseInt(parts[2]);
                            root.inLeft = parseInt(parts[3]);
                        }
                    } catch (e) {}
                    readInProcess.buffer = "";
                    readBorderProcess.running = true;
                }
            }
        },
        Process {
            id: readBorderProcess
            property string buffer
            command: ["hyprctl", "-j", "getoption", "general:border_size"]
            running: false
            stdout: SplitParser { onRead: data => readBorderProcess.buffer += data }
            onRunningChanged: {
                if (!running) {
                    try {
                        const d = JSON.parse(readBorderProcess.buffer);
                        root.borderW = d.int ?? 1;
                    } catch (e) {}
                    readBorderProcess.buffer = "";
                }
            }
        }
    ]

    function applyGapsOut(): void {
        Hypr.extras.message(`[[BATCH]]eval hl.config({ general = { gaps_out = { top = ${outTop}, right = ${outRight}, bottom = ${outBottom}, left = ${outLeft} } } })`);
    }

    function applyGapsIn(): void {
        Hypr.extras.message(`[[BATCH]]eval hl.config({ general = { gaps_in = { top = ${inTop}, right = ${inRight}, bottom = ${inBottom}, left = ${inLeft} } } })`);
    }

    function applyBorder(): void {
        Hypr.extras.message(`[[BATCH]]eval hl.config({ general = { border_size = ${borderW} } })`);
    }

    function applyBarThickness(): void {
        const dir = `${Paths.config}/nord`;
        const content = JSON.stringify({sizes: {bar: {innerWidth: barThickness}}}, null, 2);
        Quickshell.execDetached(["sh", "-c", `mkdir -p "${dir}" && echo '${content}' > "${root.tokensPath}"`]);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.cappedWidth
        spacing: 0

        SectionHeader {
            first: true
            text: qsTr("Bar")
            Layout.bottomMargin: Tokens.spacing.extraSmall / 2
        }

        StepperRow {
            first: true
            last: true
            label: qsTr("Thickness")
            value: root.barThickness
            from: 24; to: 80; stepSize: 1
            onMoved: v => { root.barThickness = v; root.applyBarThickness(); }
        }

        SectionHeader {
            text: qsTr("Outer gaps")
            Layout.bottomMargin: Tokens.spacing.extraSmall / 2
            Layout.topMargin: Tokens.spacing.small
        }

        StepperRow {
            first: true
            label: qsTr("Top")
            value: root.outTop
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.outTop = v; root.applyGapsOut(); }
        }
        StepperRow {
            label: qsTr("Left")
            value: root.outLeft
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.outLeft = v; root.applyGapsOut(); }
        }
        StepperRow {
            label: qsTr("Bottom")
            value: root.outBottom
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.outBottom = v; root.applyGapsOut(); }
        }
        StepperRow {
            last: true
            label: qsTr("Right")
            value: root.outRight
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.outRight = v; root.applyGapsOut(); }
        }

        SectionHeader {
            text: qsTr("Inner gaps")
            Layout.bottomMargin: Tokens.spacing.extraSmall / 2
            Layout.topMargin: Tokens.spacing.small
        }

        StepperRow {
            first: true
            label: qsTr("Top")
            value: root.inTop
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.inTop = v; root.applyGapsIn(); }
        }
        StepperRow {
            label: qsTr("Left")
            value: root.inLeft
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.inLeft = v; root.applyGapsIn(); }
        }
        StepperRow {
            label: qsTr("Bottom")
            value: root.inBottom
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.inBottom = v; root.applyGapsIn(); }
        }
        StepperRow {
            last: true
            label: qsTr("Right")
            value: root.inRight
            from: 0; to: 200; stepSize: 1
            onMoved: v => { root.inRight = v; root.applyGapsIn(); }
        }

        SectionHeader {
            text: qsTr("Border")
            Layout.bottomMargin: Tokens.spacing.extraSmall / 2
            Layout.topMargin: Tokens.spacing.small
        }

        StepperRow {
            first: true
            last: true
            label: qsTr("Border width")
            value: root.borderW
            from: 0; to: 20; stepSize: 1
            onMoved: v => { root.borderW = v; root.applyBorder(); }
        }
    }
}
