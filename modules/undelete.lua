local LOG_CHANNEL = '609046553474236416'

local guilds = {
	['81384788765712384'] = true, -- Discord API
	['377572091869790210'] = true, -- Luvit.io
}

local f = string.format

-- this mirrors deleted messages to a private log for moderation purposes

return function(message)

	if #message.content == 0 then return end

	local guild = message.guild
	if not guild or not guilds[guild.id] then return end

	local log = message.client:getChannel(LOG_CHANNEL)
	if not log then return end

	local channel = message.channel
	local author = message.member or message.author

	return log:send {
		embed = {
			author = {
				name = author.tag,
				icon_url = author.avatarURL,
			},
			thumbnail = {
				url = guild.iconURL,
			},
			title = 'Message Deleted',
			description = message.content,
			fields = {
				{name = 'Message ID', value = message.id},
				{name = 'Guild', value = f('%s | %s', guild.name, guild.id)},
				{name = 'Author', value = f('%s | %s', author.name, author.mentionString)},
				{name = 'Channel', value = f('%s | %s', channel.name, channel.mentionString)},
			},
			timestamp = message.timestamp,
		},
	}

end
