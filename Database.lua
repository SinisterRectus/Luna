local sql = require('sqlite3')

local f = string.format

local MAX_INT = 2^32

local function intToStr(int)
	return tostring(int):match('%d*')
end

local Database = class('Database')

function Database:__init(name, client)

	local conn = sql.open(name .. '.db')

	conn:exec([[
	CREATE TABLE IF NOT EXISTS channels (
		id INTEGER PRIMARY KEY,
		name TEXT,
		guild_id INTEGER,
		guild_name
	);
	]])

	self.stmts = {}
	self.client = client
	self.conn = conn

end

function Database:initChannel(id)

	local conn = self.conn
	local client = self.client

	local channel = client:getTextChannel(id)
	assert(tonumber(id) and channel, 'Not a valid channel ID: ' .. id)

	local name = channel.name
	local guild = channel.guild
	local guild_id = guild and guild.id
	local guild_name = guild and guild.name

	p(f('loading channel: %s (%s in %s) ', id, name, guild_name))

	conn:exec(f("CREATE TABLE IF NOT EXISTS %q (id INTEGER PRIMARY KEY, author_id INTEGER, content TEXT);", id))

	local stmts = {
		create = conn:prepare(f("INSERT INTO %q VALUES (?, ?, ?);", id)),
		update = conn:prepare(f("UPDATE %q SET content = ? WHERE id == ?;", id)),
		delete = conn:prepare(f("DELETE FROM %q WHERE id == ?;", id)),
		get = conn:prepare(f("SELECT * FROM %q WHERE id == ?;", id)),
		messageCount = conn:prepare(f("SELECT count(*) FROM %q;", id)),
		authorCount = conn:prepare(f("SELECT count(DISTINCT author_id) FROM %q;", id)),
		characterCount = conn:prepare(f("SELECT sum(length(content)) FROM %q;", id)),
		countByAuthor = conn:prepare(f("SELECT count(*) FROM %q WHERE author_id == ?;", id)),
		countByContent = conn:prepare(f("SELECT count(*) from %q WHERE content LIKE '%%' || ? || '%%'", id)),
		searchAuthorAsc = conn:prepare(f("SELECT * FROM %q WHERE author_id == ? ORDER BY id ASC LIMIT ?;", id)),
		searchContentAsc = conn:prepare(f("SELECT * FROM %q WHERE content LIKE '%%' || ? || '%%' ORDER BY id ASC LIMIT ?;", id)),
		searchAuthorContentAsc = conn:prepare(f("SELECT * FROM %q WHERE author_id == ? AND content LIKE '%%' || ? || '%%' ORDER BY id ASC LIMIT ?;", id)),
		searchAuthorDesc = conn:prepare(f("SELECT * FROM %q WHERE author_id == ? ORDER BY id DESC LIMIT ?;", id)),
		searchContentDesc = conn:prepare(f("SELECT * FROM %q WHERE content LIKE '%%' || ? || '%%' ORDER BY id DESC LIMIT ?;", id)),
		searchAuthorContentDesc = conn:prepare(f("SELECT * FROM %q WHERE author_id == ? AND content LIKE '%%' || ? || '%%' ORDER BY id DESC LIMIT ?;", id)),
		topMessage = conn:prepare(f("SELECT author_id, count(*) FROM %q GROUP BY 1 ORDER BY 2 DESC LIMIT ?;", id)),
		topCharacter = conn:prepare(f("SELECT author_id, sum(length(content)) FROM %q GROUP BY 1 ORDER BY 2 DESC LIMIT ?;", id)),
	}

	self.stmts[id] = stmts

	-- should include an option to disable fetching old messages

	local n = 0
	local api = client._api
	local create = stmts.create
	local function archiveMessages(whence, message_id)
		repeat
			local success, data = api:getChannelMessages(id, {[whence] = message_id, limit = 100})
			if not success then return end
			local done = true
			if success and #data > 0 then
				local j, k, h
				if whence == 'before' then
					j, k, h = 1, #data, 1
				elseif whence == 'after' then
					j, k, h = #data, 1, -1
				end
				conn:exec('BEGIN;')
				for i = j, k, h do
					local v = data[i]
					create:reset():bind(v.id, v.author.id, v.content):step()
					n = n + 1
					done = false
					message_id = v.id
				end
				conn:exec('COMMIT;')
			else
				p(f('no messages found %s %s', whence, message_id))
			end
		until done
	end

	local res = conn:exec(f("SELECT * FROM channels WHERE id == %s;", id), 'i')

	if not res then

		if conn:rowexec(f("SELECT count(*) FROM %q;", id)) == 0 then
			p('archiving all messages')
			archiveMessages('before', nil)
		else
			local first_id = intToStr(conn:rowexec(f("SELECT min(id) FROM %q;", id)))
			p('archiving messages before: ' .. first_id)
			archiveMessages('before', first_id)
		end
		local stmt = conn:prepare("INSERT INTO channels VALUES (?, ?, ?, ?);")
		stmt:bind(id, name, guild_id, guild_name):step()

	elseif res[2][1] ~= name or res[4][1] ~= guild_name then

		local stmt = conn:prepare("UPDATE channels SET name = ?, guild_name = ? WHERE id == ?;")
		stmt:bind(name, guild_name, id):step()

	end

	local last_id = intToStr(conn:rowexec(f("SELECT max(id) FROM %q;", id)))
	p('archiving messages after: ' .. last_id)
	archiveMessages('after', last_id)

	return n

