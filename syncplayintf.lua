-- syncplayintf.lua -- An interface for communication between mpv and Syncplay
-- Author: Etoh
-- Thanks: RiCON, James Ross-Gowan, Argon-, wm4, uau

-- All repl.lua code and most syncplay functionality has been stripped

local CANVAS_WIDTH = 1920
local CANVAS_HEIGHT = 1080
local chat_format = "{\\fs50}{\an1}"
local max_scrolling_rows = 100
local MOVEMENT_PER_SECOND = 200
local TICK_INTERVAL = 0.01
local last_chat_time = 0
local WORDWRAPIFY_MAGICWORD = "{\\\\fscx0}  {\\\\fscx100}"
local SCROLLING_ADDITIONAL_BOTTOM_MARGIN = 75

local FONT_SIZE_MULTIPLIER = 2

local chat_log = {}

local assdraw = require "mp.assdraw"

local opt = require "mp.options"

function format_scrolling(xpos, ypos, text)
    local chat_message = "\n"..chat_format .. "{\\pos("..xpos..","..ypos..")\\q2}"..text.."\\N\\n"
    return string.format(chat_message)
end

function format_chatroom(text)
    local chat_message = chat_format .. text .."\\N\\n"
    return string.format(chat_message)
end

function clear_chat()
    chat_log = {}
end

local alert_osd = ""
local last_alert_osd_time = nil

local notification_osd = ""
local last_notification_osd_time = nil

function add_chat(chat_message)
    last_chat_time = mp.get_time()
    local entry = #chat_log+1
    for i = 1, #chat_log do
        if chat_log[i].text == "" then
            entry = i
            break
        end
    end
    local row = ((entry-1) % max_scrolling_rows)+1
    if entry > opts["chatMaxLines"] then
        table.remove(chat_log, 1)
        entry = entry - 1
    end
    chat_log[entry] = { xpos=CANVAS_WIDTH, timecreated=mp.get_time(), text=tostring(chat_message), row=row }
end

local old_ass_text = ""
function chat_update()
    local ass = assdraw.ass_new()
    local chat_ass = ""
    local to_add = ""
    if chat_log ~= {} then
        local timedelta = mp.get_time() - last_chat_time
        if timedelta >= opts["chatTimeout"] then
            clear_chat()
        end
    end

    if #chat_log > 0 then
        for i = 1, #chat_log do
            local to_add = process_chat_item_chatroom(i)
            if to_add ~= nil and to_add ~= "" then
                chat_ass = chat_ass .. to_add
            end
        end
    end

    local xpos = opts["chatLeftMargin"]
    local ypos = opts["chatTopMargin"]
    chat_ass = "\n".."{\\pos("..xpos..","..ypos..")}".. chat_ass

    ass:append(chat_ass)

    -- The commit that introduced the new API removed the internal heuristics on whether a refresh is required,
    -- so we check for changed text manually to not cause excessive GPU load
    -- https://github.com/mpv-player/mpv/commit/07287262513c0d1ea46b7beaf100e73f2008295f#diff-d88d582039dea993b6229da9f61ba76cL530
    if ass.text ~= old_ass_text then
        mp.set_osd_ass(CANVAS_WIDTH,CANVAS_HEIGHT, ass.text)
        old_ass_text = ass.text
    end
end

function process_chat_item_chatroom(i)
    local text = chat_log[i].text
    if text ~= "" then
        local text = wordwrapify_string(text)
        local rowNumber = i-1
        return(format_chatroom(text))
    end
end

chat_timer=mp.add_periodic_timer(TICK_INTERVAL, chat_update)

mp.register_script_message("chat", function(e)
    add_chat(e)
end)

mp.register_script_message("set_syncplayintf_options", function(e)
    set_syncplayintf_options(e)
end)

-- Default options
local options = require "mp.options"
opts = {
    -- All drawing is scaled by this value, including the text borders.
    -- Change it if you have a high-DPI display.
    scale = 1,
    ["chatOutputFontFamily"] = "sans serif",
    ["chatOutputFontSize"] = 50,
    ["chatOutputFontWeight"] = 1,
    ["chatOutputFontUnderline"] = false,
    ["chatOutputFontColor"] = "#FFFFFF",
    ["scrollingFirstRowOffset"] = 2,
    ["chatMaxLines"] = 7,
    ["chatTopMargin"] = 25,
    ["chatLeftMargin"] = 20,
    ["chatDirectInput"] = true,
    --
    ["chatTimeout"] = 7,
    --
    ["backslashSubstituteCharacter"] = "|"
}

