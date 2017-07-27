local matches = {
    'sinister',
    'rectus',
	'discord.gg/'
}

local ignore = {
    ['173885235002474497'] = true, -- DAPI lua_discordia
}

return function(msg)

    if ignore[msg.channel.id] then return end
    if msg.author == msg.client.owner then return end

    local content = msg.content:lower()
    for _, m in ipairs(matches) do
        if content:find(m, 1, true) then
            return true
        end
    end

end
