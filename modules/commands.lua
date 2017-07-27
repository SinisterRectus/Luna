local discordia = require('discordia')
local pp = require('pretty-print')
local fs = require('coro-fs')
local json = require('json')
local timer = require('timer')
local http = require('coro-http')

local date, time = os.date, os.time
local clamp, random, max, round = math.clamp, math.random, math.max, math.round
local f, upper = string.format, string.upper
local insert, concat, sort = table.insert, table.concat, table.sort
local pack = table.pack
local keys = table.keys
local dump = pp.dump
local decode = json.decode
local request = http.request
local setTimeout = timer.setTimeout
local wrap = coroutine.wrap

local url1 = "http://api.usno.navy.mil/rstt/oneday?date=today&loc=New%20York,%20NY&ID=Discord"
local url2 = "http://api.usno.navy.mil/moon/phase?date=today&nump=4&ID=Discord"

local dateString1 = '!%Y-%m-%d %H:%M:%S'
local dateString2 = '!%Y-%m-%dT%H:%M:%S'
local ZWSP = '\226\128\139'

local function code(str)
	return f('```\n%s```', str)
end

local function lua(str)
	return f('```lua\n%s```', str)
end

local function search(guild, arg) -- member fuzzy search

	local member = guild:getMember('id', arg)
	if member then return member end

	local distance = math.huge
	local lowered = arg:lower()

	for m in guild.members do
		if m.nickname and m.nickname:lower():startswith(lowered, true) then
			local d = m.nickname:levenshtein(arg)
			if d == 0 then
				return m
			elseif d < distance then
				member = m
				distance = d
			end
		end
		if m.username and m.username:lower():startswith(lowered, true) then
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

local function toDate(t)
	return date(dateString1, t)
end

local cmds = {}

cmds['luna'] = function(_, msg)
	return msg:reply {
		embed = {
			fields = {
				{name = 'Prefix', value = '```~~```'},
				{name = 'Commands', value = code(concat(keys(cmds), '\n'))}
			}
		}
	}
end

local docs = {}

