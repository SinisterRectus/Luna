local discordia = require('discordia')
local pp = require('pretty-print')
local fs = require('fs')
local timer = require('timer')
local pathJoin = require('pathJoin')

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

local function searchMember(msg, arg)

	local guild = msg.guild
	local members = guild.members
	local user = msg.mentionedUsers.first

	local member = user and guild:getMember(user) or members:get(arg)
	if member then return member end

	if arg:find('#', 1, true) then
		local username, discriminator = arg:match('(.*)#(%d+)')
		member = members:find(function(m) return m.username == username and m.discriminator == discriminator end)
		if member then
			return member
		end
	end

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

	if member then
		return member
	else
		return nil, f('No member found for: `%s`', arg)
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
		print(msg.author.username, cmd)
	end

	local success, content, code = pcall(self[cmd], arg, msg)

	local reply, err

	if success then

		if type(content) == 'string' then
			if #content > 1900 then
				reply, err = msg:reply {
					content = 'Content is too large. See attached file.',
					file = {os.time() .. '.txt', content},
					code = true,
				}
			elseif #content > 0 then
				if code then
					reply, err = msg:reply{content = content, code = code}
				else
					reply, err = msg:reply(content)
				end
			end
		elseif type(content) == 'table' then
			reply, err = msg:reply(content)
		end

	else

		reply = msg:reply {content = content,	code = 'lua'}
		if reply then
			local c = msg.channel
			if c.guild.me:hasPermission(c, 'manageMessages') then
				return setTimeout(7000, wrap(c.bulkDelete), c, {msg, reply})
			end
		end

	end

	if err and not reply then
		print(err)
	end

end})

local classDocs = {}
local fieldDocs = {}

do -- DOCS LOADER --

	local docs = {}

	local pathjoin = require('pathjoin')
	local pathJoin = pathjoin.pathJoin

	local function scan(dir)
		for fileName, fileType in fs.scandirSync(dir) do
			local path = pathJoin(dir, fileName)
			if fileType == 'file' then
				coroutine.yield(path)
			else
				scan(path)
			end
		end
	end

	local function checkType(docstring, token)
		return docstring:find(token) == 1
	end

	local function match(s, pattern) -- only useful for one return value
		return assert(s:match(pattern), s)
	end


	for file in coroutine.wrap(function() scan('/home/sinister/luna/deps/discordia') end) do

		local d = assert(fs.readFileSync(file))

		local class = {
			methods = {},
			statics = {},
			properties = {},
			parents = {},
		}

		for s in d:gmatch('--%[=%[%s*(.-)%s*%]=%]') do

			if checkType(s, '@i?c') then

				class.name = match(s, '@i?c (%w+)')
				class.userInitialized = checkType(s, '@ic')
				for parent in s:gmatch('x (%w+)') do
					insert(class.parents, parent)
				end
				class.desc = match(s, '@d (.+)'):gsub('\r?\n', ' ')
				class.parameters = {}
				for optional, paramName, paramType in s:gmatch('@(o?)p ([%w%p]+)%s+([%w%p]+)') do
					insert(class.parameters, {paramName, paramType, optional == 'o'})
				end

			elseif checkType(s, '@s?m') then

				local method = {parameters = {}}
				method.name = match(s, '@s?m ([%w%p]+)')
				for optional, paramName, paramType in s:gmatch('@(o?)p ([%w%p]+)%s+([%w%p]+)') do
					insert(method.parameters, {paramName, paramType, optional == 'o'})
				end
				method.returnType = match(s, '@r ([%w%p]+)')
				method.desc = match(s, '@d (.+)'):gsub('\r?\n', ' ')
				insert(checkType(s, '@sm') and class.statics or class.methods, method)

			elseif checkType(s, '@p') then

				local propertyName, propertyType, propertyDesc = s:match('@p (%w+)%s+([%w%p]+)%s+(.+)')
				assert(propertyName, s); assert(propertyType, s); assert(propertyDesc, s)
				propertyDesc = propertyDesc:gsub('\r?\n', ' ')
				insert(class.properties, {
					name = propertyName,
					type = propertyType,
					desc = propertyDesc,
				})

			end

		end

		if class.name then
			docs[class.name] = class
		end

	end

	local function loadClass(class, output)
		for _, v in ipairs(class.properties) do
			insert(output.properties, v.name)
		end
		for _, v in ipairs(class.statics) do
			insert(output.statics, v.name)
		end
		for _, v in ipairs(class.methods) do
			insert(output.methods, v.name)
		end
	end

	local function loadFields(class, output)

		local url = 'https://github.com/SinisterRectus/Discordia/wiki/' .. class.name

		for _, v in ipairs(class.properties) do
			output[v.name] = {
				embed = {
					title = class.name .. '.' .. v.name,
					url = url,
					description = v.desc,
				}
			}
		end

		for _, v in ipairs(class.statics) do -- TODO: returns and parameters
			output[v.name] = {
				embed = {
					title = class.name .. '.' .. v.name .. '()',
					url = url,
					description = v.desc,
				}
			}
		end

		for _, v in ipairs(class.methods) do -- TODO: returns and parameters
			output[v.name] = {
				embed = {
					title = class.name .. ':' .. v.name .. '()',
					url = url,
					description = v.desc,
				}
			}
		end

	end

	for className, class in pairs(docs) do

		fieldDocs[className] = {}

		local title = className
		if next(class.parents) then
			title = title .. ' : ' .. concat(class.parents, ', ')
		end
		local tbl = {properties = {}, methods = {}, statics = {}}
		for _, name in ipairs(class.parents) do
			loadClass(docs[name], tbl)
			loadFields(docs[name], fieldDocs[className])
		end
		loadClass(class, tbl)
		loadFields(class, fieldDocs[className])

		local fields = {}
		if next(tbl.properties) then
			insert(fields, {name = 'Properties', value = concat(tbl.properties, ', ')})
		end
		if next(tbl.statics) then
			insert(fields, {name = 'Static Methods', value = concat(tbl.statics, ', ')})
		end
		if next(tbl.methods) then
			insert(fields, {name = 'Methods', value = concat(tbl.methods, ', ')})
		end

		local url = 'https://github.com/SinisterRectus/Discordia/wiki/' .. className

		classDocs[className] = {
			embed = {
				title = title,
				url = url,
				description = class.desc,
				fields = fields,
			}
		}


	end

