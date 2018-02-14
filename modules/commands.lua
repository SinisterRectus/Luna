local discordia = require('discordia')
local pp = require('pretty-print')
local fs = require('coro-fs')
local timer = require('timer')

local random, max = math.random, math.max
local f, upper = string.format, string.upper
local insert, concat, sort = table.insert, table.concat, table.sort
local wrap = coroutine.wrap

discordia.extensions()

local clamp, round = math.clamp, math.round -- luacheck: ignore
local pack = table.pack -- luacheck: ignore

local setTimeout = timer.setTimeout
local dump = pp.dump

local actionType = discordia.enums.actionType
local Date = discordia.Date
local Time = discordia.Time

local function searchMember(members, arg)

	local member = members:get(arg)
	if member then return member end

	local distance = math.huge
	local lowered = arg:lower()

	for m in members:iter() do
		if m.nickname and m.nickname:lower():find(lowered, 1, true) then
			local d = m.nickname:levenshtein(arg)
			if d == 0 then
				return m
			elseif d < distance then
				member = m
				distance = d
			end
		end
		if m.username:lower():find(lowered, 1, true) then
			local d = m.username:levenshtein(arg)
			if d == 0 then
				return m
			elseif d < distance then
				member = m
				distance = d
			end
		end
	end

	return member

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
		print(msg.author.username, cmd)
	end

	local success, content, code = pcall(self[cmd], arg, msg)

	if success then

		if type(content) == 'string' then
			if #content > 1900 then
				return msg:reply {
					content = 'Content is too large. See attached file.',
					file = {os.time() .. '.txt', content},
					code = true,
				}
			elseif #content > 0 then
				if code then
					return msg:reply{content = content, code = code}
				else
					return msg:reply(content)
				end
			end
		elseif type(content) == 'table' then
			return msg:reply(content)
		end

	else

		local reply = msg:reply {content = content,	code = 'lua'}
		if reply then
			local c = msg.channel
			if c.guild.me:hasPermission(c, 'manageMessages') then
				return setTimeout(7000, wrap(c.bulkDelete), c, {msg, reply})
			end
		end

	end

end})

local docs = {}

coroutine.wrap(function()

	local pathJoin = require('pathjoin').pathJoin

	local function updateViaGit(ownerName, repoName) -- luacheck: ignore
		if not fs.stat(repoName) then
			print("Directory not found, cloning from GitHub...")
			os.execute(f("git clone https://github.com/%s/%s.git", ownerName, repoName))
		else
			print("Directory found, updating via GitHub...")
			os.execute(f("git -C %q pull", repoName))
		end
		if not fs.stat(repoName) then
			error("Could not find or clone repository.")
		end
		print('Updated.')
	end

	local function parseFiles(path)
		for v in fs.scandir(path) do
			local joined = pathJoin(path, v.name)
			if v.type == 'file' then
				docs[v.name:match('(.*)%.')] = joined
			elseif v.name ~= '.git' then
				parseFiles(joined)
			end
		end
	end

	-- updateViaGit('SinisterRectus', 'Discordia.wiki') -- uncomment to update on load
	parseFiles('Discordia.wiki')

end)()

local function searchDocs(arg)

	if not arg then return end

	local matches = {}
	local lowered = arg:lower()

	for name in pairs(docs) do
		if name:lower():find(lowered, 1, true) then
			insert(matches, name)
		end
	end

	if #matches == 0 then
		for name, path in pairs(docs) do
			local data = fs.readFile(path)
			if data and data:lower():find(lowered, 1, true) then
				insert(matches, name)
			end
		end
	end

	if #matches == 0 then return end
	sort(matches)
	return matches

end

local heading = '## '

local function changelogList()

	local file = io.open('CHANGELOG.md')

	local content = {}
	for line in file:lines() do
		if line:startswith(heading) then
			line = line:gsub('%c', ''):gsub(heading, '')
			insert(content, line)
		end
	end

	file:close()

	return concat(content, ', '), 'lua'

