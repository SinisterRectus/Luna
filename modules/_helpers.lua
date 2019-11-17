local discordia = require('discordia')
local http = require('coro-http')
local pp = require('pretty-print')

local min, max = math.min, math.max
local f = string.format
local insert, concat, sort = table.insert, table.concat, table.sort
local utf8_len, utf8_codes = utf8.len, utf8.codes
local dump = pp.dump

local Date, Time = discordia.Date, discordia.Time

local zero = {__index = function() return 0 end}

local function zeroTable()
	return setmetatable({}, zero)
end

local function levenshtein(str1, str2)

	if str1 == str2 then return 0 end

	local len1 = utf8_len(str1)
	local len2 = utf8_len(str2)

	if len1 == 0 then
		return len2
	elseif len2 == 0 then
		return len1
	end

	local matrix = {}
	for i = 0, len1 do
		matrix[i] = {[0] = i}
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end

	local i = 1
	for _, a in utf8_codes(str1) do
		local j = 1
		for _, b in utf8_codes(str2) do
			local cost = a == b and 0 or 1
			matrix[i][j] = min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
			j = j + 1
		end
		i = i + 1
	end

	return matrix[len1][len2]

end

local function markdown(tbl)

	local widths = zeroTable()
	local columns = 0
	local buf = {}
	local pos

	for i = 0, #tbl do
		columns = max(columns, #tbl[i])
		for j, v in ipairs(tbl[i]) do
			widths[j] = max(widths[j], utf8.len(v))
		end
	end

	local function append(str, n)
		if n then
			return insert(buf, str:rep(n))
		else
			return insert(buf, str)
		end
	end

	local function startRow()
		if pos then
			append('\n')
		end
		append('|')
		pos = 1
	end

	local function appendBreak(n)
		append('-', n + 2)
		append('|')
		pos = pos + 1
	end

	local function appendItem(v, pad)
		v = v or ''
		pad = pad or ' '
		append(pad)
		append(v)
		local n = widths[pos] - utf8.len(v)
		if n > 0 then
			append(pad, n)
		end
		append(pad)
		append('|')
		pos = pos + 1
	end

	append('```\n')

	startRow()
	for i = 1, columns do
		appendItem(tbl[0][i])
	end

	startRow()
	for _, n in ipairs(widths) do
		appendBreak(n)
	end

	for _, line in ipairs(tbl) do
		startRow()
		for i = 1, columns do
			appendItem(line[i])
		end
	end

	append('\n```')

	return concat(buf)

end

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
			local d = levenshtein(m.nickname, query)
			if d == 0 then
				return m
			elseif d < distance then
				member = m
				distance = d
			end
		end
		if m.username:lower():find(lowered, 1, true) then
			local d = levenshtein(m.username, query)
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

local function isBotAuthored(msg)
	return msg.author == msg.client.user
end

local function canBulkDelete(msg)
	return msg.id > (Date() - Time.fromWeeks(2)):toSnowflake()
end

local function isOnline(member)
	return member.status ~= 'offline'
end

local function hasColor(role)
	return role.color > 0
end

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

local function spotifySorter(a, b)
	return a[1] > b[1]
end

local function spotifyEmbed(msg, what, listeners, counts, limit, color)

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
			color = color,
		}
	}

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

local function makeQuote(message)

	local channel = message.channel
	local guild = channel.guild

	local member = guild and guild.members:get(message.author.id)
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

return {
	levenshtein = levenshtein,
	markdown = markdown,
	searchMember = searchMember,
	zeroTable = zeroTable,
	isBotAuthored = isBotAuthored,
	canBulkDelete = canBulkDelete,
	isOnline = isOnline,
	hasColor = hasColor,
	spotifyActivity = spotifyActivity,
	spotifyEmbed = spotifyEmbed,
	spotifyIncrement = spotifyIncrement,
	getAlbumCover = getAlbumCover,
	printLine = printLine,
	prettyLine = prettyLine,
	makeQuote = makeQuote,
}