coroutine.wrap(function()

	local pathJoin = require('pathjoin').pathJoin

	local function updateViaGit(ownerName, repoName)
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

	-- updateViaGit('SinisterRectus', 'Discordia.wiki') -- uncomment to update on startupt
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

cmds['docs'] = function(arg, msg)

	local matches = searchDocs(arg)
	if not matches then return end
	local url = discordia.package.homepage
	for i, match in ipairs(matches) do
		matches[i] = f('[%s](%s/wiki/%s)', match, url, match)
	end
	return msg:reply {embed = {description = concat(matches, ', ')}}

end

cmds['mdocs'] = function(arg, msg)

	local matches = searchDocs(arg)
	if not matches then return end
	local url = discordia.package.homepage
	for i, match in ipairs(matches) do
		matches[i] = f('<%s/wiki/%s>', url, match)
	end
	return msg:reply(concat(matches, ', '))

end

cmds['time'] = function(_, msg)
	return msg:reply {embed = {description = date(dateString1) .. ' UTC'}}
end

cmds['sun'] = function(_, msg) -- should probably cache these responses

	local channel = msg.channel
	channel:broadcastTyping()

	local _, data = request('GET', url1)
	data = decode(data)

	if data.error then
		return channel:sendMessage(code(data.type))
	else
		local sundata = {}
		for _, v in ipairs(data.sundata) do
			sundata[v.phen] = v.time
		end
		return channel:sendMessage {
			embed = {
				fields = {
					{name = 'Twilight Start', value = tostring(sundata.BC), inline = true},
					{name = 'Sunrise', value = tostring(sundata.R), inline = true},
					{name = 'Upper Transit', value = tostring(sundata.U), inline = true},
					{name = 'Sunset', value = tostring(sundata.S), inline = true},
					{name = 'Twilight End', value = tostring(sundata.EC), inline = true},
					{name = ZWSP, value = ZWSP, inline = true},
				},
				footer = {text = f('%s, %s', data.city, data.state)},
				timestamp = date(dateString2, time()),
			}
		}
	end

end

cmds['moon'] = function(_, msg) -- should probably cache these responses

	local channel = msg.channel
	channel:broadcastTyping()

	local _, data1 = request('GET', url1)
	data1 = decode(data1)

	local _, data2 = request('GET', url2)
	data2 = decode(data2)

	if data1.error then
		return channel:sendMessage(code(data1.type))
	elseif data2.error then
		return channel:sendMessage(code(data2.type))
	else
		local moondata = {}
		for _, v in ipairs(data1.moondata) do
			moondata[v.phen] = v.time
		end
		local phasedata = data2.phasedata
		local phase1 = phasedata[1]
		local phase2 = phasedata[2]
		local phase3 = phasedata[3]
		local phase4 = phasedata[4]
		return channel:sendMessage {
			embed = {
				fields = {
					{name = 'Moonrise', value = tostring(moondata.R), inline = true},
					{name = 'Upper Transit', value = tostring(moondata.U), inline = true},
					{name = 'Moonset', value = tostring(moondata.S), inline = true},
					{name = 'Current Phase', value = tostring(data1.curphase or data1.closestphase.phase), inline = true},
					{name = tostring(phase1.phase), value = tostring(phase1.date), inline = true},
					{name = tostring(phase2.phase), value = tostring(phase2.date), inline = true},
					{name = tostring(phase3.phase), value = tostring(phase3.date), inline = true},
					{name = tostring(phase4.phase), value = tostring(phase4.date), inline = true},
					{name = ZWSP, value = ZWSP, inline = true},
				},
				footer = {text = f('%s, %s', data1.city, data1.state)},
				timestamp = date(dateString2, time()),
			}
		}
	end

end

cmds['roll'] = function(arg, msg)
	local n = clamp(tonumber(arg) or 6, 3, 20)
	return msg:reply {
		embed = {
			description = f('You roll a %i-sided die. It lands on %i.', n, random(1, n))
		}
	}
end

cmds['flip'] = function(_, msg)
	return msg:reply {
		embed = {
			description = f('You flip a coin. It lands on %s.', random(2) == 1 and 'heads' or 'tails')
		}
	}
end

cmds['whois'] = function(arg, msg)

	if not arg then return end
	arg = arg:lower()

	local member = search(msg.guild, arg)
	if not member then return end

	local name
	if member.nickname then
		name = f('%s (%s)', member.username, member.nickname)
	else
		name = member.username
	end

	return msg:reply {
		embed = {
			thumbnail = {url = member.avatarUrl},
			fields = {
				{name = 'Name', value = name, inline = true},
				{name = 'Discriminator', value = member.discriminator, inline = true},
				{name = 'ID', value = member.id, inline = true},
				{name = 'Status', value = member.status:gsub('^%l', upper), inline = true},
				{name = 'Joined Server', value = member.joinedAt:gsub('%..*', ''):gsub('T', ' '), inline = true},
				{name = 'Joined Discord', value = toDate(member.createdAt), inline = true},
			},
			color = member.color.value,
		}
	}

end

cmds['avatar'] = function(arg, msg)
	local user = arg and search(msg.guild, arg) or msg.author
	-- return msg:reply(user.avatarUrl)
	return msg:reply {embed = {image = {url = user.avatarUrl}}}
end

cmds['serverinfo'] = function(_, msg)

	local guild = msg.guild

	local online = 0
	for member in guild.members do
		if member.status ~= 'offline' then
			online = online + 1
		end
	end

	local owner = guild.owner

	return msg:reply {
		embed = {
			thumbnail = {url = guild.iconUrl},
			fields = {
				{name = 'Name', value = guild.name, inline = true},
				{name = 'ID', value = guild.id, inline = true},
				{name = 'Owner', value = f('%s#%s', owner.username, owner.discriminator), inline = true},
				{name = 'Created At', value = toDate(guild.createdAt), inline = true},
				{name = 'Online Members', value = tostring(online), inline = true},
				{name = 'Total Members', value = tostring(guild.totalMemberCount), inline = true},
				{name = 'Text Channels', value = tostring(guild.textChannelCount), inline = true},
				{name = 'Voice Channels', value = tostring(guild.voiceChannelCount), inline = true},
				{name = 'Roles', value = tostring(guild.roleCount), inline = true},
			}
		}
	}

end

cmds['icon'] = function(_, msg)
	-- return msg:reply(msg.guild.iconUrl)
	return msg:reply {embed = {image = {url = msg.guild.iconUrl}}}
end

cmds['color'] = function(arg, msg)
	if not arg then return end
	local success, c = pcall(discordia.Color, tonumber(arg) or arg)
	if not success then return end
	return msg:reply {
		embed = {
			color = c.value,
			fields = {
				{name = 'Hexadecimal', value = c:toHex()},
				{name = 'Decimal', value = c.value},
				{name = 'RGB', value = f('%i, %i, %i', c.r, c.g, c.b)},
			}
		}
	}
end

cmds['colors'] = function(_, msg)

	local len = 0
	local roles = msg.guild.roles
	for role in roles do
		if role.color.value > 0 then
			len = max(len, #role.name)
		end
	end

	local ret = {}
	for role in roles do
		local c = role.color
		if c.value > 0 then
			local row = f('%s: %s (%s, %s, %s)',
				role.name:padleft(len),
				c:toHex(),
				tostring(c.r):padleft(3),
				tostring(c.g):padleft(3),
				tostring(c.b):padleft(3)
			)
			insert(ret, row)
		end
	end

	return msg:reply(code(concat(ret, '\n')))

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

local function handleError(msg, err)
	local reply = msg:reply(lua(err))
	return setTimeout(5000, wrap(function()
		msg:delete(); reply:delete()
	end))
end

local sandbox = setmetatable({
	require = require,
	discordia = discordia,
}, {__index = _G})

local function collect(success, ...)
	return success, pack(...)
end

cmds['lua'] = function(arg, msg)

	if not arg then return end

	local owner = msg.client.owner
	if msg.author ~= owner then
		return msg:reply {
			content = f('%s only %s may use this command', msg.author.mentionString, owner.mentionString)
		}
	end

	arg = arg:gsub('```lua\n?', ''):gsub('```\n?', '')

	local lines = {}

	sandbox.message = msg
	sandbox.channel = msg.channel
	sandbox.guild = msg.guild
	sandbox.client = msg.client
	sandbox.print = function(...) insert(lines, printLine(...)) end
	sandbox.p = function(...) insert(lines, prettyLine(...)) end

	local fn, syntaxError = load(arg, 'Luna', 't', sandbox)
	if not fn then return handleError(msg, syntaxError) end

	local success, res = collect(pcall(fn))
	if not success then return handleError(msg, res[1]) end

	if res.n > 0 then
		for i = 1, res.n do
			res[i] = tostring(res[i])
		end
		insert(lines, concat(res, '\t'))
	end

	local output = concat(lines, '\n')
	if #output > 1990 then
		return msg:reply {
			content = code('Content is too large. See attached file.'),
			file = {tostring(os.time()) .. '.txt', output}
		}
	elseif #output > 0 then
		return msg:reply(lua(output))
	end

end

local bf = {
	["+"] = "t[i] = t[i] + 1 ",
	["-"] = "t[i] = t[i] - 1 ",
	[">"] = "i = i + 1 ",
	["<"] = "i = i - 1 ",
	["."] = "w(t[i]) ",
	[","] = "t[i] = r() ",
	["["] = "while t[i] ~= 0 do ",
	["]"] = "end ",
}

cmds['bf'] = function(arg, msg)

	if not arg then return end

	local owner = msg.client.owner
	if msg.author ~= owner then
		return msg:reply {
			content = f('%s only %s may use this command', msg.author.mentionString, owner.mentionString)
		}
	end

	arg = arg:gsub('```\n?', '')

	local output = {}

	local fn, syntaxError = loadstring(arg:gsub(".", bf), "brainfuck", "t", {
		i = 0,
		t = setmetatable({}, {__index = function() return 0 end}),
		r = function() return io.read(1):byte() end,
		w = function(c) insert(output, string.char(c)) end
	})

	if not fn then return handleError(msg, syntaxError) end

	local success, res = collect(pcall(fn))
	if not success then return handleError(msg, res[1]) end

	output = concat(output)
	if #output > 1990 then
		return msg:reply {
			content = code('Content is too large. See attached file.'),
			file = {os.time() .. '.txt', output}
		}
	elseif #output > 0 then
		return msg:reply(lua(output))
	end

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
	for member in guild:findMembers(function(e) return e:hasRole(role) end) do
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

	return msg:reply {
		embed = {
			title = 'Discordia News Subscribers',
			description = 'Total: ' .. n,
			fields = fields
		}
	}

end

local limit = 15
local DISCORDIA = '173885235002474497'

-- TODO: restrict these to discordia channel

cmds['top'] = function(_, msg)

	local fields = {}
	local db = msg.client.db
	local athCount = db:getAuthorCount(DISCORDIA)
	local msgCount = db:getMessageCount(DISCORDIA)

	for res in msg.client.db:getTopAuthorsByMessageCount(DISCORDIA, limit) do
		local user = msg.client:getUser(res[1])
		insert(fields, {
			name = user and user.username or res[1],
			value = f('%i (%.2f%%)', res[2], 100 * res[2] / msgCount),
			inline = true,
		})
	end

	return msg:reply {
		embed = {
			title = 'Top Discordia Channel Authors By Message Count',
			description = f('Authors: %i | Messages: %i', athCount, msgCount),
			fields = fields,
		}
	}

end

cmds['chars'] = function(_, msg)

	local fields = {}
	local db = msg.client.db
	local athCount = db:getAuthorCount(DISCORDIA)
	local chrCount = db:getCharacterCount(DISCORDIA)

	for res in db:getTopAuthorsByCharacterCount(DISCORDIA, limit) do
		local user = msg.client:getUser(res[1])
		insert(fields, {
			name = user and user.username or res[1],
			value = f('%i (%.2f%%)', res[2], 100 * res[2] / chrCount),
			inline = true,
		})
	end

	return msg:reply {
		embed = {
			title = 'Top Discordia Channel Authors By Character Count',
			description = f('Authors: %i | Character: %i', athCount, chrCount),
			fields = fields,
		}
	}

end

cmds['stats'] = function(_, msg)

	local db = msg.client.db
	local athCount = db:getAuthorCount(DISCORDIA)
	local chrCount = db:getCharacterCount(DISCORDIA)
	local msgCount = db:getMessageCount(DISCORDIA)

	local t = time()
	local chan = msg.client:getTextChannel(DISCORDIA)
	local age = round((t - chan.createdAt) / 60 / 60 / 24)

	return msg:reply {
		embed = {
			title = 'Discordia Channel Statistics',
			description = 'Since ' .. date(dateString1, chan.createdAt),
			fields = {
				{name = 'Authors', value = athCount, inline = true},
				{name = 'Messages', value = msgCount, inline = true},
				{name = 'Characters', value = chrCount, inline = true},
				{name = 'Channel Age', value = age .. ' days', inline = true},
				{name = 'Avg Msgs Per Author', value = round(msgCount / athCount), inline = true},
				{name = 'Avg Chars Per Msg', value = round(chrCount / msgCount), inline = true},
				{name = 'Avg Chars Per Author', value = round(chrCount / athCount), inline = true},
				{name = 'Avg Msgs Per Day', value = round(msgCount / age), inline = true},
				{name = ZWSP, value = ZWSP, inline = true},
			},
		}
	}

end

cmds['lenny'] = function(_, msg)
	-- msg:delete()
	return msg:reply('( ͡° ͜ʖ ͡°)')
end

cmds['clean'] = function(arg, msg)
	if msg.author ~= msg.client.owner then return end
	if not tonumber(arg) then return end
	return msg.channel:bulkDeleteAfter(arg, 100)
end

cmds['block'] = function(arg, msg)
	if msg.author ~= msg.client.owner then return end
	local member = search(msg.guild, arg)
	if not member then return end
	local o = msg.channel:getPermissionOverwriteFor(member)
	if o and o:denyPermissions('sendMessages') then
		return msg:reply(code(f('⛔ %s (%s) blocked', member.name, member.id)))
	end
end

cmds['unblock'] = function(arg, msg)
	if msg.author ~= msg.client.owner then return end
	local member = search(msg.guild, arg)
	if not member then return end
	local o = msg.channel:getPermissionOverwriteFor(member)
	if o and o:clearPermissions('sendMessages') then
		return msg:reply(code(f('✅ %s (%s) unblocked', member.name, member.id)))
	end
end

return cmds
