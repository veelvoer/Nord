pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Nord.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Themes")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: 0

        SectionHeader {
            first: true
            text: qsTr("Appearance theme")
            Layout.bottomMargin: Tokens.spacing.extraSmall / 2
        }

        ThemeCard {
            first: true
            themeName: "default"
            label: qsTr("Default")
            description: qsTr("Current wallpaper-derived colour scheme")
            swatches: [
                Colours.current.m3primary,
                Colours.current.m3secondary,
                Colours.current.m3tertiary,
                Colours.current.m3surfaceContainer,
                Colours.current.m3surfaceContainerHighest
            ]
        }

        ThemeCard {
            themeName: "nord"
            label: "Nord"
            description: qsTr("Clean, elegant dark theme with frost accents")
            swatches: [
                "#5E81AC",
                "#81A1C1",
                "#88C0D0",
                "#8FBCBB",
                "#A3BE8C"
            ]
        }

        ThemeCard {
            themeName: "aurora"
            label: "Aurora"
            description: qsTr("Northern lights — deep teal with cyan glow")
            swatches: [
                "#0D9488",
                "#14B8A6",
                "#2DD4BF",
                "#5EEAD4",
                "#99F6E4"
            ]
        }

        ThemeCard {
            themeName: "obsidian"
            label: "Obsidian"
            description: qsTr("Volcanic glass — cool blue on deep black")
            swatches: [
                "#1E40AF",
                "#2563EB",
                "#3B82F6",
                "#60A5FA",
                "#93C5FD"
            ]
        }

        ThemeCard {
            last: true
            themeName: "sakura"
            label: "Sakura"
            description: qsTr("Cherry blossoms — soft pink gradient")
            swatches: [
                "#BE185D",
                "#EC4899",
                "#F472B6",
                "#F9A8D4",
                "#FBCFE8"
            ]
        }
    }

    component ThemeCard: StyledRect {
        id: card

        required property string themeName
        required property string label
        required property string description
        required property list<color> swatches
        property bool first
        property bool last

        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall / 2
        implicitHeight: layout.implicitHeight + layout.anchors.margins * 2

        color: isActive ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
        topLeftRadius: first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        topRightRadius: first ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomLeftRadius: last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall
        bottomRightRadius: last ? Tokens.rounding.extraLarge : Tokens.rounding.extraSmall

        readonly property bool isActive: Colours.currentTheme === card.themeName

        border.width: isActive ? 2 : 0
        border.color: Colours.palette.m3primary

        Behavior on border.color {
            ColorAnimation {
                duration: 200
                easing: Easing.InOutQuad
            }
        }

        StateLayer {
            id: stateLayer

            anchors.fill: parent
            topLeftRadius: card.topLeftRadius
            topRightRadius: card.topRightRadius
            bottomLeftRadius: card.bottomLeftRadius
            bottomRightRadius: card.bottomRightRadius

            onClicked: Colours.setTheme(card.themeName)
        }

        RowLayout {
            id: layout

            anchors.fill: parent
            anchors.margins: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.large

            // Colour swatches
            Row {
                spacing: Tokens.spacing.extraSmall

                Repeater {
                    model: card.swatches

                    StyledRect {
                        required property color modelData
                        required property int index

                        implicitWidth: 28
                        implicitHeight: 28
                        radius: Tokens.rounding.full
                        color: modelData

                        Behavior on color {
                            CAnim {}
                        }
                    }
                }
            }

            // Label + description
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: card.label
                    font: Tokens.font.body.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.description
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            // Selection indicator
            MaterialIcon {
                text: card.isActive ? "radio_button_checked" : "radio_button_unchecked"
                color: card.isActive ? Colours.palette.m3primary : Colours.palette.m3outline
                fontStyle: Tokens.font.icon.medium

                Behavior on color {
                    CAnim {}
                }
            }
        }
    }
}
