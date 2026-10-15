-- Recurring check: lua ~/.dotfiles/tests/hypr-transparency-binding-test.lua
-- Load the real bindings and exercise key presses against changing focus.
local root = assert(arg[0]:match("^(.*)/tests/[^/]+$"))
local bindings, commands = {}, {}
local focused = "first"
local opaque = { first = false, second = false }

hl = {
    bind = function(key, action)
        assert(not bindings[key], "duplicate binding: " .. key)
        bindings[key] = action
    end,
    dsp = {
        exec_cmd = function(command)
            return function() commands[#commands + 1] = command end
        end,
        window = {
            set_prop = function(options)
                assert(options.prop == "opaque" and options.value == "toggle")
                assert(options.window == nil, "resolve focus when pressed, not when loaded")
                return function() opaque[focused] = not opaque[focused] end
            end,
        },
    },
}

dofile(root .. "/home/.config/hypr/lua/omarchy/binds_utilities.lua")
local toggle = assert(bindings["SUPER + BACKSPACE"], "missing transparency shortcut")
toggle()
assert(#commands == 0, "transparency must not call the incompatible hyprlang shell helper")
assert(opaque.first and not opaque.second, "toggle only the focused window")
focused = "second"
toggle()
assert(opaque.first and opaque.second, "follow focus at keypress time")
focused = "first"
toggle()
assert(not opaque.first and opaque.second, "second press restores original opacity")
print("PASS: native Lua transparency binding follows focus and toggles both ways")