end -- DOCS LOADER --

cmds['docs'] = function(arg)

	if not arg then return end -- TODO: handle no arg
	arg = arg:lower()

	local queries = {}
	for query in arg:gmatch('[%w_]+') do
		insert(queries, query)
	end

	-- try all combinations of "a b" arguments
	for n = 1, #queries do

		local a = {}
		for i = 1, n do
			insert(a, queries[i])
		end
		local b = {}
		for i = n + 1, #queries do
			insert(b, queries[i])
		end

		a = concat(a)
		b = concat(b)

		if #b > 0 then

			-- TODO
			-- fuzzy match "a" with class and match "b" with field (multiple results)
			-- match "a" with class and fuzzy match "b" with field (multiple results)
			-- fuzzy match "a" with class and fuzzy match "b" with field (multiple results)
			-- fuzzy match "a b" with class (multiple results)
			-- fuzzy match "a b" with field (multiple results)

			-- match "a" with class and match "b" with field
			for className, v in pairs(fieldDocs) do
				if className:lower() == a then
					for fieldName, content in pairs(v) do
						if fieldName:lower() == b then
							return content
						end
					end
				end
			end

		else

			-- TODO
			-- match "arg" with field (multiple results)
			-- fuzzy match "arg" with class (multiple results)
			-- fuzzy match "arg" with field (multiple results)

			-- match "a" with class
			for k, v in pairs(classDocs) do
				if k:lower() == a then
					return v
				end
			end

		end

	end

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

end

cmds['avatar'] = function(arg, msg)
	if not arg then
		return {embed = {image = {url = msg.author.avatarURL}}}
	else
		local member, err = searchMember(msg, arg)
		if not member then
			return err
		end
		return {embed = {image = {url = member.avatarURL}, description = member.mentionString}}
	end
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

cmds['poop'] = function(arg, msg)

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

end

local sandbox = setmetatable({
	require = require,
	discordia = discordia,
}, {__index = _G})