end

cmds['changelog'] = function(arg)

	if arg == 'list' then
		return changelogList()
	end

	local content = {}
	local file = io.open('CHANGELOG.md')

	local version
	if arg then
		version = heading .. arg
	else
		version = heading
	end

	local run
	for line in file:lines() do
		if run then
			if line:startswith(heading) then
				break
			end
			insert(content, line)
		else
			if line:startswith(version) then
				run = true
				insert(content, line)
			end
		end
	end

	file:close()

	if #content > 0 then
		content = concat(content, '\n')
		if #content > 1000 then
			content = content:sub(1, 1000) .. ' ...'
		end
		return content, 'md'
	else
		return changelogList()
	end

end

cmds['docs'] = function(arg)

	local matches = searchDocs(arg)
	if not matches then return end
	local url = discordia.package.homepage
	for i, match in ipairs(matches) do
		matches[i] = f('[%s](%s/wiki/%s)', match, url, match)
	end
	return {embed = {description = concat(matches, ', ')}}

end

cmds['mdocs'] = function(arg)

	local matches = searchDocs(arg)
	if not matches then return end
	local url = discordia.package.homepage
	for i, match in ipairs(matches) do
		matches[i] = f('<%s/wiki/%s>', url, match)
	end
	return concat(matches, ', ')

end

cmds['time'] = function()
	return {embed = {description = Date():toISO(' ', ' UTC')}}
end

cmds['roll'] = function(arg)
	local n = clamp(tonumber(arg) or 6, 3, 20)
	return {
		embed = {
			description = f('You roll a %i-sided die. It lands on %i.', n, random(1, n))
		}
	}
end

cmds['flip'] = function()
	return {
		embed = {
			description = f('You flip a coin. It lands on %s.', random(2) == 1 and 'heads' or 'tails')
		}
	}
end

cmds['whois'] = function(arg, msg)

	if not arg then return end
	arg = arg:lower()

	local m = searchMember(msg.guild.members, arg)
	if not m then return end

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

end

cmds['avatar'] = function(arg, msg)
	local user = arg and searchMember(msg.guild.members, arg) or msg.author
	return {embed = {image = {url = user.avatarURL}}}
end

cmds['icon'] = function(_, msg)
	return {embed = {image = {url = msg.guild.iconURL}}}
end

local function isOnline(member)
	return member.status ~= 'offline'
end

local function hasColor(role)
	return role.color > 0
end

