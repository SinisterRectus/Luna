local guilds = {
	['81384788765712384'] = '652568709562499072', -- Discord API
	['377572091869790210'] = '652568730672431137', -- Luvit.io
}

local f = string.format

-- this mirrors deleted messages to a private log for moderation purposes

return function(message)

	if #message.content == 0 then return end

	local guild = message.guild
	if not guild then return end

	local id = guilds[guild.id]
	if not id then return end

	local log = message.client:getChannel(id)
	if not log then return end

	local channel = message.channel
	local author = message.member or message.author

	return log:send {
		embed = {
			author = {
				name = author.tag,
				icon_url = author.avatarURL,
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
