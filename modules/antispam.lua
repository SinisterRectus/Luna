local discordia = require('discordia')

local Date = discordia.Date

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

local nsfwFilters = {
	'nakedphotos.club',
	'privatepage.vip',
	'viewc.site',
}

local notified = {}

local DEVS = '381886868708655104'-- DAPI #devs

local function lewd(msg)

	local author = msg.author

	local content = msg.content
	for _, filter in ipairs(nsfwFilters) do
		if content:find(filter, 1, true) then
			if not notified[author.id] then -- notify on first message, but do not delete it
				local log = msg.guild:getChannel(DEVS)
				if log then
					local member = msg.guild:getMember(author)
					if member and member.joinedAt then
						local joined = Date.fromISO(member.joinedAt)
						local created = Date.fromSnowflake(author.id)
						local now = Date()
						local notice = log:sendf(
							'nsfw bot detected: %s in %s.\n - Joined: `%s` (%s ago)\n - Created: `%s` (%s ago)',
							author.mentionString, msg.channel.mentionString,
							joined:toISO('T', 'Z'), (now - joined):toString(),
							created:toISO('T', 'Z'), (now - created):toString()
						)
						if notice then
							notified[author.id] = true
							return false
						end
					end
				end
			end
			return true
		end
	end

end

return function(msg)

	local channel = msg.channel
	local guild = channel.guild
	local bot = guild.me

	if bot:hasPermission(channel, 'manageMessages') then
		if lewd(msg) then -- detect nsfw bot
			return msg:delete()
		end
		if star(msg) then -- github star spam
			return msg:delete()
		end
	end

end
