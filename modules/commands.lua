local discordia = require('discordia')
local pp = require('pretty-print')
local fs = require('fs')
local http = require('coro-http')
local qs = require('querystring')

local random, max = math.random, math.max
local f, upper = string.format, string.upper
local insert, concat, sort = table.insert, table.concat, table.sort

local clamp = math.clamp -- luacheck: ignore
local pack = table.pack -- luacheck: ignore

local dump = pp.dump
local urlencode = qs.urlencode

local Date = discordia.Date
local Time = discordia.Time

local function searchMember(msg, query)

	if not query then return end

	local guild = msg.guild
	local members = guild.members
	local user = msg.mentionedUsers.first

	local member = user and guild:getMember(user) or members:get(query) -- try mentioned user or cache lookup by id
	if member then
		return member
	end

	if query:find('#', 1, true) then -- try username#discriminator combination
		local username, discriminator = query:match('(.*)#(%d+)$')
		if username and discriminator then
			print(username, discriminator)
			member = members:find(function(m) return m.username == username and m.discriminator == discriminator end)
			if member then
				return member
			end
		end
	end

	local distance = math.huge
	local lowered = query:lower()

	for m in members:iter() do
		if m.nickname and m.nickname:lower():find(lowered, 1, true) then
			local d = m.nickname:levenshtein(query)
			if d == 0 then
				return m
			elseif d < distance then
				member = m
				distance = d
			end
		end
		if m.username:lower():find(lowered, 1, true) then
			local d = m.username:levenshtein(query)
			if d == 0 then
				return m
			elseif d < distance then
				member = m
				distance = d
			end
		end
	end

	if member then
		return member
	else
		return nil, f('No member found for: `%s`', query)
	end

end

local prefix = '~~'
local function parseContent(content)
	if content:find(prefix, 1, true) ~= 1 then return end
	content = content:sub(prefix:len() + 1)
	local cmd, arg = content:match('(%S+)%s+(.*)')
	return cmd or content, arg
end

local cmds = setmetatable({}, {__call = function(self, msg)

	local cmd, arg = parseContent(msg.content)
	if not self[cmd] then return end

	if msg.author ~= msg.client.owner then
		print(msg.author.username, cmd) -- TODO: better command use logging
	end

	local success, content = pcall(self[cmd][1], arg, msg)

	local reply, err

	if success then -- command ran successfully

		if type(content) == 'string' then
			if #content > 1900 then
				reply, err = msg:reply {
					content = 'Content is too large. See attached file.',
					file = {os.time() .. '.txt', content},
					code = true,
				}
			elseif #content > 0 then
				reply, err = msg:reply(content)
			end
		elseif type(content) == 'table' then
			if content.content and #content.content > 1900 then
				local file = {os.time() .. '.txt', content.content}
				content.content = 'Content is too large. See attached file.'
				content.code = true
				if content.files then
					insert(content.files, file)
				else
					content.files = {file}
				end
			end
			reply, err = msg:reply(content)
		end

	else -- command produced an error, try to send it as a message

		reply = msg:reply {content = content,	code = 'lua'}

	end

	if err and not reply then
		print(err)
	end

end})

cmds['help'] = {function()
	local buf = {}
	for k, v in pairs(cmds) do
		insert(buf, f('%s - %s', k, v[2]))
	end
	sort(buf)
	return concat(buf, '\n')
end, 'This help command.'}

cmds['time'] = {function()
	return {embed = {description = Date():toISO(' ', ' UTC')}}
end, 'Provides the current time in an abbreviated UTC format.'}

cmds['roll'] = {function(arg)
	local n = tonumber(arg) or 6
	return {
		embed = {
			description = f('You roll a math.random(%i). It returns %i.', n, random(n))
		}
	}
end, 'Provides a random number.'}

cmds['flip'] = {function()
	return {
		embed = {
			description = f('You flip a coin. It lands on %s.', random(2) == 1 and 'heads' or 'tails')
		}
	}
end, 'Flips a coin.'}