cmds['lua'] = function(arg, msg)

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
		local member, err = searchMember(msg, arg)
		if not member then return err end
		local o = msg.channel:getPermissionOverwriteFor(member)
		if o and o:denyPermissions('sendMessages') then
			return f('⛔ %s (%s) blocked', member.name, member.id), true
		end
	end
end

cmds['unblock'] = function(arg, msg)
	if msg.author == msg.client.owner and msg.guild.me:hasPermission(msg.channel, 'manageRoles') then
		local member, err = searchMember(msg, arg)
		if not member then return err end
		local o = msg.channel:getPermissionOverwriteFor(member)
		if o and o:clearPermissions('sendMessages') then
			return f('✅ %s (%s) unblocked', member.name, member.id), true
		end
	end
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
	local logs = guild:getAuditLogs {limit = limit and clamp(limit, 1, 20) or 10}
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

cmds['joined'] = function(_, msg)

	local guild = msg.guild
	local members = {}

	for m in msg.channel:getMessages(10):iter() do
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
	for _, v in ipairs(sorted) do
		local seconds = Date.parseISO(v[1])
		local t = now - Date(seconds)
		insert(fields, {name = v[2], value = t:toString() .. ' ago'})
	end

	return {
		embed = {fields = fields}
	}

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
	return concat(content, '\n'), true

end

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

local coverCache = {}

local function getAlbumCover(id)
	local cover = coverCache[id]
	if cover then
		return cover
	end
	local res, data = require('coro-http').request("GET", "https://i.scdn.co/image/" .. id)
	if res.code == 200 then
		coverCache[id] = data
		return data
	end
end

cmds['listening'] = function(arg, msg)

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

end

local http = require('coro-http')

cmds['steal'] = function(arg, msg)

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

end

local DAPI_PARTNER_DATE = discordia.Date.fromSnowflake('261716079448031242')

cmds['splash'] = function(_, msg)
	if msg.guild.id ~= DAPI then return end
	if msg.guild.splash then
		return msg.guild.splashURL
	else
		local days = (discordia.Date() - DAPI_PARTNER_DATE):toDays()
		return f('Days without a guild splash: %i', days)
	end
end

cmds['emojify'] = function(arg, msg)

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
				local emoji = guild:createEmoji(member.username, filename)
				-- timer.setTimeout(5000, coroutine.wrap(emoji.delete), emoji)
				if emoji then
					return {mention = emoji}
				end
			end
		end
	end

end

local DAPI_GAMING_GUILD = '513126885279137792'
local gamingRoles = { -- channel = role
	['514872890613825544'] = '513733703243923460', -- clashers,
	['514879656717975569'] = '514922820539514901', -- skribblers,
}

cmds['sub'] = function(_, msg)

	if msg.guild.id ~= DAPI_GAMING_GUILD then return end
	local member = msg.guild:getMember(msg.author)
	if not member then return end

	local role = gamingRoles[msg.channel.id]
	if role and member:addRole(role) then
		return msg:addReaction('✅')
	end

end

cmds['unsub'] = function(_, msg)

	if msg.guild.id ~= DAPI_GAMING_GUILD then return end
	local member = msg.guild:getMember(msg.author)
	if not member then return end

	local role = gamingRoles[msg.channel.id]
	if role and member:removeRole(role) then
		return msg:addReaction('✅')
	end

end

cmds['addemoji'] = function(arg, msg)

	if msg.author ~= msg.client.owner then return end

	local args = arg:split('%s+')
	local name, url = args[1], args[2]
	if not name or not url then return end

	local res, data = http.request('GET', url)
	if res.code == 200 then
		local filename = table.remove(pathJoin.splitPath(url))
		fs.writeFileSync(filename, data) -- hack for now
		local emoji = msg.guild:createEmoji(name, filename)
		if emoji then
			return {mention = emoji}
		end
	end

end

cmds['rate'] = function(arg, msg)

	local n = arg and clamp(arg, 2, 100) or 100
	local m = msg.channel:getMessages(n):toArray('id')
	local t = discordia.Date.fromSnowflake(m[1].id) - discordia.Date.fromSnowflake(m[#m].id)

	t = t:toMinutes()

	return f('Current message rate: %g messages per minute (measured for the previous %i messages)', #m / t, #m)

end

return cmds
