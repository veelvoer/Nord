pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Nord
import Nord.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property bool showPreview
    property string scheme
    property string flavour
    property bool currentLight
    property bool previewLight

    // Theme management
    property string currentTheme: "default"
    readonly property M3Palette nordPalette: NordTheme {}
    readonly property M3Palette auroraPalette: AuroraTheme {}
    readonly property M3Palette obsidianPalette: ObsidianTheme {}
    readonly property M3Palette sakuraPalette: SakuraTheme {}

    readonly property bool light: showPreview ? previewLight : (currentTheme === "sakura" ? true : currentLight)

    readonly property M3Palette palette: showPreview ? preview : activePalette
    readonly property M3Palette activePalette: {
        switch (currentTheme) {
        case "nord": return nordPalette;
        case "aurora": return auroraPalette;
        case "obsidian": return obsidianPalette;
        case "sakura": return sakuraPalette;
        default: return current;
        }
    }
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property M3Palette preview: M3Palette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance

    property bool cooldownPending
    property real lastBaseTransparency

    function setTheme(themeName: string): void {
        if (currentTheme === themeName)
            return;
        currentTheme = themeName;
        saveTheme(themeName);
        // Sync system-wide light/dark mode
        if (themeName === "sakura")
            setMode("light");
        else
            setMode("dark");
    }

    function saveTheme(themeName: string): void {
        const themeDir = `${Paths.state}`;
        Quickshell.execDetached(["mkdir", "-p", themeDir]);
        const content = JSON.stringify({name: themeName}, null, 2);
        // Write via a temporary process since we can't write files directly from QML
        Quickshell.execDetached(["sh", "-c", `echo '${content}' > "${themeDir}/theme.json"`]);
    }

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    function load(data: string, isPreview: bool): void {
        const colours = isPreview ? preview : current;
        const scheme = JSON.parse(data);

        if (!isPreview) {
            root.scheme = scheme.name;
            flavour = scheme.flavour;
            currentLight = scheme.mode === "light";
        } else {
            previewLight = scheme.mode === "light";
        }

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }
    }

    function setMode(mode: string): void {
        Quickshell.execDetached(["nord", "scheme", "set", "--notify", "-m", mode]);
    }

    function reloadHyprRules(): void {
        let rule, trEnabled;
        if (Hypr.usingLua) {
            rule = `eval hl.layer_rule({ match = { namespace = "nord-drawers" }, %1 = %2 })`;
            trEnabled = transparency.enabled;
        } else {
            rule = "keyword layerrule %1 %2, match:namespace nord-drawers";
            trEnabled = transparency.enabled ? 1 : 0;
        }
        Hypr.extras.batchMessage([rule.arg("blur").arg(trEnabled), rule.arg("ignore_alpha").arg(Math.max(0, transparency.base - 0.03))]);
    }

    function requestReloadHyprRules(): void {
        if (cooldownTimer.running) {
            root.cooldownPending = true;
        } else {
            root.reloadHyprRules();
            cooldownTimer.restart();
        }
    }

    Component.onCompleted: root.requestReloadHyprRules()

    Connections {
        function onConfigReloaded(): void {
            root.reloadHyprRules();
        }

        target: Hypr
    }

    FileView {
        path: `${Paths.state}/scheme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.load(text(), false)
    }

    FileView {
        id: themeFile

        path: `${Paths.state}/theme.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                if (data.name && ["default", "nord", "aurora", "obsidian", "sakura"].includes(data.name)) {
                    root.currentTheme = data.name;
                    // Sync system-wide light/dark mode on startup
                    if (data.name === "sakura")
                        root.setMode("light");
                }
            } catch (e) {
                // Ignore parse errors, keep default theme
            }
        }
    }

    ImageAnalyser {
        id: analyser

        source: Wallpapers.current
    }

    Timer {
        id: cooldownTimer

        interval: 30
        onTriggered: {
            if (root.cooldownPending) {
                root.cooldownPending = false;
                root.reloadHyprRules();
                restart();
            }
        }
    }

    Timer {
        id: cAnimCompleteTimer

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: root.requestReloadHyprRules()
    }

    component NordTheme: M3Palette {
        // Nord Frost (accent) – used sparingly as primary
        m3primary_paletteKeyColor: "#88C0D0"
        m3secondary_paletteKeyColor: "#81A1C1"
        m3tertiary_paletteKeyColor: "#5E81AC"
        m3neutral_paletteKeyColor: "#3B4252"
        m3neutral_variant_paletteKeyColor: "#434C5E"

        // Background
        m3background: "#2E3440"
        m3onBackground: "#ECEFF4"

        // Surface
        m3surface: "#2E3440"
        m3surfaceDim: "#2E3440"
        m3surfaceBright: "#3B4252"
        m3surfaceContainerLowest: "#242933"
        m3surfaceContainerLow: "#323845"
        m3surfaceContainer: "#3B4252"
        m3surfaceContainerHigh: "#434C5E"
        m3surfaceContainerHighest: "#4C566A"

        // On-surface
        m3onSurface: "#ECEFF4"
        m3surfaceVariant: "#434C5E"
        m3onSurfaceVariant: "#D8DEE9"

        // Inverse
        m3inverseSurface: "#ECEFF4"
        m3inverseOnSurface: "#2E3440"

        // Outline
        m3outline: "#7B88A1"
        m3outlineVariant: "#4C566A"

        // Shadow & scrim
        m3shadow: "#1A1E28"
        m3scrim: "#1A1E28"
        m3surfaceTint: "#88C0D0"

        // Primary (Nord Frost – accent only)
        m3primary: "#88C0D0"
        m3onPrimary: "#1F2B33"
        m3primaryContainer: "#2E5A66"
        m3onPrimaryContainer: "#D8EEF4"
        m3inversePrimary: "#5E81AC"

        // Secondary (Nord Frost lighter)
        m3secondary: "#81A1C1"
        m3onSecondary: "#1E2A38"
        m3secondaryContainer: "#3A5068"
        m3onSecondaryContainer: "#D8E4F0"

        // Tertiary (Nord Storm)
        m3tertiary: "#5E81AC"
        m3onTertiary: "#1A2636"
        m3tertiaryContainer: "#3A5470"
        m3onTertiaryContainer: "#D0DFEF"

        // Error
        m3error: "#BF616A"
        m3onError: "#2A1215"
        m3errorContainer: "#6D2A2F"
        m3onErrorContainer: "#FFDAD6"

        // Success
        m3success: "#A3BE8C"
        m3onSuccess: "#1A2B12"
        m3successContainer: "#3A5430"
        m3onSuccessContainer: "#D4E9CA"

        // Fixed
        m3primaryFixed: "#D8EEF4"
        m3primaryFixedDim: "#88C0D0"
        m3onPrimaryFixed: "#0D1B22"
        m3onPrimaryFixedVariant: "#2E5A66"
        m3secondaryFixed: "#D8E4F0"
        m3secondaryFixedDim: "#81A1C1"
        m3onSecondaryFixed: "#141E2A"
        m3onSecondaryFixedVariant: "#3A5068"
        m3tertiaryFixed: "#D0DFEF"
        m3tertiaryFixedDim: "#5E81AC"
        m3onTertiaryFixed: "#101C28"
        m3onTertiaryFixedVariant: "#3A5470"

        // Nord terminal palette
        term0: "#3B4252"
        term1: "#BF616A"
        term2: "#A3BE8C"
        term3: "#EBCB8B"
        term4: "#81A1C1"
        term5: "#B48EAD"
        term6: "#88C0D0"
        term7: "#E5E9F0"
        term8: "#4C566A"
        term9: "#BF616A"
        term10: "#A3BE8C"
        term11: "#EBCB8B"
        term12: "#81A1C1"
        term13: "#B48EAD"
        term14: "#88C0D0"
        term15: "#ECEFF4"
    }

    component AuroraTheme: M3Palette {
        // Aurora palette key colors
        m3primary_paletteKeyColor: "#0D9488"
        m3secondary_paletteKeyColor: "#14B8A6"
        m3tertiary_paletteKeyColor: "#2DD4BF"
        m3neutral_paletteKeyColor: "#1F2937"
        m3neutral_variant_paletteKeyColor: "#263447"

        // Background
        m3background: "#111827"
        m3onBackground: "#F8FAFC"

        // Surface
        m3surface: "#111827"
        m3surfaceDim: "#0F1520"
        m3surfaceBright: "#1F2937"
        m3surfaceContainerLowest: "#0C1018"
        m3surfaceContainerLow: "#182030"
        m3surfaceContainer: "#1F2937"
        m3surfaceContainerHigh: "#263447"
        m3surfaceContainerHighest: "#2E3D52"

        // On-surface
        m3onSurface: "#F8FAFC"
        m3surfaceVariant: "#263447"
        m3onSurfaceVariant: "#CBD5E1"

        // Inverse
        m3inverseSurface: "#F8FAFC"
        m3inverseOnSurface: "#111827"

        // Outline
        m3outline: "#475569"
        m3outlineVariant: "#2E3D52"

        // Shadow & scrim
        m3shadow: "#060A12"
        m3scrim: "#060A12"
        m3surfaceTint: "#0D9488"

        // Primary (Teal)
        m3primary: "#0D9488"
        m3onPrimary: "#042F2E"
        m3primaryContainer: "#0F5E54"
        m3onPrimaryContainer: "#9FD6CD"
        m3inversePrimary: "#5EEAD4"

        // Secondary (Teal lighter)
        m3secondary: "#14B8A6"
        m3onSecondary: "#042F2E"
        m3secondaryContainer: "#0D5E50"
        m3onSecondaryContainer: "#A7F3D0"

        // Tertiary (Cyan)
        m3tertiary: "#2DD4BF"
        m3onTertiary: "#042F2E"
        m3tertiaryContainer: "#0D5E54"
        m3onTertiaryContainer: "#B2F5EA"

        // Error
        m3error: "#F87171"
        m3onError: "#450A0A"
        m3errorContainer: "#7F1D1D"
        m3onErrorContainer: "#FECACA"

        // Success
        m3success: "#34D399"
        m3onSuccess: "#064E3B"
        m3successContainer: "#065F46"
        m3onSuccessContainer: "#A7F3D0"

        // Fixed
        m3primaryFixed: "#9FD6CD"
        m3primaryFixedDim: "#0D9488"
        m3onPrimaryFixed: "#031E1D"
        m3onPrimaryFixedVariant: "#0F5E54"
        m3secondaryFixed: "#A7F3D0"
        m3secondaryFixedDim: "#14B8A6"
        m3onSecondaryFixed: "#031E1E"
        m3onSecondaryFixedVariant: "#0D5E50"
        m3tertiaryFixed: "#B2F5EA"
        m3tertiaryFixedDim: "#2DD4BF"
        m3onTertiaryFixed: "#031E1E"
        m3onTertiaryFixedVariant: "#0D5E54"

        // Aurora terminal palette
        term0: "#1F2937"
        term1: "#F87171"
        term2: "#34D399"
        term3: "#FBBF24"
        term4: "#60A5FA"
        term5: "#2DD4BF"
        term6: "#0D9488"
        term7: "#F1F5F9"
        term8: "#475569"
        term9: "#FB7185"
        term10: "#6EE7B7"
        term11: "#FDE68A"
        term12: "#93C5FD"
        term13: "#5EEAD4"
        term14: "#14B8A6"
        term15: "#F8FAFC"
    }

    component ObsidianTheme: M3Palette {
        // Obsidian palette key colors
        m3primary_paletteKeyColor: "#3B82F6"
        m3secondary_paletteKeyColor: "#818CF8"
        m3tertiary_paletteKeyColor: "#60A5FA"
        m3neutral_paletteKeyColor: "#121212"
        m3neutral_variant_paletteKeyColor: "#232323"

        // Background
        m3background: "#050505"
        m3onBackground: "#FFFFFF"

        // Surface
        m3surface: "#050505"
        m3surfaceDim: "#030303"
        m3surfaceBright: "#0B0B0B"
        m3surfaceContainerLowest: "#020202"
        m3surfaceContainerLow: "#080808"
        m3surfaceContainer: "#0B0B0B"
        m3surfaceContainerHigh: "#121212"
        m3surfaceContainerHighest: "#1A1A1A"

        // On-surface
        m3onSurface: "#FFFFFF"
        m3surfaceVariant: "#232323"
        m3onSurfaceVariant: "#CFCFCF"

        // Inverse
        m3inverseSurface: "#FFFFFF"
        m3inverseOnSurface: "#050505"

        // Outline
        m3outline: "#525252"
        m3outlineVariant: "#232323"

        // Shadow & scrim
        m3shadow: "#000000"
        m3scrim: "#000000"
        m3surfaceTint: "#3B82F6"

        // Primary (Electric Blue)
        m3primary: "#3B82F6"
        m3onPrimary: "#0A1A3A"
        m3primaryContainer: "#152D5A"
        m3onPrimaryContainer: "#BFDBFE"
        m3inversePrimary: "#2563EB"

        // Secondary (Indigo)
        m3secondary: "#818CF8"
        m3onSecondary: "#1A0F44"
        m3secondaryContainer: "#2E2070"
        m3onSecondaryContainer: "#DDD6FE"

        // Tertiary (Light Blue)
        m3tertiary: "#60A5FA"
        m3onTertiary: "#0A1A3A"
        m3tertiaryContainer: "#152D5A"
        m3onTertiaryContainer: "#BFDBFE"

        // Error
        m3error: "#EF4444"
        m3onError: "#450A0A"
        m3errorContainer: "#7F1D1D"
        m3onErrorContainer: "#FECACA"

        // Success
        m3success: "#22C55E"
        m3onSuccess: "#052E16"
        m3successContainer: "#0D5E2F"
        m3onSuccessContainer: "#BBF7D0"

        // Fixed
        m3primaryFixed: "#BFDBFE"
        m3primaryFixedDim: "#3B82F6"
        m3onPrimaryFixed: "#040D1F"
        m3onPrimaryFixedVariant: "#152D5A"
        m3secondaryFixed: "#DDD6FE"
        m3secondaryFixedDim: "#818CF8"
        m3onSecondaryFixed: "#0E0522"
        m3onSecondaryFixedVariant: "#2E2070"
        m3tertiaryFixed: "#BFDBFE"
        m3tertiaryFixedDim: "#60A5FA"
        m3onTertiaryFixed: "#040D1F"
        m3onTertiaryFixedVariant: "#152D5A"

        // Obsidian terminal palette
        term0: "#121212"
        term1: "#EF4444"
        term2: "#22C55E"
        term3: "#EAB308"
        term4: "#3B82F6"
        term5: "#818CF8"
        term6: "#60A5FA"
        term7: "#F4F4F5"
        term8: "#525252"
        term9: "#F87171"
        term10: "#4ADE80"
        term11: "#FACC15"
        term12: "#60A5FA"
        term13: "#A5B4FC"
        term14: "#93C5FD"
        term15: "#FFFFFF"
    }

    component SakuraTheme: M3Palette {
        // Sakura palette key colors
        m3primary_paletteKeyColor: "#EC4899"
        m3secondary_paletteKeyColor: "#F472B6"
        m3tertiary_paletteKeyColor: "#F9A8D4"
        m3neutral_paletteKeyColor: "#F4EFEE"
        m3neutral_variant_paletteKeyColor: "#E8E0DF"

        // Background
        m3background: "#FAF7F6"
        m3onBackground: "#1C1917"

        // Surface
        m3surface: "#FAF7F6"
        m3surfaceDim: "#E8E2E1"
        m3surfaceBright: "#FFFFFF"
        m3surfaceContainerLowest: "#FFFFFF"
        m3surfaceContainerLow: "#F7F2F1"
        m3surfaceContainer: "#F1ECEB"
        m3surfaceContainerHigh: "#EBE5E4"
        m3surfaceContainerHighest: "#DFD9D8"

        // On-surface
        m3onSurface: "#1C1917"
        m3surfaceVariant: "#E7E0E0"
        m3onSurfaceVariant: "#49454F"

        // Inverse
        m3inverseSurface: "#313033"
        m3inverseOnSurface: "#F4EFF4"

        // Outline
        m3outline: "#79747E"
        m3outlineVariant: "#CAC4CF"

        // Shadow & scrim
        m3shadow: "#000000"
        m3scrim: "#000000"
        m3surfaceTint: "#EC4899"

        // Primary (Cherry Blossom Pink)
        m3primary: "#BE185D"
        m3onPrimary: "#FFFFFF"
        m3primaryContainer: "#FDD5EB"
        m3onPrimaryContainer: "#5B0E2E"
        m3inversePrimary: "#F472B6"

        // Secondary (Rose)
        m3secondary: "#9D174D"
        m3onSecondary: "#FFFFFF"
        m3secondaryContainer: "#FCE7F3"
        m3onSecondaryContainer: "#5B0E2E"

        // Tertiary (Light Pink)
        m3tertiary: "#831843"
        m3onTertiary: "#FFFFFF"
        m3tertiaryContainer: "#FDF2F8"
        m3onTertiaryContainer: "#5B0E2E"

        // Error
        m3error: "#BA1A1A"
        m3onError: "#FFFFFF"
        m3errorContainer: "#FFDAD6"
        m3onErrorContainer: "#410002"

        // Success
        m3success: "#006D3B"
        m3onSuccess: "#FFFFFF"
        m3successContainer: "#C3F2B0"
        m3onSuccessContainer: "#00210E"

        // Fixed
        m3primaryFixed: "#FDD5EB"
        m3primaryFixedDim: "#EC4899"
        m3onPrimaryFixed: "#380718"
        m3onPrimaryFixedVariant: "#5B0E2E"
        m3secondaryFixed: "#FCE7F3"
        m3secondaryFixedDim: "#F472B6"
        m3onSecondaryFixed: "#380718"
        m3onSecondaryFixedVariant: "#5B0E2E"
        m3tertiaryFixed: "#FDF2F8"
        m3tertiaryFixedDim: "#F9A8D4"
        m3onTertiaryFixed: "#380718"
        m3onTertiaryFixedVariant: "#5B0E2E"

        // Sakura terminal palette
        term0: "#E8E0DF"
        term1: "#F472B6"
        term2: "#10B981"
        term3: "#F59E0B"
        term4: "#60A5FA"
        term5: "#EC4899"
        term6: "#F9A8D4"
        term7: "#FAF7F6"
        term8: "#B8B0AE"
        term9: "#BE185D"
        term10: "#34D399"
        term11: "#FBBF24"
        term12: "#3B82F6"
        term13: "#DB2777"
        term14: "#FBCFE8"
        term15: "#FFFFFF"
    }

    component Transparency: QtObject {
        readonly property bool enabled: Tokens.transparency.enabled
        readonly property real base: Math.max(0, Math.min(1, Tokens.transparency.base - (root.light ? 0.1 : 0)))
        readonly property real layers: Math.max(0, Math.min(1, Tokens.transparency.layers))

        onEnabledChanged: {
            if (enabled)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
        }
        onBaseChanged: {
            if (root.lastBaseTransparency > base)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
            root.lastBaseTransparency = base;
        }
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
        property color term0: "#353434"
        property color term1: "#ff4c8a"
        property color term2: "#ffbbb7"
        property color term3: "#ffdedf"
        property color term4: "#b3a2d5"
        property color term5: "#e98fb0"
        property color term6: "#ffba93"
        property color term7: "#eed1d2"
        property color term8: "#b39e9e"
        property color term9: "#ff80a3"
        property color term10: "#ffd3d0"
        property color term11: "#fff1f0"
        property color term12: "#dcbc93"
        property color term13: "#f9a8c2"
        property color term14: "#ffd1c0"
        property color term15: "#ffffff"
    }
}
