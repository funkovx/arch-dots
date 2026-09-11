-- ~/.config/hypr/hyprland.lua
-- Переписано с hyprlang (.conf) на Lua для Hyprland 0.55+
-- Справка: https://wiki.hypr.land/Configuring/Start/

------------------
---- MONITORS ----
------------------

hl.monitor({
    output   = "eDP-1",
    mode     = "2880x1620",
    position = "0x0",
    scale    = 2,
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "kitty"
local fileManager  = "dolphin"
local menu         = "rofi -show drun"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("waybar")
    -- hl.exec_cmd("sunshine")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("hyprpaper")
    hl.exec_cmd("throne", { workspace = "9 silent" })
    hl.exec_cmd("copyq --start-server")
    hl.exec_cmd("libinput-gestures-setup start")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("XDG_MENU_PREFIX", "arch-")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 6,

        border_size = 1,

        col = {
            active_border = "rgba(ffffffff)",
            inactive_border = "rgba(333333aa)",
        },

        resize_on_border = true,
        allow_tearing = false,
        layout = "dwindle",
    },

    decoration = {
        rounding = 8,
        rounding_power = 2,

        active_opacity = 1.0,
        inactive_opacity = 0.93,

        shadow = {
            enabled = true,
            range = 8,
            render_power = 3,
            color = 0xcc000000,
        },

        blur = {
            enabled = true,
            size = 5,
            passes = 2,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- кривые анимаций
hl.curve("gruvbox",   { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.curve("linear",    { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.curve("overshoot", { type = "bezier", points = { {0.13, 0.99}, {0.29, 1.1} } })

hl.animation({ leaf = "windows",         enabled = true, speed = 4,  bezier = "gruvbox", style = "slide" })
hl.animation({ leaf = "windowsOut",      enabled = true, speed = 3,  bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border",          enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "fade",            enabled = true, speed = 4,  bezier = "default" })
hl.animation({ leaf = "workspaces",      enabled = true, speed = 4,  bezier = "gruvbox", style = "slide" })
hl.animation({ leaf = "specialWorkspace",enabled = true, speed = 4,  bezier = "gruvbox", style = "slidevert" })

hl.config({
    dwindle = {
        force_split = 0,
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
    },
})

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout = "us,ru",
        kb_variant = "",
        kb_model = "",
        kb_options = "grp:alt_shift_toggle",
        kb_rules = "",

        follow_mouse = 1,
        sensitivity = 0,

        touchpad = {
            natural_scroll = true,
            ["tap-to-click"] = true,
            disable_while_typing = true,
        },
    },
})

-- пример конфига под конкретное устройство (перенесено из старого конфига как есть)
hl.device({
    name = "epic-mouse-v1",
    sensitivity = -0.5,
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

hl.bind(mainMod .. " + t", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("rofi -show drun"))

-- waybar
hl.bind("ALT + W", hl.dsp.exec_cmd("killall -SIGUSR2 waybar"))

-- hyprlock
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("loginctl lock-session"))

-- hyprshot
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots -f screenshot_$(date +%Y-%m-%d_%H-%M).png"))

-- clipboard
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("copyq show"))

-- fullscreen
-- ⚠ сигнатура fullscreen-диспетчера не подтверждена по актуальной вики — проверь на месте
hl.bind(mainMod .. " + U", hl.dsp.window.fullscreen({ mode = 0 }))

-- переключение по рабочим столам mainMod + [0-9]
-- перенос активного окна mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 -> клавиша 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- special workspace (scratchpad)
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- перемещение / ресайз окон мышью
hl.bind(mainMod .. " + Z", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + X", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- мультимедиа-клавиши (громкость / яркость)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

-- медиаплеер (нужен playerctl)
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

hl.window_rule({
    name = "move-hyprland-run",
    match = { class = "hyprland-run" },
    move = "20 monitor_h-120",
    float = true,
})

-- imv (просмотр изображений)
hl.window_rule({
    name = "imv-floating",
    match = { class = "imv" },
    float = true,
    center = true,
    size = "1200 720",
})

-- nmtui (сетевой менеджер)
hl.window_rule({
    name = "nmtui-menu",
    match = { class = "nmtui-float" },
    float = true,
    center = true,
    size = "700 450",
    pin = true,
})

-- copyq (менеджер буфера обмена)
hl.window_rule({
    name = "copyq-float",
    match = { class = "com.github.hluk.copyq" },
    float = true,
    center = true,
    size = "700 450",
    pin = true,
})

-- rofi
hl.window_rule({
    name = "rofi-float",
    match = { class = "rofi" },
    float = true,
    center = true,
})
