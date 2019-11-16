-- Based on https://gist.github.com/jonniek/c3fed06cd7990518e8b2389f48ba3619

local assdraw = require("mp.assdraw")

local settings = {
    ass_style = "\\1c&HC8C8B4\\fs33\\bord2",
    speed = 0.3
}

local subs = {}

local rendering = false

math.randomseed(os.time())

function round(num)
    m = num % 50
    if m == 0 then m = 50 end
    return num + (50 - (m))
end

local function handle(action, text)
    if action == "clear" then
        subs = {}
        rendering = false
        return
    end
    local w, h = mp.get_osd_size()
    if not w or not h then return end
    local subtitle = {}
    subtitle.y = round(math.random(15, h-51))
    if subs[subtitle.y] then
        if subs[subtitle.y].x <= w / 2 then
            subs[subtitle.y .. "-" .. os.time()] = subs[subtitle.y]
        else
            return mp.add_timeout(subs[subtitle.y].x / 2 / (settings.speed * (settings.speed / 0.001)), function() handle(action, text) end)
        end
    end
    subtitle.x = w
    subtitle.content = text:gsub("^&br!", ""):gsub("&br!", "\\N")
    subs[subtitle.y] = subtitle
    if not rendering then
        playsubs:resume()
    end
end

local function render()
    rendering = true
    local ass = assdraw.ass_new()
    ass:new_event()
    ass:append("")
    for key, subtitle in pairs(subs) do
        ass:new_event()
        ass:append(string.format("{\\pos(%s,%s)%s}", subtitle.x, subtitle.y, settings.ass_style))
        ass:append(subtitle.content:gsub("(>.-\\N)", "{\\1c&H35966f&}%1"):gsub("(\\N[^>])", "{\\1c&HC8C8B4}%1"))

        subtitle.x = subtitle.x - settings.speed
        if subtitle.x < -2500 then subs[key] = nil end
    end
    local w, h = mp.get_osd_size()
    mp.set_osd_ass(w, h, ass.text)
    if ass.text == "" then
        rendering = false
        playsubs:kill()
    end
end
playsubs = mp.add_periodic_timer(0.001, render)
playsubs:kill()

mp.register_script_message("scrollingsubs", handle)