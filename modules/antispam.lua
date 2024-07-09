local discordia = require('discordia')

local f = string.format

local stars = setmetatable({}, {__index = function() return 0 end})

local function star(msg)

	if msg.author.discriminator ~= '0000' then return end

	local embed = msg.embed
	if not embed then return end

	if not embed.title then return end
	if not embed.title:find('New star added') then return end

	if not embed.author then return end
	if not embed.author.name then return end

	local key = msg.channel.id .. embed.author.name .. embed.title
	stars[key] = stars[key] + 1

	return stars[key] > 1

end

local mentions = setmetatable({}, {
	__index = function(self, k)
		self[k] = {}
		return self[k]
	end
})

local limit = 2 -- mentions
local reset = discordia.Time.fromSeconds(10)
local timeout = discordia.Time.fromMinutes(10)

local function mention(msg)

	if msg.channel.guild.id ~= '749981577303556167' then return end -- discordia

	local member = msg.member
	if not member then return end

	local bot = msg.guild.me
	if not bot then return end
	
	if #msg.mentionedUsers == 0 then return end

	if member.highestRole.position > bot.highestRole.position then return end

	local id = msg.author.id
	
	local log
	for user in msg.mentionedUsers:iter() do
		if user.id ~= id then
			log = log or msg.guild:getChannel('1021837861928046652')
			table.insert(mentions[id], {msg.id, user.id})
		end
	end

	local now = discordia.Date()
	local n = 0
	for i = #mentions[id], 1, -1 do
		local v = mentions[id][i]
		local d = discordia.Date.fromSnowflake(v[1])
		if d - now > reset then
			table.remove(mentions[id], i)
		else
			n = n + 1
		end
	end

	if n > 1 and log and bot:hasPermission(log, 'sendMessages') then
		log:send {
			embed = {
				author = {
					name = member.tag,
					icon_url = member.avatarURL,
				},
				title = 'User(s) Mentioned',
				description = msg.content,
				fields = {
					{name = 'Message ID', value = f('[%s](%s)', msg.id, msg.link)},
					{name = 'Author', value = f('%s | %s', member.name, member.mentionString)},
					{name = 'Channel', value = f('%s | %s', msg.channel.name, msg.channel.mentionString)},
					{name = 'Mentions Used', value = f('%s of %s / %s', n, limit, reset:toString())}
				},
				timestamp = msg.timestamp,
			},
		}
	end

	return n > limit

end

return function(msg)

	local channel = msg.channel
	local bot = channel.guild.me

	if bot:hasPermission(channel, 'manageMessages') then
		if star(msg) then -- github star spam
			return msg:delete()
		end
		if mention(msg) then
			if msg.member:timeoutFor(timeout) then
				msg:reply(msg.author.username .. ' timed-out for spamming mentions')
			end
		end
	end

end