cmds['serverinfo'] = function(_, msg)

	local guild = msg.guild
	local owner = guild.owner

	return {
		embed = {
			thumbnail = {url = guild.iconURL},
			fields = {
				{name = 'Name', value = guild.name, inline = true},
				{name = 'ID', value = guild.id, inline = true},
				{name = 'Owner', value = owner.fullname, inline = true},
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

end

cmds['color'] = function(arg)
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
end

cmds['colors'] = function(_, msg)

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

	return concat(ret, '\n'), true

end

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

local sandbox = setmetatable({
	require = require,
	discordia = discordia,
}, {__index = _G})

cmds['lua'] = function(arg, msg)

	if not arg then return end

	local owner = msg.client.owner
	if msg.author ~= owner then
		return f('%s only %s may use this command', msg.author.mentionString, owner.mentionString)
	end

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

	return concat(lines, '\n'), 'lua'

end

local enum1 = {online = 1, idle = 2, dnd = 3, offline = 4}
local enum2 = {'Online', 'Idle', 'Do Not Disturb', 'Offline'}

local DAPI = '81384788765712384'
local DISCORDIA_SUBS = '238388552663171072'

cmds['subs'] = function(_, msg)

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

end

cmds['lenny'] = function()
	return '( ͡° ͜ʖ ͡°)'
end

cmds['clean'] = function(arg, msg)
	if msg.author == msg.client.owner and msg.guild.me:hasPermission(msg.channel, 'manageMessages') then
		if not tonumber(arg) then return end
		local messages = msg.channel:getMessagesAfter(arg, 100)
		if messages then
			return msg.channel:bulkDelete(messages)
		end
	end
end

cmds['block'] = function(arg, msg)
	if msg.author == msg.client.owner and msg.guild.me:hasPermission(msg.channel, 'manageRoles') then
		local member = searchMember(msg.guild.members, arg)
		if not member then return end
		local o = msg.channel:getPermissionOverwriteFor(member)
		if o and o:denyPermissions('sendMessages') then
			return f('⛔ %s (%s) blocked', member.name, member.id), true
		end
	end
end

cmds['unblock'] = function(arg, msg)
	if msg.author == msg.client.owner and msg.guild.me:hasPermission(msg.channel, 'manageRoles') then
		local member = searchMember(msg.guild.members, arg)
		if not member then return end
		local o = msg.channel:getPermissionOverwriteFor(member)
		if o and o:clearPermissions('sendMessages') then
			return f('✅ %s (%s) unblocked', member.name, member.id), true
		end
	end
end

cmds['mention'] = function(arg, msg)
	local member = searchMember(msg.channel.members, arg)
	if not member then return end
	return f('Mention from **%s** (%s): %s', msg.author.username, msg.author.id, member.mentionString)
end

local function getBestChannel(guild, arg)
	local channelName = arg and arg:match('in:%s-([_%w]+)')
	if channelName then
		channelName = channelName:lower()
		local bestDistance, bestChannel = math.huge, nil
		for channel in guild.textChannels:iter() do
			if channel.name:lower():find(channelName) then
				local distance = channel.name:levenshtein(channelName)
				if distance < bestDistance then
					bestChannel = channel
					bestDistance = distance
				end
			end
		end
		return bestChannel
	end
end

cmds['stats'] = function(arg, msg)

	local db = discordia.storage.db
	if not db then return end

	local c = getBestChannel(msg.guild, arg) or msg.channel
	local u = msg.mentionedUsers.first or msg.author

	local sw = discordia.Stopwatch()
	local authorStats = db:getAuthorStats(c, u)
	local channelStats = db:getChannelStats(c)
	if not authorStats or not channelStats then
		return f('#%s is not indexed!', c.name), true
	end
	local t = sw.milliseconds

	local fields = {}

	for i, v in ipairs(authorStats) do
		local n = tonumber(v[2])
		local m = tonumber(channelStats[i][2])
		if n and m then
			insert(fields, {
				name = f('%s (%i)', v[1], m),
				value = f('%i (%.3f%%)', n, 100 * n / m),
				inline = true
			})
		end
	end

	local authorCount = db:getAuthorCount(c)
	local days = (discordia.Date() - discordia.Date.fromSnowflake(c.id)):toDays()

	return {
		embed = {
			title = f('Author Statistics for %s in #%s', u.name, c.name),
			description = f('%i authors, %i days', authorCount, days),
			fields = fields,
			thumbnail = {url = u.avatarURL},
			footer = {text = f('Queried in %.3f milliseconds', t)},
		}
	}

end

cmds['top'] = function(arg, msg)

	local db = discordia.storage.db
	if not db then return end

	local limit = tonumber(arg and arg:match('limit:(%d+)')) or 3
	local c = getBestChannel(msg.guild, arg) or msg.channel

	local sw = discordia.Stopwatch()
	local channelTopStats = db:getChannelTopStats(c, limit)
	local channelStats = db:getChannelStats(c)
	if not channelTopStats then
		return f('#%s is not indexed!', c.name), true
	end
	local t = sw.milliseconds

	local fields = {}
	for i, v in ipairs(channelTopStats) do
		local lines = {}
		for j, id in ipairs(v[1]) do
			insert(lines, f('%i. <@%s> %i', j, id, v[2][j]))
		end
		insert(fields, {
			name = f('%s (%i)', v[0][2], channelStats[i][2]),
			value = concat(lines, '\n'),
			inline = true
		})
	end

	local authorCount = db:getAuthorCount(c)
	local days = (discordia.Date() - discordia.Date.fromSnowflake(c.id)):toDays()

	return {
		embed = {
			title = 'Top Author Rankings for #' .. c.name,
			description = f('%i authors, %i days', authorCount, days),
			fields = fields,
			thumbnail = {url = msg.guild.iconURL or msg.client.user.avatarURL},
			footer = {text = t .. ' milliseconds'},
		}
	}

end

local function extractChange(change)
	if type(change) == 'table' then
		if #change == 1 then
			change = change[1] -- extract a lone object from its array
		end
		return change.name or dump(change, nil, true) -- extract a name or everything
	end
	return change
end

local function sorter(a, b)
	return tonumber(a.id) > tonumber(b.id)
end

cmds['audit'] = function(arg, msg)

	local guild = msg.guild

	local me = guild:getMember(msg.client.user)
	if not me or not me:hasPermission('viewAuditLog') then return end

	local author = guild:getMember(msg.author)
	if not author or not author:hasPermission('viewAuditLog') then return end

	local limit = tonumber(arg)
	local logs = guild:getAuditLogs {limit = limit and clamp(limit, 1, 10) or 10}
	if not logs then return end

	logs = logs:toArray()
	sort(logs, sorter)

	local fields = {}

	for _, log in ipairs(logs) do

		local user = log:getUser()
		local target = log:getTarget()
		local changes = log.changes
		local typ = actionType(log.actionType)


		if target then
			target = target.username or target.name
		else
			target = changes and changes.name and (changes.name.old or changes.name.new)
		end

		local name = {}

		if user then
			insert(name, user.username)
		end

		if typ then
			insert(name, typ)
		end

		if target then
			insert(name, target)
		end

		local value = {'```'}
		if changes then
			for k, change in pairs(changes) do
				local old = extractChange(change.old)
				local new = extractChange(change.new)
				insert(value, f('• %s | %s → %s', k, old, new))
			end
		end

		local t = Date() - Date.fromSnowflake(log.id)
		t = Time.fromSeconds(round(t:toSeconds())):toString()
		insert(value, f('• %s ago', t))
		insert(value, '```')

		insert(fields, {name = concat(name, ' | '), value = concat(value, '\n')})

	end

	return {embed = {fields = fields}}

end

cmds['discrims'] = function(arg, msg)

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
	return concat(content, '\n')

end

local function spotifyActivity(m)
	return m.activity and m.activity.name == 'Spotify' and m.activity.type == 2
end

local function spotifyIncrement(counts, hash, member)
	local count = counts[hash]
	if count then
		count[1] = count[1] + 1
		insert(count, member.mentionString)
	else
		counts[hash] = {1, hash, member.mentionString}
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

cmds['artists'] = function(arg, msg)

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

end

cmds['albums'] = function(arg, msg)

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

end

cmds['tracks'] = function(arg, msg)

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

end

cmds['listening'] = function(arg, msg)

	local member = arg and searchMember(msg.guild.members, arg) or msg.guild:getMember(msg.author)
	if not member then return end

	local artist, album, track, start, stop
	if spotifyActivity(member) then
		artist = member.activity.state
		album = member.activity.textLarge
		track = member.activity.details
		start = member.activity.start
		stop = member.activity.stop
	end

	if artist and album and track and start and stop then

		local other = {artists = {}, albums = {}, tracks = {}}

		for m in msg.guild.members:findAll(spotifyActivity) do
			if m.id ~= member.id then
				local act = m.activity
				if act.state == artist then
					if act.textLarge == album then
						if act.details == track then
							insert(other.tracks, m.mentionString)
						else
							insert(other.albums, m.mentionString)
						end
					else
						insert(other.artists, m.mentionString)
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

		return {
			embed = {
				author = {
					name = member.name,
					icon_url = member.avatarURL,
				},
				description = 'Listening on Spotify',
				fields = fields,
				color = spotifyGreen,
			}
		}

	end

end

return cmds
