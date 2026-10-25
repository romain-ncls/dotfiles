-- skip-signs-subs.lua
-- If mpv auto-selects a "Signs & Songs" or a forced subtitle track (forced =
-- only the foreign-language lines; streaming rips often flag it default, as
-- on The Terminal List), switch to a full subtitle track in the same language
-- instead. Non-SDH tracks are preferred over SDH ([door creaks] captions),
-- text (ASS/SRT) over image (PGS/VobSub), and ASS over plain text.

local function is_signs(track)
    local t = (track.title or ""):lower()
    if t:find("full", 1, true) or t:find("dialog", 1, true) then
        return false
    end
    return t:find("sign", 1, true) or t:find("song", 1, true)
        or t:find("s&s", 1, true) or t:find("s & s", 1, true)
end

local function partial(track)
    return track.forced or is_signs(track)
end

local image_codecs = { hdmv_pgs_subtitle = true, dvd_subtitle = true, dvb_subtitle = true }

local function score(track)
    local s = track["hearing-impaired"] and 0 or 10
    if track.codec == "ass" or track.codec == "ssa" then return s + 3 end
    if not image_codecs[track.codec] then return s + 2 end
    return s + 1
end

mp.register_event("file-loaded", function()
    local current = mp.get_property_native("current-tracks/sub")
    if not current or not partial(current) then return end

    local best
    for _, track in ipairs(mp.get_property_native("track-list")) do
        if track.type == "sub" and track.id ~= current.id and not partial(track)
            and track.lang == current.lang
            and (not best or score(track) > score(best)) then
            best = track
        end
    end

    if best then
        mp.msg.info(("Skipping signs/forced track '%s', selecting '%s'"):format(
            current.title or "", best.title or ""))
        mp.set_property_number("sid", best.id)
    end
end)