end

function Database:startEventHandlers()
	self:startCreateHandler()
	self:startUpdateHandler()
	self:startDeleteHandler()
end

local log = io.open('database.log', 'a')

function Database:startCreateHandler()
	self.client:on('messageCreate', function(msg)
		local stmt = self.stmts[msg.channel.id]
		if not stmt then return end
		if not pcall(function() return stmt.create:reset():bind(msg.id, msg.author.id, msg.content):step() end) then
			log:write('messageCreate: ', msg.id, '\n')
			log:flush()
		end
	end)
end

function Database:startUpdateHandler()
	self.client:on('messageUpdate', function(msg)
		local stmt = self.stmts[msg.channel.id]
		if not stmt then return end
		if not pcall(function() return stmt.update:reset():bind(msg.content, msg.id):step() end) then
			log:write('messageUpdate: ', msg.id, '\n')
			log:flush()
		end
	end)
	self.client:on('messageUpdateUncached', function(channel, id)
		local stmt = self.stmts[channel.id]
		if not stmt then return end
		local msg = channel:getMessage(id)
		if not msg then return end
		if not pcall(function() return stmt.update:reset():bind(msg.content, msg.id):step() end) then
			log:write('messageUpdateUncached: ', id, '\n')
			log:flush()
		end
	end)
end

function Database:startDeleteHandler()
	self.client:on('messageDelete', function(msg)
		local stmt = self.stmts[msg.channel.id]
		if not stmt then return end
		if not pcall(function() return stmt.delete:reset():bind(msg.id):step() end) then
			log:write('messageDelete: ', msg.id, '\n')
			log:flush()
		end
	end)
	self.client:on('messageDeleteUncached', function(channel, id)
		local stmt = self.stmts[channel.id]
		if not stmt then return end
		if not pcall(function() return stmt.delete:reset():bind(id):step() end) then
			log:write('messageDeleteUncached: ', id, '\n')
			log:flush()
		end
	end)
end

function Database:getMessageData(channel_id, id)
	local stmt = self.stmts[channel_id]
	if not stmt then return nil end
	local res = stmt.get:reset():bind(id):step()
	if not res then return nil end
	res[1] = intToStr(res[1])
	res[2] = intToStr(res[2])
	return res
end

function Database:getMessageCount(channel_id)
	local stmt = self.stmts[channel_id]
	if not stmt then return nil end
	local res = stmt.messageCount:reset():step()
	return tonumber(res[1])
end

function Database:getAuthorCount(channel_id)
	local stmt = self.stmts[channel_id]
	if not stmt then return nil end
	local res = stmt.authorCount:reset():step()
	return tonumber(res[1])
end

function Database:getCharacterCount(channel_id)
	local stmt = self.stmts[channel_id]
	if not stmt then return nil end
	local res = stmt.characterCount:reset():step()
	return tonumber(res[1])
end

function Database:getMessageCountByAuthor(channel_id, author_id)
	local stmt = self.stmts[channel_id]
	if not stmt then return nil end
	local res = stmt.countByAuthor:reset():bind(author_id):step()
	return tonumber(res[1])
end

function Database:getMessageCountByContent(channel_id, content)
	local stmt = self.stmts[channel_id]
	if not stmt then return nil end
	local res = stmt.countByContent:reset():bind(content):step()
	return tonumber(res[1])
end

function Database:search(channel_id, author_id, content, descending, limit)

	local stmt = self.stmts[channel_id]
	if not stmt then return nil end

	limit = limit or MAX_INT

	if descending then
		if author_id and content then
			stmt = stmt.searchAuthorContentDesc:reset():bind(author_id, content, limit)
		elseif author_id then
			stmt = stmt.searchAuthorDesc:reset():bind(author_id, limit)
		elseif content then
			stmt = stmt.searchContentDesc:reset():bind(content, limit)
		end
	else
		if author_id and content then
			stmt = stmt.searchAuthorContentAsc:reset():bind(author_id, content, limit)
		elseif author_id then
			stmt = stmt.searchAuthorAsc:reset():bind(author_id, limit)
		elseif content then
			stmt = stmt.searchContentAsc:reset():bind(content, limit)
		end
	end

	return function()
		local res = stmt:step()
		if not res then return nil end
		res[1] = intToStr(res[1])
		res[2] = intToStr(res[2])
		return res
	end

end

function Database:getTopAuthorsByMessageCount(channel_id, limit)
	local stmt = self.stmts[channel_id]
	if not stmt then return function() end end
	stmt = stmt.topMessage:reset():bind(limit or MAX_INT)
	return function()
		local res = stmt:step()
		if not res then return nil end
		res[1] = intToStr(res[1])
		res[2] = intToStr(res[2])
		return res
	end
end

function Database:getTopAuthorsByCharacterCount(channel_id, limit)
	local stmt = self.stmts[channel_id]
	if not stmt then return function() end end
	stmt = stmt.topCharacter:reset():bind(limit or MAX_INT)
	return function()
		local res = stmt:step()
		if not res then return nil end
		res[1] = intToStr(res[1])
		res[2] = intToStr(res[2])
		return res
	end
end

return Database
