local sql = require('sqlite3')
local timer = require('timer')
local discordia = require('discordia')

local class = discordia.class
local sleep = timer.sleep

local format = string.format
local classes = class.classes
local isInstance = class.isInstance

local LIMIT = 100
local DELAY = 2000

local function intstr(n)
	if tonumber(n) then
		n = tostring(n):match('%d*')
		return #n > 0 and n or '0'
	else
		return tostring(n)
	end
end

local function len(obj)
	return obj and #obj or 0
end

local function exec(stmt, ...)
	return stmt:reset():bind(...):step()
end

local Database = class('Database')

function Database:__init(name, client)

	local db = sql.open(name .. '.db')

	db:exec("PRAGMA foreign_keys = ON")

	-- TODO: create indices

	db:exec [[
	CREATE TABLE IF NOT EXISTS channels (
		id       INTEGER PRIMARY KEY,
		guild_id INTEGER NOT NULL
	)
	]]

	db:exec [[
	CREATE TABLE IF NOT EXISTS messages (
		id          INTEGER PRIMARY KEY,
		channel_id  INTEGER NOT NULL,
		author_id   INTEGER NOT NULL,
		content     INTEGER NOT NULL,
		embeds      INTEGER NOT NULL,
		attachments INTEGER NOT NULL,
		FOREIGN KEY (channel_id) REFERENCES channels(id)
	)
	]]

	db:exec [[
	CREATE TABLE IF NOT EXISTS mentions (
		user_id    INTEGER NOT NULL,
		message_id INTEGER NOT NULL,
		FOREIGN KEY (message_id) REFERENCES messages(id)
	)
	]]

	db:exec [[
	CREATE TABLE IF NOT EXISTS reactions (
		emoji      INTEGER NOT NULL,
		user_id    INTEGER NOT NULL,
		message_id INTEGER NOT NULL,
		FOREIGN KEY (message_id) REFERENCES messages(id)
	)
	]]

	self._db = db
	self._client = client
	self._channels = {}

	local stmts = {
		create = db:prepare("INSERT INTO messages VALUES (?, ?, ?, ?, ?, ?)"),
		channel = db:prepare("INSERT OR REPLACE INTO channels VALUES (?, ?)"),
		mention = db:prepare("INSERT INTO mentions VALUES (?, ?)"),
		reaction = db:prepare("INSERT INTO reactions VALUES (?, ?, ?)"),
		min = db:prepare("SELECT min(id) FROM messages WHERE channel_id == ?"),
		max = db:prepare("SELECT max(id) FROM messages WHERE channel_id == ?"),
		authorCount = db:prepare("SELECT count(DISTINCT author_id) FROM messages WHERE channel_id == ?"),
		begin = db:prepare("BEGIN"),
		commit = db:prepare("COMMIT"),
	}

	local stats = [[
	SELECT
		count(id) AS Messages,
		sum(content) AS Characters,
		sum(embeds) AS Embeds,
		sum(attachments) AS Attachments
	FROM
		messages WHERE channel_id == ?
	]]

	local mentions = " FROM mentions INNER JOIN messages ON messages.id == mentions.message_id"
	local reactions = " FROM reactions INNER JOIN messages ON messages.id == reactions.message_id"
	local where = " WHERE messages.channel_id == ?"

	local m_w = mentions .. where
	local r_w = reactions .. where

	stmts.channelStats = {
		db:prepare(stats),
		db:prepare("SELECT count(*) AS 'Mentions Sent'" .. m_w),
		db:prepare("SELECT count(*) AS 'Mentions Received'" .. m_w),
		db:prepare("SELECT count(*) AS 'Reaction Sent'" .. r_w),
		db:prepare("SELECT count(*) AS 'Reactions Received'" .. r_w),
	}

	local author = " AND author_id == ?"
	local user = " AND user_id == ?"

	local m_w_a = m_w .. author
	local r_w_a = r_w .. author
	local m_w_u = m_w .. user
	local r_w_u = r_w .. user

	stmts.authorStats = {
		db:prepare(stats .. author),
		db:prepare("SELECT count(*) AS 'Mentions Sent'" .. m_w_a),
		db:prepare("SELECT count(*) AS 'Mentions Received'" .. m_w_u),
		db:prepare("SELECT count(*) AS 'Reactions Sent'" .. r_w_u),
		db:prepare("SELECT count(*) AS 'Reactions Received'" .. r_w_a),
	}

	local group = " GROUP BY 1 ORDER BY 2 DESC LIMIT ?"
	local chan = " FROM messages WHERE channel_id == ?" .. group

	local m_w_g = m_w .. group
	local r_w_g = r_w .. group
	local m_w_a_g =	m_w_a .. group
	local m_w_u_g =	m_w_u .. group
	local r_w_u_g =	r_w_u .. group
	local r_w_a_g =	r_w_a .. group

	stmts.authorTop = {
		db:prepare("SELECT user_id, count(*) AS 'Users That You Mention'" .. m_w_a_g),
		db:prepare("SELECT author_id, count(*) AS 'Users That Mention You'" .. m_w_u_g),
		db:prepare("SELECT author_id, count(*) AS 'Users That You React To'" .. r_w_u_g),
		db:prepare("SELECT user_id, count(*) AS 'Users That React To You'" .. r_w_a_g),
	}

	stmts.channelTop = {
		db:prepare("SELECT author_id, count(*) AS Messages" .. chan),
		db:prepare("SELECT author_id, sum(content) AS Characters" .. chan),
		db:prepare("SELECT author_id, sum(embeds) AS Embeds" .. chan),
		db:prepare("SELECT author_id, sum(attachments) AS Attachments" .. chan),
		db:prepare("SELECT author_id, count(*) AS 'Mentions Sent'" .. m_w_g),
		db:prepare("SELECT user_id, count(*) AS 'Mentions Received'" .. m_w_g),
		db:prepare("SELECT user_id, count(*) AS 'Reactions Sent'" .. r_w_g),
		db:prepare("SELECT author_id, count(*) AS 'Reactions Received'" .. r_w_g),
	}

	stmts.authorReactions = db:prepare("SELECT emoji, count(*) AS Reactions" .. r_w_u_g)
	stmts.channelReactions = db:prepare("SELECT emoji, count(*) AS Reactions" .. r_w_g)

	-- local rank1 = "SELECT count(*) FROM (SELECT"
	-- local rank2 = " FROM messages WHERE channel_id == ? GROUP BY author_id HAVING"
	-- stmts.ranks = {
	-- 	db:prepare(rank1 .. " count(id)" .. rank2 .. " count(id) < ?)"),
	-- 	db:prepare(rank1 .. " sum(content)" .. rank2 .. " sum(content) < ?)"),
	-- 	db:prepare(rank1 .. " sum(embeds)" .. rank2 .. " sum(embeds) < ?)"),
	-- 	db:prepare(rank1 .. " sum(attachments)" .. rank2 .. " sum(attachments) < ?)"),
	-- }

	self._stmts = stmts

