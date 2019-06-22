local discordia = require('discordia')

local Date = discordia.Date

local channels = {
	['381890411414683648'] = true, -- DAPI #lua_discordia
}

local stars = setmetatable({}, {__index = function() return 0 end})

local function star(msg)

	if msg.author.discriminator ~= '0000' then return end

	local embed = msg.embed
	if not embed then return end

	if not embed.title or not embed.title:find('star added') then return end

	local name = embed.author and embed.author.name
	if not name then return end

	local key = msg.channel.id .. name
	stars[key] = stars[key] + 1

	if stars[key] > 1 then
		if stars[key] == 2 then
			msg.client.owner:sendf(
				'Star spam detected at %q (%q) by %q',
				msg.channel.name,
				msg.channel.id,
				name
			)
		end
		return true
	end

end

local function dot(msg)
	return msg.content == '.'
end

local function caret(msg)
	if msg.content:find('%^') then
		local _, n = msg.content:gsub('%^', '')
		return n > 0.35 * msg.content:len()
	end
end

local function xd(msg)
	return msg.author.id == '366610426441498624' and msg.content:lower() == 'xd'
end

-- return function(msg)
-- 	local channel = msg.channel
-- 	if channels[channel.id] and channel.guild.me:hasPermission(channel, 'manageMessages') then
-- 		if star(msg) or dot(msg) or caret(msg) or xd(msg) then
-- 			return msg:delete()
-- 		end
-- 	end
-- end

local filters = {
	'nakedphotos.club',
	'privatepage.vip',
	'viewc.site',
}

local notified = {}

local DEVS = '381886868708655104'-- DAPI #devs

local function lewd(msg)

	local author = msg.author
	-- if author.avatar then return end

	local content = msg.content
	for _, filter in ipairs(filters) do
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
							author.mentionString,
							msg.channel.mentionString,
							joined:toISO('T', 'Z'),
							(now - joined):toString(),
							created:toISO('T', 'Z'),
							(now - created):toString()
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
	local me = guild.me
	if me:hasPermission(channel, 'manageMessages') then
		if lewd(msg) then
			return msg:delete()
		end
		if star(msg) then
			return msg:delete()
		end
	end
end
