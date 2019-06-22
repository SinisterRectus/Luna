local DAPI_GUILD = '81384788765712384'
local LOG_CHANNEL = '430492289077477416'

-- this mirrors deleted messages from DAPI to a private log for moderation purposes

return function(message)

	if #message.content == 0 then return end
	if not message.guild then return end
	if message.guild.id ~= DAPI_GUILD then return end

	local log = message.client:getChannel(LOG_CHANNEL)
	if not log then return end

	return log:send {
		content = '\n' .. message.content,
		mentions = {message.author, message.channel}
	}

end