cmds['whois'] = {function(arg, msg)

	local m, err = searchMember(msg, arg)
	if not m then
		return err
	end

	local color = m:getColor().value

	return {
		embed = {
			thumbnail = {url = m.avatarURL},
			fields = {
				{name = 'Name', value = m.nickname and f('%s (%s)', m.username, m.nickname) or m.username, inline = true},
				{name = 'Discriminator', value = m.discriminator, inline = true},
				{name = 'ID', value = m.id, inline = true},
				{name = 'Status', value = m.status:gsub('^%l', upper), inline = true},
				{name = 'Joined Server', value = m.joinedAt and m.joinedAt:gsub('%..*', ''):gsub('T', ' ') or '?', inline = true},
				{name = 'Joined Discord', value = Date.fromSnowflake(m.id):toISO(' ', ''), inline = true},
			},
			color = color > 0 and color or nil,
		}
	}

end, 'Provides information about a guild member.'}

cmds['avatar'] = {function(arg, msg)
	if not arg then
		return {embed = {image = {url = msg.author.avatarURL}}}
	else
		local member, err = searchMember(msg, arg)
		if not member then
			return err
		end
		return {embed = {image = {url = member.avatarURL}, description = member.mentionString}}
	end
end, 'Provides the avatar of a guild member.'}

cmds['icon'] = {function(_, msg)
	return {embed = {image = {url = msg.guild.iconURL}}}
end, 'Provides the guild icon.'}

local function isOnline(member)
	return member.status ~= 'offline'
end

local function hasColor(role)
	return role.color > 0
end