function detect_platform()
    local o = {}
    -- Kind of a dumb way of detecting the platform but whatever
    if mp.get_property_native("options/vo-mmcss-profile", o) ~= o then
        return "windows"
    elseif mp.get_property_native("options/input-app-events", o) ~= o then
        return "macos"
    end
    return "linux"
end

-- Pick a better default font for Windows and macOS
local platform = detect_platform()
if platform == "windows" then
    opts.font = "Consolas"
elseif platform == "macos" then
    opts.font = "Menlo"
end

-- Apply user-set options
options.read_options(opts)

-- Escape a string for verbatim display on the OSD
function ass_escape(str)
    -- There is no escape for "\" in ASS (I think?) but "\" is used verbatim if
    -- it isn't followed by a recognised character, so add a zero-width
    -- non-breaking space
    str = str:gsub("\\", "\\\239\187\191")
    str = str:gsub("{", "\\{")
    str = str:gsub("}", "\\}")
    -- Precede newlines with a ZWNBSP to prevent ASS"s weird collapsing of
    -- consecutive newlines
    str = str:gsub("\n", "\239\187\191\n")
    return str
end

function get_output_style()
    local bold
    if opts["chatOutputFontWeight"] < 75 then
        bold = 0
    else
        bold = 1
    end
    local underline = opts["chatOutputFontUnderline"] and 1 or 0
    local red = string.sub(opts["chatOutputFontColor"],2,3)
    local green = string.sub(opts["chatOutputFontColor"],4,5)
    local blue = string.sub(opts["chatOutputFontColor"],6,7)
    local fontColor = blue .. green .. red
    local style = "{\\r" ..
                   "\\1a&H00&\\3a&H00&\\4a&H99&" ..
                   "\\1c&H"..fontColor.."&\\3c&H111111&\\4c&H000000&" ..
                   "\\fn" .. opts["chatOutputFontFamily"] .. "\\fs" .. (opts["chatOutputFontSize"]*FONT_SIZE_MULTIPLIER) .. "\\b" .. bold ..
                   "\\u"  .. underline .. "\\a5\\MarginV=500" .. "}"

    return style

end

-- Naive helper function to find the next UTF-8 character in "str" after "pos"
-- by skipping continuation bytes. Assumes "str" contains valid UTF-8.
function next_utf8(str, pos)
    if pos > str:len() then return pos end
    repeat
        pos = pos + 1
    until pos > str:len() or str:byte(pos) < 0x80 or str:byte(pos) > 0xbf
    return pos
end

function wordwrapify_string(line)
    -- Used to ensure characters wrap on a per-character rather than per-word basis
    -- to avoid issues with long filenames, etc.

    local str = line
    if str == nil or str == "" then
        return ""
    end
    local newstr = ""
    local currentChar = 0
    local nextChar = 0
    local chars = 0
    local maxChars = str:len()
    str = string.gsub(str, "\\\"", "\"");
    repeat
        nextChar = next_utf8(str, currentChar)
        if nextChar == currentChar then
            return newstr
        end
        local charToTest = str:sub(currentChar,nextChar-1)
        if charToTest ~= "{"  and charToTest ~= "}" and charToTest ~= "%" then
            newstr = newstr .. WORDWRAPIFY_MAGICWORD .. str:sub(currentChar,nextChar-1)
        else
            newstr = newstr .. str:sub(currentChar,nextChar-1)
        end
        currentChar = nextChar
    until currentChar > maxChars
    newstr = string.gsub(newstr,opts["backslashSubstituteCharacter"], "\\\239\187\191") -- Workaround for \ escape issues
    return newstr
end

local syncplayintfSet = false

function readyMpvAfterSettingsKnown()
    if syncplayintfSet == false then
        local vertical_output_area = CANVAS_HEIGHT-(opts["chatTopMargin"]+opts["chatBottomMargin"]+((opts["chatOutputFontSize"]*FONT_SIZE_MULTIPLIER)*opts["scrollingFirstRowOffset"])+SCROLLING_ADDITIONAL_BOTTOM_MARGIN)
        max_scrolling_rows = math.floor(vertical_output_area/(opts["chatOutputFontSize"]*FONT_SIZE_MULTIPLIER))
        syncplayintfSet = true
    end
end

function set_syncplayintf_options(input)
    for option, value in string.gmatch(input, "([^ ,=]+)=([^,]+)") do
        local valueType = type(opts[option])
        if valueType == "number" then
            value = tonumber(value)
        elseif valueType == "boolean" then
            if value == "True" then
                value = true
            else
                value = false
            end
        end
        opts[option] = value
    end
    chat_format = get_output_style()
    readyMpvAfterSettingsKnown()
end 