end

function Database:initChannel(channel)

	assert(isInstance(channel, classes.GuildTextChannel), 'invalid channel')

	local stmts = self._stmts
	local client = self._client

	local n = 0
	local api = client._api
	local channel_id = channel.id

	exec(stmts.channel, channel_id, channel.guild.id)

	local row = exec(stmts.max, channel_id)
	local id = row[1] and intstr(row[1]) or channel_id

	print('archiving messages after ' .. id)

	while true do
		local messages = assert(api:getChannelMessages(channel_id, {after = id, limit = LIMIT}))
		local m = #messages
		if m > 0 then
			exec(stmts.begin)
			for i = m, 1, -1 do
				local msg = messages[i]
				exec(stmts.create,
					msg.id,
					msg.channel_id,
					msg.author.id,
					len(msg.content),
					len(msg.embeds),
					len(msg.attachments)
				)
				if msg.mentions then
					for _, user in ipairs(msg.mentions) do
						exec(stmts.mention, user.id, msg.id)
					end
				end
				if msg.reactions then
					for _, r in ipairs(msg.reactions) do
						local emoji, e = r.emoji
						if type(emoji.id) == 'string' then
							e = emoji.name .. ':' .. emoji.id
							emoji = emoji.id
						else
							e = emoji.name
							emoji = emoji.name
						end
						local users = assert(api:getReactions(msg.channel_id, msg.id, e))
						for _, user in ipairs(users) do
							exec(stmts.reaction, emoji, user.id, msg.id)
						end
					end
				end
				n = n + 1
			end
			exec(stmts.commit)
			id = messages[1].id
		end
		if m == LIMIT then
			sleep(DELAY)
		else
			break
		end
	end

	self._channels[channel_id] = true

	print(format('archived %i messages', n))

end

local function one(stmt, out, ...)
	local res = stmt:reset():bind(...):resultset('ih')
	if not res then return out end
	for i, name in ipairs(res[0]) do
		local value = intstr(res[i][1])
		table.insert(out, {name, value})
	end
	return out
end

local function many(stmt, out, ...)
	local res, n = stmt:reset():bind(...):resultset('ih')
	if not res then return out end
	for _, v in ipairs(res) do
		for i = 1, n do
			v[i] = intstr(v[i])
		end
	end
	table.insert(out, res)
	return out
end

function Database:getAuthorCount(channel)
	local res = exec(self._stmts.authorCount, channel.id)
	return res and tonumber(res[1])
end

function Database:getAuthorStats(channel, user)

	local id = channel.id
	if not self._channels[id] then return end
	local stmts = self._stmts
	local user_id = user.id

	local ret = {}
	for _, stmt in ipairs(stmts.authorStats) do
		one(stmt, ret, id, user_id)
	end

	return ret

end

function Database:getChannelStats(channel)

	local id = channel.id
	if not self._channels[id] then return end
	local stmts = self._stmts

	local ret = {}

	for _, stmt in ipairs(stmts.channelStats) do
		one(stmt, ret, id)
	end

	return ret

end

function Database:getAuthorTopStats(channel, user, limit)

	local id = channel.id
	if not self._channels[id] then return end
	local stmts = self._stmts
	local user_id = user.id

	local ret = {}

	for _, stmt in ipairs(stmts.authorTop) do
		many(stmt, ret, id, user_id, limit)
	end

	return ret

end

local map = {
	messages = 1,
	characters = 2,
	embeds = 3,
	attachments = 4,
	mentionsSent = 5,
	mentionsReceived = 6,
	reactionsSent = 7,
	reactionsReceived = 8,
}

function Database:getChannelTopStats(channel, limit, query)

	local id = channel.id
	if not self._channels[id] then return end
	local stmts = self._stmts
	query = query and map[query]

	local ret = {}

	if query then
		many(stmts.channelTop[query], ret, id, limit)
	else
		for _, stmt in ipairs(stmts.channelTop) do
			many(stmt, ret, id, limit)
		end
	end

	return ret

end

function Database:getAuthorReactionStats(channel, user, limit)

	local id = channel.id
	if not self._channels[id] then return end
	local stmts = self._stmts
	local user_id = user.id

	return many(stmts.authorReactions, {}, id, user_id, limit)

end

function Database:getChannelReactionStats(channel, limit)

	local id = channel.id
	if not self._channels[id] then return end
	local stmts = self._stmts

	return many(stmts.channelReactions, {}, id, limit)

end

return Database