cmds['serverinfo'] = {function(_, msg)

	local guild = msg.guild
	local owner = guild.owner

	return {
		embed = {
			thumbnail = {url = guild.iconURL},
			fields = {
				{name = 'Name', value = guild.name, inline = true},
				{name = 'ID', value = guild.id, inline = true},
				{name = 'Owner', value = owner.tag, inline = true},
				{name = 'Created', value = Date.fromSnowflake(guild.id):toISO(' ', ''), inline = true},
				{name = 'Members', value = guild.members:count(isOnline) .. ' / ' .. guild.totalMemberCount, inline = true},
				{name = 'Categories', value = tostring(#guild.categories), inline = true},
				{name = 'Text Channels', value = tostring(#guild.textChannels), inline = true},
				{name = 'Voice Channels', value = tostring(#guild.voiceChannels), inline = true},
				{name = 'Roles', value = tostring(#guild.roles), inline = true},
				{name = 'Emojis', value = tostring(#guild.emojis), inline = true},
			}
		}
	}

end, 'Provides information about the guild.'}

cmds['color'] = {function(arg)
	local c = discordia.Color(tonumber(arg))
	return {
		embed = {
			color = c.value,
			fields = {
				{name = 'Decimal', value = c.value},
				{name = 'Hexadecimal', value = c:toHex()},
				{name = 'RGB', value = f('%i, %i, %i', c:toRGB())},
				{name = 'HSV', value = f('%i, %.2f, %.2f', c:toHSV())},
				{name = 'HSL', value = f('%i, %.2f, %.2f', c:toHSL())},
			}
		}
	}
end, 'Provides some information about a provided color.'}

cmds['colors'] = {function(_, msg)

	local roles = msg.guild.roles:toArray('position', hasColor)

	local len = 0
	for _, role in ipairs(roles) do
		len = max(len, #role.name)
	end

	local ret = {}
	for i = #roles, 1, -1 do
		local role = roles[i]
		local c = role:getColor()
		local row = f('%s | %s | %s | %s | %s',
			role.name:pad(len, 'right'),
			c:toHex(),
			tostring(c.r):pad(3, 'right'),
			tostring(c.g):pad(3, 'right'),
			tostring(c.b):pad(3, 'right')
		)
		insert(ret, row)
	end

	return {content = concat(ret, '\n'), code = true}

end, 'Shows the colors of all of the colored roles in the guild.'}

local function printLine(...)
	local ret = {}
	for i = 1, select('#', ...) do
		insert(ret, tostring(select(i, ...)))
	end
	return concat(ret, '\t')
end

local function prettyLine(...)
	local ret = {}
	for i = 1, select('#', ...) do
		insert(ret, dump(select(i, ...), nil, true))
	end
	return concat(ret, '\t')
end

cmds['poop'] = {function(arg, msg)

	local guild = msg.guild

	local author = guild:getMember(msg.author)
	if not author then return end

	if not author:hasPermission('manageNicknames') then return end
	if not guild.me:hasPermission('manageNicknames') then return end

	local member = searchMember(msg, arg)
	if not member then return end

	if author.highestRole.position > member.highestRole.position then
		if member:setNickname('💩') then
			return msg:addReaction('✅')
		end
	end

end, 'Moderator only. Changes a nickname to a poop emoji.'}

local sandbox = setmetatable({
	require = require,
	discordia = discordia,
}, {__index = _G})

cmds['lua'] = {function(arg, msg)

	if not arg then return end

	if msg.author ~= msg.client.owner then return end

	arg = arg:gsub('```lua\n?', ''):gsub('```\n?', '')

	local lines = {}

	sandbox.message = msg
	sandbox.channel = msg.channel
	sandbox.guild = msg.guild
	sandbox.client = msg.client
	sandbox.print = function(...) insert(lines, printLine(...)) end
	sandbox.p = function(...) insert(lines, prettyLine(...)) end

	local fn, err = load(arg, 'Luna', 't', sandbox)
	if not fn then return error(err) end

	local res = pack(fn())
	if res.n > 0 then
		for i = 1, res.n do
			res[i] = tostring(res[i])
		end
		insert(lines, concat(res, '\t'))
	end

	if #lines > 0 then
		return {content = concat(lines, '\n'), code = 'lua'}
	end

end, 'Bot owner only. Executes Lua code.'}

local enum1 = {online = 1, idle = 2, dnd = 3, offline = 4}
local enum2 = {'Online', 'Idle', 'Do Not Disturb', 'Offline'}

local DAPI = '81384788765712384'
local DISCORDIA_SUBS = '238388552663171072'
local BOOSTER_COLOR = 0xF47FFF

cmds['subs'] = {function(_, msg)

	local guild = msg.client:getGuild(DAPI)
	if not guild then return end
	local role = guild:getRole(DISCORDIA_SUBS)
	if not role then return end

	local n = 0
	local ret = {{}, {}, {}, {}}
	for member in role.members:iter() do
		insert(ret[enum1[member.status]], member.name)
		n = n + 1
	end

	local fields = {}
	for i, v in ipairs(ret) do
		if #v > 0 then
			sort(v)
			insert(fields, {name = enum2[i], value = concat(v, ', ')})
		end
	end

	return {
		embed = {
			title = 'Discordia News Subscribers',
			description = 'Total: ' .. n,
			fields = fields
		}
	}

end, 'Shows all subscribers to the Discordia news role.'}

cmds['boosters'] = {function(_, msg)

	local guild = msg.guild

	local members = {}
	for member in guild.members:findAll(function(m) return m.premiumSince end) do
		insert(members, {member.tag, member.premiumSince})
	end
	sort(members, function(a, b) return a[2] < b[2] end)

	local desc = {}
	local now = Date()
	for _, v in ipairs(members) do
		local days = (now - Date.fromISO(v[2]))
		insert(desc, f('%s - %.2f days', v[1], days:toDays()))
	end

	return {
		embed = {
			title = guild.name .. ' Boosters',
			description = concat(desc, '\n'),
			color = BOOSTER_COLOR,
		}
	}

end, 'Shows all current guild boosters.'}

cmds['lenny'] = {function()
	return '( ͡° ͜ʖ ͡°)'
end, '( ͡° ͜ʖ ͡°)'}

cmds['clean'] = {function(arg, msg)
	if msg.author == msg.client.owner and msg.guild.me:hasPermission(msg.channel, 'manageMessages') then
		if not tonumber(arg) then return end
		local messages = msg.channel:getMessagesAfter(arg, 100)
		if messages then
			return msg.channel:bulkDelete(messages)
		end
	end
end, 'Bot owner only. Cleans chat messages after a specific ID.'}

cmds['joined'] = {function(_, msg)

	local guild = msg.guild
	local members = {}

	for m in msg.channel:getMessages(100):iter() do
		local member = guild:getMember(m.author)
		if member.joinedAt then
			members[member] = true
		end
	end

	local sorted = {}
	for member in pairs(members) do
		insert(sorted, {member.joinedAt, member.name})
	end
	sort(sorted, function(a, b) return a[1] > b[1] end)

	local fields = {}

	local now = Date()
	for i = 1, math.min(#sorted, 5) do
		local v = sorted[i]
		local seconds = Date.parseISO(v[1])
		local t = now - Date(seconds)
		insert(fields, {name = v[2], value = t:toString() .. ' ago'})
	end

	return {
		embed = {fields = fields}
	}

end, 'Shows recently joined members based on recent message authors.'}

cmds['discrims'] = {function(arg, msg)

	local counts = setmetatable({}, {__index = function() return 0 end})

	for member in msg.guild.members:iter() do
		local d = tonumber(member.discriminator)
		counts[d] = counts[d] + 1
	end

	local sorted = {}
	for i = 1, 9999 do
		if counts[i] > 0 then
			insert(sorted, {i, counts[i]})
		end
	end

	sort(sorted, function(a, b) return a[2] > b[2] end)

	local content = {}
	local n = tonumber(arg) or 10
	for i = 1, n do
		local d = sorted[i]
		if d then
			local fmt = f('%%%ii | %%04i | %%i', #tostring(n))
			insert(content, f(fmt, i, d[1], d[2]))
		end
	end
	return {content = concat(content, '\n'), code = true}

end, 'Shows the top discriminators in use for the guild.'}

local function spotifyActivity(m)
	return m.activity and m.activity.name == 'Spotify' and m.activity.type == 2
end

local function spotifyIncrement(counts, hash, member)
	local count = counts[hash]
	if count then
		count[1] = count[1] + 1
		insert(count, member.tag)
	else
		counts[hash] = {1, hash, member.tag}
	end
end

local spotifyGreen = discordia.Color.fromRGB(30, 215, 96).value

local function spotifySorter(a, b)
	return a[1] > b[1]
end

local function spotifyEmbed(msg, what, listeners, counts, limit)

	local sorted, n = {}, 0
	for _, v in pairs(counts) do
		n = n + 1
		if v[1] > 1 then
			insert(sorted, v)
		end
	end
	sort(sorted, spotifySorter)

	local fields = {}
	for i = 1, tonumber(limit) or 5 do
		local d = sorted[i]
		if d then
			insert(fields, {name = d[2], value = f('%i listening | %s', d[1], concat(d, ' ', 3))})
		else
			break
		end
	end

	return {
		embed = {
			title = f('Popular %s on %s', what, msg.guild.name),
			description = f('Spotify Listeners: %i | Unique %s: %i', listeners, what, n),
			fields = fields,
			color = spotifyGreen,
		}
	}

end

cmds['artists'] = {function(arg, msg)

	local listeners = 0
	local counts = {}

	for member in msg.guild.members:findAll(spotifyActivity) do
		local artist = member.activity.state
		if artist then
			listeners = listeners + 1
			local hash = artist
			spotifyIncrement(counts, hash, member)
		end

	end

	return spotifyEmbed(msg, 'Artists', listeners, counts, arg)

end, 'Shows common artists according to Spotify statuses.'}

cmds['albums'] = {function(arg, msg)

	local listeners = 0
	local counts = {}

	for member in msg.guild.members:findAll(spotifyActivity) do
		local artist = member.activity.state
		local album = member.activity.textLarge
		if artist and album then
			listeners = listeners + 1
			local hash = f('%s by %s', album, artist)
			spotifyIncrement(counts, hash, member)
		end
	end

	return spotifyEmbed(msg, 'Albums', listeners, counts, arg)

end, 'Shows common albums according to Spotify statuses.'}

cmds['tracks'] = {function(arg, msg)

	local listeners = 0
	local counts = {}

	for member in msg.guild.members:findAll(spotifyActivity) do
		local artist = member.activity.state
		local track = member.activity.details
		if artist and track then
			listeners = listeners + 1
			local hash = f('%s by %s', track, artist)
			spotifyIncrement(counts, hash, member)
		end
	end

	return spotifyEmbed(msg, 'Tracks', listeners, counts, arg)

end, 'Shows common tracks according to Spotify statuses.'}

local coverCache = {}

local function getAlbumCover(id)
	local cover = coverCache[id]
	if cover then
		return cover
	end
	local res, data = http.request("GET", "https://i.scdn.co/image/" .. id)
	if res.code == 200 then
		coverCache[id] = data
		return data
	end
end

cmds['listening'] = {function(arg, msg)

	local member = arg and searchMember(msg, arg) or msg.guild:getMember(msg.author)
	if not member then return end

	local artist, album, track, start, stop, image
	if spotifyActivity(member) then
		artist = member.activity.state
		album = member.activity.textLarge
		track = member.activity.details
		start = member.activity.start
		stop = member.activity.stop
		image = member.activity.imageLarge
	end

	if artist and album and track and start and stop then

		local other = {artists = {}, albums = {}, tracks = {}}

		for m in msg.guild.members:findAll(spotifyActivity) do
			if m.id ~= member.id then
				local act = m.activity
				if act.state == artist then
					if act.textLarge == album then
						if act.details == track then
							insert(other.tracks, m.tag)
						else
							insert(other.albums, m.tag)
						end
					else
						insert(other.artists, m.tag)
					end
				end
			end
		end

		local fields = {
			{name = track, value = f('by %s on %s', artist, album)},
		}

		if #other.artists > 0 then
			insert(fields, {name = 'Current Artist Listeners', value = concat(other.artists, ', ')})
		end

		if #other.albums > 0 then
			insert(fields, {name = 'Current Album Listeners', value = concat(other.albums, ', ')})
		end

		if #other.tracks > 0 then
			insert(fields, {name = 'Current Track Listeners', value = concat(other.tracks, ', ')})
		end

		local thumbnail = image and getAlbumCover(image:match('spotify:(.*)'))

		return {
			file = thumbnail and {'image.jpg', thumbnail},
			embed = {
				author = {
					name = member.name,
					icon_url = member.avatarURL,
				},
				description = 'Listening on Spotify',
				fields = fields,
				color = spotifyGreen,
				thumbnail = thumbnail and {url = "attachment://image.jpg"},
			}
		}

	end

end, 'Shows what a member is listening too according to a Spotify status.'}

cmds['steal'] = {function(arg, msg)

	if not arg then return end
	if msg.author ~= msg.client.owner then return end
	local messages = msg.channel:getMessages(50)

	arg = arg:lower()

	local subs = {}
	local other = {}

	for message in messages:iter() do
		for animated, name, id in message.content:gmatch('<(a?):([%w_]+):(%d+)>') do
			if name:lower():find(arg) then
				insert(subs, {name, id, animated == 'a'})
			else
				insert(other, {name, id, animated == 'a'})
			end
		end
	end

	local function levensort(a, b)
		return a[1]:levenshtein(arg) < b[1]:levenshtein(arg)
	end

	local emoji
	if subs[1] then
		sort(subs, levensort)
		emoji = subs[1]
	elseif other[1] then
		sort(other, levensort)
		emoji = other[1]
	end

	if emoji then
		local guild = msg.client:getGuild('149206227455311873')
		if guild then
			local ext = emoji[3] and 'gif' or 'png'
			local res, data = http.request('GET', f("https://cdn.discordapp.com/emojis/%s.%s", emoji[2], ext))
			if res.code == 200 then
				local filename = f('temp.%s', ext)
				fs.writeFileSync(filename, data) -- hack for now
				emoji = guild:createEmoji(emoji[1], filename)
				if emoji then
					return f("Emoji %s stolen!", emoji.mentionString)
				end
			end
		end
	end

end, 'Bot owner only. Steals an emoji.'}

cmds['emojify'] = {function(arg, msg)

	if msg.author ~= msg.client.owner then return end

	local member = searchMember(msg, arg)
	if not member then return end

	if member.avatar then
		local guild = msg.client:getGuild('149206227455311873')
		if guild then
			local ext = member.avatar:find('a_') and 'gif' or 'png'
			local res, data = http.request('GET', member.avatarURL)
			if res.code == 200 then
				local filename = f('temp.%s', ext)
				fs.writeFileSync(filename, data) -- hack for now
				local emoji = assert(guild:createEmoji(member.username, filename))
				-- timer.setTimeout(5000, coroutine.wrap(emoji.delete), emoji)
				return {mention = emoji}
			end
		end
	end

end, 'Bot owner only. Converts a member avatar into an emoji.'}

cmds['rate'] = {function(arg, msg)

	local n = tonumber(arg)
	n = n and clamp(arg, 2, 100) or 100

	local m = msg.channel:getMessages(n):toArray('id')
	n = #m

	local t = Date.fromSnowflake(m[1].id) - Date.fromSnowflake(m[n].id)

	local content = '%s message rate: **%g** per minute, or 1 every **%g** seconds, measured for the previous **%i**'

	return f(content, msg.channel.mentionString, n / t:toMinutes(), t:toSeconds() / n, n)

end, 'Shows the current rate of channel messages.'}

local function canDelete(msg)
	return msg.author == msg.client.user
end

local function canBulkDelete(msg)
	if msg.id < (Date() - Time.fromWeeks(2)):toSnowflake() then return end
	local cmd = parseContent(msg.content)
	return msg.author == msg.client.user or cmds[cmd]
end

cmds['cleanup'] = {function(_, msg)

	local c = msg.channel
	local member = c.guild:getMember(msg.author)
	if not member then return end
	if not member:hasPermission(c, 'manageMessages') then return end

	if c.guild.me:hasPermission(c, 'manageMessages') then
		local messages = {}
		for message in c:getMessages(100):findAll(canBulkDelete) do
			insert(messages, message)
		end
		c:bulkDelete(messages)
	else
		for message in c:getMessages(100):findAll(canDelete) do
			message:delete()
		end
	end

end, 'Moderator only. Removes recently used commands.'}

local json = require('json')

cmds['msg'] = {function(arg, msg)

	local data = msg.client._api:getChannelMessage(msg.channel.id, arg)

	return {
		content = json.encode(data, {indent = true}),
		code = 'json',
	}

end, 'Provides the raw JSON for a message.'}

cmds['ping'] = {function()
	return 'No.'
end, 'Ping command.'}

cmds['members'] = {function(arg, msg)

	local guild = msg.guild
	local lowered = arg:lower()

	local titles = {
		'Matched Usernames',
		'Similar Usernames',
		'Matched Nicknames',
		'Similar Nicknames',
	}

	local matches = {}
	for i = 1, 6 do
		matches[i] = {}
	end

	local n = 5
	local usernameDistances = {}
	local nicknameDistances = {}

	for member in guild.members:iter() do

		local username = member.username
		local loweredUsername = username:lower()
		if loweredUsername:find(lowered) then
			insert(matches[1], member)
		else
			insert(matches[2], member)
		end
		usernameDistances[member] = username:levenshtein(arg)

		local nickname = member.nickname
		if nickname then
			local loweredNickname = nickname:lower()
			if loweredNickname:find(lowered) then
				insert(matches[3], member)
			else
				insert(matches[4], member)
			end
			nicknameDistances[member] = nickname:levenshtein(arg)
		end

	end

	sort(matches[1], function (a, b)
		return usernameDistances[a] < usernameDistances[b]
	end)

	sort(matches[2], function (a, b)
		return usernameDistances[a] < usernameDistances[b]
	end)

	sort(matches[3], function (a, b)
		return nicknameDistances[a] < nicknameDistances[b]
	end)

	sort(matches[4], function (a, b)
		return nicknameDistances[a] < nicknameDistances[b]
	end)

	local fields = {}
	for i, v in ipairs(matches) do
		local field = {'```lua'}
		for j = 1, n do
			local member = v[j]
			if v[j] then
				if member.nickname then
					insert(field, f('%i. %s#%s (%s)', j, member.username, member.discriminator, member.nickname))
				else
					insert(field, f('%i. %s#%s', j, member.username, member.discriminator))
				end
				-- insert(field, f('%i. %s', j, member.mentionString))
			end
		end
		if #field > 1 then
			insert(field, '```')
			field = {name = f('%s (%i)', titles[i], #v), value = concat(field, '\n')}
			insert(fields, field)
		end
	end

	return {
		embed = {
			fields = fields
		}
	}

end, 'Shows members that match a specific query.'}

cmds['quotelink'] = {function(_, msg)

	local messages = msg.channel:getMessages():toArray('id')
	local client = msg.client

	for i = #messages, 1, -1 do

		local m = messages[i]
		local guildId, channelId, messageId = m.content:match('https://.-%.?discordapp.com/channels/(%d+)/(%d+)/(%d+)')

		if guildId and channelId and messageId then

			local guild = assert(client:getGuild(guildId))
			local channel = assert(guild:getChannel(channelId))
			local bot = assert(guild:getMember(client.user))

			assert(bot:hasPermission(channel, 'readMessages'))
			assert(bot:hasPermission(channel, 'readMessageHistory'))

			local message = assert(channel:getMessage(messageId) or channel:getMessagesAfter(messageId, 1):iter()())

			local member = guild.members:get(message.author.id)
			local color = member and member:getColor().value or 0

			return {
				embed = {
					author = {
						name = message.author.username,
						icon_url = message.author.avatarURL,
					},
					description = message.content,
					footer = {
						text = f('#%s in %s', channel.name, guild.name),
					},
					timestamp = message.timestamp,
					color = color > 0 and color or nil,
				}
			}

		end

	end

end, 'Shows the content of the most recent message link.'}

local function getWeather(method, query) -- TODO request caching

	query.key = discordia.storage.apiux_key

	local url = {f('http://api.apixu.com/v1/%s.json', method)}
	for k, v in pairs(query) do
		insert(url, #url == 1 and '?' or '&')
		insert(url, urlencode(k))
		insert(url, '=')
		insert(url, urlencode(v))
	end
	url = concat(url)

	local res, data = http.request('GET', url)

	data = json.decode(data)

	if res.code < 300 then
		return data
	else
		if data and data.error and data.error.message then
			return nil, 'Apixu.com error: ' .. data.error.message
		else
			return nil, res.reason
		end
	end

end

cmds['weather'] = {function(arg)

	local weather, err = getWeather('current', {q = arg})

	if not weather then
		return err
	end

	local location = weather.location
	local current = weather.current

	local fields = {}
	local function add(name, value, ...)
		insert(fields, {name = name, value = value:format(...), inline = true})
	end

	add('Coordinates', '%s, %s', location.lat, location.lon)
	add('Timezone', location.tz_id)
	add('Local Time', location.localtime)
	add('Last Updated', current.last_updated)
	add('Temperature', '%s °C | %s °F', current.temp_c, current.temp_f)
	add('Feels Like', '%s °C | %s °F', current.feelslike_c, current.feelslike_f)
	add('Wind Speed', '%s kph | %s mph', current.wind_kph, current.wind_mph)
	add('Gust Speed', '%s kph | %s mph', current.gust_kph, current.gust_mph)
	add('Wind Direction', '%s° | %s', current.wind_degree, current.wind_dir)
	add('Pressure', '%s mbar | %s inHg', current.pressure_mb, current.pressure_in)
	add('Precipitation', '%s mm | %s in', current.precip_mm, current.precip_in)
	add('Humidity', '%s%% ', current.humidity)
	add('Visiblity', '%s km | %s mi', current.vis_km, current.vis_miles)
	add('Cloud Coverage', '%s%% ', current.cloud)
	add('UV Index', '%s', current.uv)

	local title
	if location.region and #location.region > 0 then
		title = f('Weather for %s, %s, %s', location.name, location.region, location.country)
	else
		title = f('Weather for %s, %s', location.name, location.country)
	end

	local localTime = Date(location.localtime_epoch)
	local lastUpdated = Date(current.last_updated_epoch)

	return {
		embed = {
			title = title,
			description = f('%s, updated %s ago',current.condition.text, (localTime - lastUpdated):toString()),
			thumbnail = {
				url = 'https:' .. current.condition.icon,
			},
			fields = fields,
			footer = {
				text = 'Powered by Apixu.com',
			},
			timestamp = lastUpdated:toISO(),
		}
	}

end, 'Shows the current weather for the provided location.'}

local function markdown(tbl)

	local widths = setmetatable({}, {__index = function() return 0 end})

	for i = 0, #tbl do
		for j, v in ipairs(tbl[i]) do
			widths[j] = math.max(widths[j], #v)
		end
	end

	local buf = {}
	local function append(str)
		return table.insert(buf, str)
	end

	local m = #tbl[0]

	append('|')
	for i, v in ipairs(tbl[0]) do
		append(' ')
		append(v)
		local n = widths[i] - #v
		if n > 0 then
			append(string.rep(' ', n))
		end
		append(' |')
	end
	append('\n')

	append('|')
	for _, n in ipairs(widths) do
		append(string.rep('-', n))
		append('--|')
	end
	append('\n')

	for _, line in ipairs(tbl) do
		append('|')
		for i = 1, m do
			local v = line[i] or ''
			append(' ')
			append(v)
			local n = widths[i] - #v
			if n > 0 then
				append(string.rep(' ', n))
			end
			append(' |')
		end
		append('\n')
	end

	return table.concat(buf)

end

cmds['forecast'] = {function(arg)

		local weather, err = getWeather('forecast', {q = arg,	days = 5})

		if not weather then
			return err
		end

		local location = weather.location

		local title
		if location.region and #location.region > 0 then
			title = f('Forecast for %s, %s, %s', location.name, location.region, location.country)
		else
			title = f('Forecast for %s, %s', location.name, location.country)
		end

		local i = 0
		local data = {}

		local function add(str, ...)
			data[i] = data[i] or {}
			insert(data[i], str:format(...))
			i = i + 1
		end

		local function reset()
			i = 0
		end

		add('')
		add('Sunrise')
		add('Sunset')
		add('Moonrise')
		add('Moonset')
		add('Max Temp (C | F)')
		add('Avg Temp (C | F)')
		add('Min Temp (C | F)')
		add('Max Wind Speed (kph | mph)')
		add('Total Precip (mm | in)')
		add('Average Visibility (km | mi)')
		add('Average Humidity (%%)')
		add('UV Index')
		reset()

		local fmt = '%s | %s'

		for _, v in ipairs(weather.forecast.forecastday) do
			add(v.date)
			add(v.astro.sunrise)
			add(v.astro.sunset)
			add(v.astro.moonrise)
			add(v.astro.moonset)
			add(fmt, v.day.maxtemp_c, v.day.maxtemp_f)
			add(fmt, v.day.avgtemp_c, v.day.avgtemp_f)
			add(fmt, v.day.mintemp_c, v.day.mintemp_f)
			add(fmt , v.day.maxwind_kph, v.day.maxwind_mph)
			add(fmt, v.day.totalprecip_mm, v.day.totalprecip_in)
			add(fmt, v.day.avgvis_km, v.day.avgvis_miles)
			add('%s', v.day.avghumidity)
			add('%s', v.day.uv)
			reset()
		end

		return f('%s\n```\n%s\n```', title, markdown(data))

end, 'Shows a weather forecast for the provided location.'}

return cmds
