-- local discordia = require('discordia')

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

	if stars[key] > 1 then
		if stars[key] == 2 then
			msg.client.owner:sendf(
				'Star spam detected at %q (%q) by %q',
				msg.channel.name,
				msg.channel.id,
				embed.author.name
			)
		end
		return true
	end

end

return function(msg)

	local channel = msg.channel
	local guild = channel.guild
	local bot = guild.me

	if bot:hasPermission(channel, 'manageMessages') then
		if star(msg) then -- github star spam
			return msg:delete()
		end
	end

end
