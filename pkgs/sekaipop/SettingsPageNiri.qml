import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

// Niri's half of the phone's Settings, in place of SettingsPageHyprland when
// NiriWorkspaces.running (SettingsFace.qml picks one). There is no niri IPC
// for input settings, so this page is deliberately small: outputs, keyboard
// layouts, and buttons that point at where the real config lives.
//
// Output changes use `niri msg output`, which is TEMPORARY by niri's own
// documentation: nothing is written to config.kdl, which is a Nix store
// symlink here. The note card says so rather than pretending otherwise.
SettingsPage {
    id: page

    // Parsed JSON, refreshed on open, every 3 s while visible, and after
    // every change (the reply has no output-event stream on this side).
    property var outputs: ({})
    property var layoutNames: []

    function outputNames() {
        return Object.keys(page.outputs)
    }

    // args is the rest of `niri msg output <name> ...`, e.g. ["scale", "1.25"]
    function setOutput(name, args) {
        Quickshell.execDetached(["niri", "msg", "output", name].concat(args))
        refresh.restart()
    }

    function modeId(mode) {
        return mode.width + "x" + mode.height + "@" + (mode.refresh_rate / 1000)
    }

    function modeLabel(mode) {
        return mode.width + "×" + mode.height + " · " + Math.round(mode.refresh_rate / 1000) + " Hz"
    }

    function currentModeId(output) {
        if (output.current_mode === null || output.current_mode === undefined)
            return ""
        const mode = output.modes[output.current_mode]
        return mode ? page.modeId(mode) : ""
    }

    Timer {
        id: refresh
        interval: 400
        onTriggered: outputsProcess.running = true
    }

    Timer {
        interval: 3000
        repeat: true
        running: page.visible
        onTriggered: outputsProcess.running = true
    }

    Process {
        id: outputsProcess
        command: ["niri", "msg", "--json", "outputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.outputs = JSON.parse(text)
                } catch (e) {
                    page.outputs = ({})
                }
            }
        }
    }

    Process {
        id: layoutsProcess
        command: ["niri", "msg", "--json", "keyboard-layouts"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.layoutNames = JSON.parse(text).names
                } catch (e) {
                    page.layoutNames = []
                }
            }
        }
    }

    Component.onCompleted: {
        outputsProcess.running = true
        layoutsProcess.running = true
    }

    SectionCard {
        title: "Displays"

        Repeater {
            model: page.outputNames()

            delegate: Column {
                id: outputColumn
                required property var modelData

                readonly property var output: page.outputs[modelData] || ({})
                readonly property var logical: output.logical || null

                width: page.fullWidth
                spacing: 10

                SettingToggle {
                    tileWidth: page.fullWidth
                    icon: "monitor"
                    label: outputColumn.modelData
                    detail: (outputColumn.output.make || "") + " " + (outputColumn.output.model || "")
                    checked: outputColumn.logical !== null
                    onToggled: page.setOutput(outputColumn.modelData,
                        [outputColumn.logical !== null ? "off" : "on"])
                }

                SettingChoice {
                    visible: outputColumn.logical !== null
                    label: "Mode"
                    options: (outputColumn.output.modes || []).map(m => ({
                        id: page.modeId(m), label: page.modeLabel(m)
                    }))
                    current: page.currentModeId(outputColumn.output)
                    onPicked: id => page.setOutput(outputColumn.modelData, ["mode", id])
                }

                SettingChoice {
                    visible: outputColumn.logical !== null
                    label: "Scale"
                    options: [ "1", "1.25", "1.5", "1.75", "2" ].map(s => ({ id: s, label: s + "×" }))
                    current: outputColumn.logical ? String(outputColumn.logical.scale) : ""
                    onPicked: id => page.setOutput(outputColumn.modelData, ["scale", id])
                }
            }
        }

        Text {
            width: page.fullWidth
            text: "These last until the session ends — niri does not write them to your config. To keep a mode or scale, edit home/modules/niri.nix and rebuild."
            color: Theme.pInkSub
            font.family: Theme.fontFamily
            font.pixelSize: 14
            wrapMode: Text.WordWrap
        }
    }

    SectionCard {
        title: "Keyboard"

        Text {
            width: page.fullWidth
            text: page.layoutNames.length > 0
                ? "Layouts: " + page.layoutNames.join(" · ")
                : "niri reported no keyboard layouts"
            color: Theme.pInk
            font.family: Theme.fontFamily
            font.pixelSize: 16
            wrapMode: Text.WordWrap
        }

        SettingAction {
            tileWidth: page.fullWidth
            icon: "code"
            label: "Edit niri config"
            detail: "home/modules/niri.nix"
            onActivated: Quickshell.execDetached(
                ["kitty", "-e", "nvim", "/home/thedreamdev/nixos-config/home/modules/niri.nix"])
        }

        SettingAction {
            tileWidth: page.fullWidth
            icon: "refresh"
            label: "Reload config"
            detail: "After editing the file outside a rebuild"
            onActivated: Quickshell.execDetached(["niri", "msg", "action", "load-config-file"])
        }
    }

    SectionCard {
        title: "Noctalia"

        SettingAction {
            tileWidth: page.fullWidth
            icon: "settings"
            label: "Noctalia settings"
            detail: "Bar, dock, launcher, colours"
            onActivated: Quickshell.execDetached(["noctalia", "msg", "settings-toggle"])
        }
    }
}
