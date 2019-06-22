local timer = require('timer')

local DAPI_GUILD = '81384788765712384'

return function(client)

	local guild = client:getGuild(DAPI_GUILD)
	if not guild then return end

	local me = guild:getMember(client.user)
	if not me then return end

	if me:hasPermission('manageNicknames') then
		local position = me.highestRole.position
		for member in guild.members:findAll(function(m)
			return m.name:startswith('!') and m.highestRole.position < position and m.status ~= 'offline'
		end) do
			member:setNickname('💩')
			timer.sleep(1000)
		end
	end

end
