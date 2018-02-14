local channels = {
	['381890411414683648'] = true, -- DAPI #lua_discordia
}

local timer = require('timer')
local random = math.random
local wrap = coroutine.wrap

local chance = 0.1

return function(msg)

	if channels[msg.channel.id] and msg.content:lower():find('roblox') and random() < chance then
		local r = msg:reply {file = 'roblox.png'}
		if r then
			timer.setTimeout(4000, wrap(r.delete), r)
		end
	end

end
