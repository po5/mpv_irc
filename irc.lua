-- irc.lua
--
-- Displays lines from an IRC channel

local options = {
    enabled = true,

    -- Log file to monitor
    log_file = "",

    -- Constrain line duration
    min_duration = 1,
    max_duration = 8,

    -- Extend the duration of a line if it's the last
    lead_out = 1,

    -- Characters Per Second
    target_cps = 18,

    -- How fast we try to catch up when the queue is full (lower is faster)
    queue_weight = 4,

    -- Possible values: osd, syncplay, scrolling
    -- Timing related options only work with 'osd'
    display_method = "osd",

    -- List of pipe-separated patterns to discard
    patterns = ""
}

mp.options = require "mp.options"
mp.options.read_options(options, "irc")

function offset(file)
    local f = assert(io.open(file, "rb"))
    local content = f:seek("end")
    f:close()
    return content
end

local log_file = ""
local last = 0
local queue = {}
local logs = {}
local logs_shown = false
local enabled = options.enabled

function new_lines(file)
    local f = assert(io.open(file, "rb"))
    f:seek("set", last)
    while true do
        local line = f:read("*l")
        if not line then
            last = f:seek()
            f:close()
            return
        end
        table.insert(queue, line)
    end
end

function update()
    if not enabled then return end
    if logs_shown and logs_shown < os.time() - 5 then logs_shown = false end
    mp.options.read_options(options, "irc")
    if log_file ~= options.log_file then
        queue = {}
        log_file = options.log_file
        if log_file ~= "" then
            last = offset(log_file)
        end
    end
    local timeout = options.min_duration
    if log_file ~= "" then
        new_lines(log_file)
        if next(queue) and not logs_shown then
            line = queue[1]
            for pattern in string.gmatch(options.patterns, "[^|]+") do
                line = string.gsub(line, pattern, "")
            end
            if options.display_method == "syncplay" then
                timeout = 0
                mp.command_native({"script-message-to", "syncplayintf", "chat", line})
            elseif options.display_method == "scrolling" then
                timeout = 0
                mp.command_native({"script-message", "scrollingsubs", "add", line})
            else
                timeout = math.max(timeout, math.min(options.max_duration, string.len(line) / options.target_cps) - #queue / options.queue_weight)
                mp.osd_message(line, timeout + options.lead_out)
            end
            table.remove(queue, 1)
            table.insert(logs, line)
        end
    end
    if #logs > 20 then
        table.remove(logs, 1)
    end
    mp.add_timeout(timeout, update)
end

function display_logs()
    if not enabled then return end
    if logs_shown and logs_shown > os.time() - 5 then
        mp.osd_message("", 0)
        logs_shown = false
        return
    end
    if not next(logs) then return end
    logs_shown = os.time()
    mp.osd_message(table.concat(logs, "\n"), 5)
end

function toggle()
    if enabled then
        enabled = false
        queue = {}
        logs = {}
        if options.display_method == "scrolling" then
            mp.command_native({"script-message", "scrollingsubs", "clear"})
        end
        mp.osd_message("[irc] disabled")
    else
        mp.osd_message("[irc] enabled")
        enabled = true
        update()
    end
end

mp.add_key_binding("x", "irc_display_logs", display_logs)
mp.add_key_binding("X", "irc_toggle", toggle)

update()
