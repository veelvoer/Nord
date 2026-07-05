pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property var allBindings: []
    property var luaBindingMap: ({})
    property int currentCategory: -1
    property bool listening: false
    property var listeningBinding: null
    property string listeningOldCombo: ""

    readonly property list<string> categoryNames: [
        qsTr("All"),
        qsTr("General"),
        qsTr("Window"),
        qsTr("Workspace"),
        qsTr("Media"),
        qsTr("Shell")
    ]

    readonly property var categoryIcons: ({
        "-1": "filter_list",
        "0": "apps",
        "1": "terminal",
        "2": "crop_square",
        "3": "view_carousel",
        "4": "volume_up",
        "5": "widgets"
    })

    readonly property var descriptionLookup: ({
        "q,64": qsTr("Open terminal"),
        ",64": qsTr("Toggle launcher"),
        "space,8": qsTr("Open application menu"),
        "c,64": qsTr("Close window"),
        "m,64": qsTr("Exit session"),
        "e,64": qsTr("Open file manager"),
        "v,64": qsTr("Toggle floating"),
        "p,64": qsTr("Toggle pseudo tiling"),
        "j,64": qsTr("Toggle split"),
        "left,64": qsTr("Focus left"),
        "right,64": qsTr("Focus right"),
        "up,64": qsTr("Focus up"),
        "down,64": qsTr("Focus down"),
        "tab,8": qsTr("Toggle scratchpad"),
        "s,65": qsTr("Move to scratchpad"),
        "1,64": qsTr("Switch to workspace 1"),
        "2,64": qsTr("Switch to workspace 2"),
        "3,64": qsTr("Switch to workspace 3"),
        "4,64": qsTr("Switch to workspace 4"),
        "5,64": qsTr("Switch to workspace 5"),
        "6,64": qsTr("Switch to workspace 6"),
        "7,64": qsTr("Switch to workspace 7"),
        "8,64": qsTr("Switch to workspace 8"),
        "9,64": qsTr("Switch to workspace 9"),
        "0,64": qsTr("Switch to workspace 10"),
        "1,65": qsTr("Move window to workspace 1"),
        "2,65": qsTr("Move window to workspace 2"),
        "3,65": qsTr("Move window to workspace 3"),
        "4,65": qsTr("Move window to workspace 4"),
        "5,65": qsTr("Move window to workspace 5"),
        "6,65": qsTr("Move window to workspace 6"),
        "7,65": qsTr("Move window to workspace 7"),
        "8,65": qsTr("Move window to workspace 8"),
        "9,65": qsTr("Move window to workspace 9"),
        "0,65": qsTr("Move window to workspace 10"),
        "mouse_down,64": qsTr("Scroll workspace down"),
        "mouse_up,64": qsTr("Scroll workspace up"),
        "mouse:272,64": qsTr("Drag window"),
        "mouse:273,64": qsTr("Resize window"),
        "xf86audioraisevolume,0": qsTr("Volume up"),
        "xf86audiolowervolume,0": qsTr("Volume down"),
        "xf86audiomute,0": qsTr("Toggle mute"),
        "xf86audiomicmute,0": qsTr("Toggle mic mute"),
        "xf86monbrightnessup,0": qsTr("Brightness up"),
        "xf86monbrightnessdown,0": qsTr("Brightness down"),
        "xf86audionext,0": qsTr("Next track"),
        "xf86audiopause,0": qsTr("Pause playback"),
        "xf86audioplay,0": qsTr("Play / Pause"),
        "xf86audioprev,0": qsTr("Previous track")
    })

    function lookupDescription(binding): string {
        if (binding.description)
            return binding.description;
        const d = binding.dispatcher;
        const a = binding.arg;
        if (d === "global" && a && descriptionLookup[a])
            return descriptionLookup[a];
        const comboKey = (binding.key ?? "").toLowerCase() + "," + (binding.modmask ?? 0);
        if (descriptionLookup[comboKey])
            return descriptionLookup[comboKey];
        if (descriptionLookup[d])
            return descriptionLookup[d];
        return formatDispatcher(binding);
    }

    function categorizeBinding(binding): int {
        const d = binding.dispatcher;
        if (d === "exec" || d === "execr")
            return 1;
        if (["closewindow", "float", "togglefloat", "pseudo", "fullscreen", "pin",
             "focuswindow", "focusurgentorlast", "killactive", "centerwindow",
             "setfloating", "settiled", "bringactivetotop"].includes(d)
            || d.startsWith("focus") || d.startsWith("move") || d.startsWith("layout")
            || d.startsWith("window") || d.startsWith("group") || d === "togglesplit"
            || d === "splitratio" || d === "splitswap" || d === "togglespecialworkspace")
            return 2;
        if (d.startsWith("workspace") || d === "movetoworkspace" || d === "movetoworkspacesilent"
            || d === "moveworkspace" || d === "focusworkspace")
            return 3;
        if (binding.key.startsWith("XF86") || d === "dpms" || d === "brightness" || d === "volume")
            return 4;
        if (d === "__lua") {
            const comboKey = (binding.key ?? "").toLowerCase() + "," + (binding.modmask ?? 0);
            const desc = descriptionLookup[comboKey] ?? "";
            if (desc.includes("volume") || desc.includes("brightness") || desc.includes("track") || desc.includes("playback") || desc.includes("mute"))
                return 4;
            if (desc.includes("workspace") || desc.includes("scratchpad"))
                return 3;
            if (desc.includes("terminal") || desc.includes("file manager") || desc.includes("launcher") || desc.includes("menu") || desc.includes("session") || desc.includes("exit"))
                return 0;
            if (desc.includes("focus") || desc.includes("window") || desc.includes("float") || desc.includes("pseudo") || desc.includes("split"))
                return 2;
        }
        return 5;
    }

    function formatMods(modmask): string {
        if (!modmask)
            return "";
        const mods = [];
        if (modmask & 1) mods.push("Shift");
        if (modmask & 4) mods.push("Ctrl");
        if (modmask & 8) mods.push("Alt");
        if (modmask & 64) mods.push("Super");
        return mods.join(" + ");
    }

    function modmaskToHlBindMods(modmask): string {
        if (!modmask)
            return "";
        const mods = [];
        if (modmask & 64) mods.push("SUPER");
        if (modmask & 8) mods.push("ALT");
        if (modmask & 4) mods.push("CTRL");
        if (modmask & 1) mods.push("SHIFT");
        return mods.join(" + ");
    }

    function bindingToHlKeyCombo(binding): string {
        const modStr = modmaskToHlBindMods(binding.modmask);
        let keyStr = binding.key;
        if (modStr && keyStr)
            return modStr + " + " + keyStr;
        if (modStr)
            return modStr;
        return keyStr;
    }

    function formatKeyCombo(binding): string {
        const modStr = formatMods(binding.modmask);
        let keyStr = binding.key;
        if (keyStr.length === 1)
            keyStr = keyStr.toUpperCase();
        if (modStr && keyStr)
            return modStr + " + " + keyStr;
        if (modStr)
            return modStr;
        return keyStr;
    }

    function formatDispatcher(binding): string {
        const d = binding.dispatcher;
        if (d === "global")
            return binding.arg;
        if (d === "exec" || d === "execr")
            return binding.arg;
        if (d === "__lua")
            return "";
        if (d === "focus" && binding.arg?.direction)
            return qsTr("Focus %1").arg(binding.arg.direction);
        if (d === "workspace" && binding.arg?.name)
            return qsTr("Workspace %1").arg(binding.arg.name);
        if (d === "movetoworkspace" && binding.arg?.name)
            return qsTr("Move to workspace %1").arg(binding.arg.name);
        if (d === "togglespecialworkspace" && binding.arg?.name)
            return qsTr("Toggle %1").arg(binding.arg.name);
        if (binding.arg && typeof binding.arg === "object")
            return d + " " + JSON.stringify(binding.arg);
        if (binding.arg)
            return d + " " + binding.arg;
        return d;
    }

    function getFilteredBindings(): var {
        const result = [];
        for (const b of allBindings) {
            if (currentCategory === -1 || categorizeBinding(b) === currentCategory)
                result.push(b);
        }
        return result;
    }

    function saveBinding(oldBinding, newKeyCombo) {
        const hlCombo = bindingToHlKeyCombo(oldBinding);
        const luaInfo = luaBindingMap[hlCombo.toLowerCase()];
        if (!luaInfo) {
            statusText.text = qsTr("Cannot rebind: no Lua expression found");
            return;
        }
        let bindExpr = `hl.bind("${newKeyCombo}", ${luaInfo.dispatcher}`;
        if (luaInfo.flags)
            bindExpr += `, ${luaInfo.flags}`;
        bindExpr += ")";
        unbindProc.command = ["hyprctl", "eval", `hl.unbind("${hlCombo}")`];
        unbindProc.running = true;
        bindProc.command = ["hyprctl", "eval", bindExpr];
        bindProc.running = true;
        reloadTimer.restart();
        statusText.text = qsTr("Rebound to %1").arg(newKeyCombo);
    }

    title: qsTr("Shortcuts")

    focus: root.listening
    Keys.enabled: root.listening
    Keys.onPressed: event => {
        if (!root.listening)
            return;

        let modStr = "";
        const mods = [];
        if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT");
        if (event.modifiers & Qt.ControlModifier) mods.push("CTRL");
        if (event.modifiers & Qt.AltModifier) mods.push("ALT");
        if (event.modifiers & Qt.MetaModifier) mods.push("SUPER");
        modStr = mods.join(" + ");

        let keyStr = "";
        const keyMap = ({
            [Qt.Key_Left]: "left",
            [Qt.Key_Right]: "right",
            [Qt.Key_Up]: "up",
            [Qt.Key_Down]: "down",
            [Qt.Key_Space]: "Space",
            [Qt.Key_Tab]: "Tab",
            [Qt.Key_Backtab]: "Tab",
            [Qt.Key_Escape]: "",
            [Qt.Key_Return]: "Return",
            [Qt.Key_Backspace]: "BackSpace",
            [Qt.Key_Delete]: "Delete",
            [Qt.Key_Insert]: "Insert",
            [Qt.Key_Home]: "Home",
            [Qt.Key_End]: "End",
            [Qt.Key_PageUp]: "Page_Up",
            [Qt.Key_PageDown]: "Page_Down",
        });

        if (keyMap[event.key] !== undefined) {
            keyStr = keyMap[event.key];
        } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F35) {
            keyStr = "F" + (event.key - Qt.Key_F1 + 1);
        } else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
            keyStr = String.fromCharCode(event.key + 32);
        } else if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
            keyStr = String.fromCharCode(event.key);
        } else {
            keyStr = event.text || "";
        }

        if (event.key === Qt.Key_Escape) {
            root.listening = false;
            root.listeningBinding = null;
            statusText.text = qsTr("%1 shortcuts").arg(root.getFilteredBindings().length);
            return;
        }

        if (!keyStr)
            return;

        let newCombo = "";
        if (modStr && keyStr)
            newCombo = modStr + " + " + keyStr;
        else if (modStr)
            newCombo = modStr;
        else
            newCombo = keyStr;

        if (root.listeningBinding) {
            saveBinding(root.listeningBinding, newCombo);
            root.listening = false;
            root.listeningBinding = null;
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: bindsProcess

            running: true
            command: ["hyprctl", "binds", "-j"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const parsed = JSON.parse(text);
                        root.allBindings = parsed.filter(b => {
                            const k = (b.key ?? "").toLowerCase();
                            if (!k && !b.modmask) return false;
                            if (k === "caps_lock" || k === "num_lock") return false;
                            if (b.key.startsWith("mouse")) return false;
                            if (!b.dispatcher) return false;
                            return true;
                        });
                    } catch (e) {
                        root.allBindings = [];
                    }
                }
            }
        }

        Process {
            id: luaProcess

            running: true
            command: ["python3", "/home/warre/.config/quickshell/caelestia/scripts/parse_binds.py", "/home/warre/.config/hypr/hyprland.lua"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        const arr = JSON.parse(text);
                        const map = {};
                        for (const entry of arr) {
                            map[entry.key.toLowerCase()] = {
                                dispatcher: entry.dispatcher,
                                flags: entry.flags
                            };
                        }
                        root.luaBindingMap = map;
                    } catch (e) {
                        root.luaBindingMap = {};
                    }
                }
            }
        }

        Process {
            id: unbindProc

            running: false
        }

        Process {
            id: bindProc

            running: false
        }

        Timer {
            id: reloadTimer

            interval: 300
            onTriggered: {
                bindsProcess.running = false;
                bindsProcess.running = true;
            }
        }

        // Category tabs
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Repeater {
                model: [qsTr("All"), ...root.categoryNames.slice(1)]

                delegate: StyledRect {
                    required property string modelData
                    required property int index

                    property int catIndex: index - 1

                    implicitWidth: catRow.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: 36
                    radius: Tokens.rounding.full
                    color: root.currentCategory === catIndex ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHigh

                    TapHandler {
                        onTapped: root.currentCategory = parent.catIndex
                    }

                    RowLayout {
                        id: catRow

                        anchors.centerIn: parent
                        spacing: Tokens.spacing.extraSmall

                        MaterialIcon {
                            text: root.categoryIcons[parent.parent.catIndex]
                            color: root.currentCategory === parent.parent.catIndex ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }

                        StyledText {
                            text: modelData
                            color: root.currentCategory === parent.parent.catIndex ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.medium
                        }
                    }
                }
            }
        }

        // Divider
        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            Layout.bottomMargin: Tokens.spacing.extraSmall
            implicitHeight: 1
            color: Colours.palette.m3outlineVariant
        }

        // Binding list
        Repeater {
            model: root.getFilteredBindings()

            delegate: ConnectedRect {
                id: rowDelegate

                required property var modelData
                required property int index

                readonly property string description: root.lookupDescription(rowDelegate.modelData)
                readonly property string keyCombo: root.formatKeyCombo(rowDelegate.modelData)
                readonly property bool hasLuaBinding: root.luaBindingMap[root.bindingToHlKeyCombo(rowDelegate.modelData).toLowerCase()] !== undefined
                readonly property bool isListening: root.listening && root.listeningBinding === rowDelegate.modelData

                Layout.fillWidth: true
                first: index === 0
                last: index === root.getFilteredBindings().length - 1
                color: isListening ? Colours.tPalette.m3primaryContainer : Colours.tPalette.m3surfaceContainer

                implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2

                RowLayout {
                    id: rowLayout

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: root.categoryIcons[root.categorizeBinding(rowDelegate.modelData)]
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: rowDelegate.description
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                            color: Colours.palette.m3onSurface
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: false
                        implicitWidth: kbText.implicitWidth + Tokens.padding.large * 2
                        implicitHeight: kbText.implicitHeight + Tokens.padding.small * 2
                        radius: Tokens.rounding.small
                        color: rowDelegate.isListening ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHigh

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: rowDelegate.hasLuaBinding ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: rowDelegate.hasLuaBinding && !root.listening

                            onClicked: {
                                root.listening = true;
                                root.listeningBinding = rowDelegate.modelData;
                                statusText.text = qsTr("Press a new key combination...");
                                root.forceActiveFocus();
                            }
                        }

                        StyledText {
                            id: kbText

                            anchors.centerIn: parent
                            text: rowDelegate.isListening ? qsTr("Press a key...") : rowDelegate.keyCombo
                            color: rowDelegate.isListening ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            font: Qt.font({
                                family: root.font.family,
                                pointSize: Tokens.font.label.medium.pointSize,
                                weight: Font.DemiBold,
                                letterSpacing: 1
                            })
                        }
                    }
                }
            }
        }

        // Status bar
        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            implicitHeight: statusText.implicitHeight + Tokens.padding.small * 2
            color: "transparent"

            StyledText {
                id: statusText

                anchors.centerIn: parent
                text: qsTr("%1 shortcuts").arg(root.getFilteredBindings().length)
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
            }
        }
    }
}
