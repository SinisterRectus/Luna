local discordia = require('discordia')
local abs = math.abs

local GENERAL = '381870553235193857' -- dapi #general
local lastNumber = false

local function count(msg) do
    if #msg.content == 0 then
        return true
    end
    local num = tonumber(msg.content)
    if num == nil then
        return true
    end
    if not lastNumber then
        lastNumber = num
    end
    if abs(lastNumber - num) > 1 then
        return true
    end
    return false
end

return function(msg)
    local channel = msg.channel
    local guild = msg.guild
    local bot = guild.me

    if channel.id ~= GENERAL then
        return
    end

    if bot:hasPermission(channel, 'manageMessages') then
        if count(msg) then
            return msg:delete()
        end
    end
end