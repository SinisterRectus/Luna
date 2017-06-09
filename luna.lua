local discordia = require('discordia')
local client = discordia.Client {
	fetchMembers = true,
}

---- module loader -------------------------------------------------------------
local fs = require('fs')
local pathjoin = require('pathjoin')

local splitPath = pathjoin.splitPath
local pathJoin = pathjoin.pathJoin
local readFile = fs.readFileSync
local scandir = fs.scandirSync
local remove = table.remove

local env = setmetatable({
	require = require, -- luvit custom require
}, {__index = _G})

local modules = {}

local function loadModule(path)
	local name = remove(splitPath(path)):match('(.*).lua')
	local success, err = pcall(function()
		local code = assert(readFile(path))
		local fn = assert(loadstring(code, name, 't', env))
		modules[name] = fn()
	end)
	if success then
		print('module loaded: ' .. name)
	else
		print(err)
	end
end

local function unloadModule(name)
	if modules[name] then
		modules[name] = nil
		print('module unloaded: ' .. name)
	else
		print('module not found: ' .. name)
	end
end

local function scan(path, name)
	for k, v in scandir(path) do
		local joined = pathJoin(path, name)
		if v == 'file' then
			if k:lower() == name then
				return joined
			end
		else
			scan(joined)
		end
	end
end

local function loadModules(path)
	for k, v in scandir(path) do
		local joined = pathJoin(path, k)
		if v == 'file' then
			if k:find('.lua', -4, true) then
				loadModule(joined)
			end
		else
			loadModules(joined)
		end
	end
end

-- loadModules('./modules')

process.stdin:on('data', function(data)
	data = data:split('%s+')
	if data[1] == 'reload' then
		local name = data[2]
		if name then
			local path = scan('./modules', name .. '.lua')
			if path then
				return loadModule(path)
			end
		end
	elseif data[1] == 'unload' then
		local name = data[2]
		if name then
			return unloadModule(name)
		end
	end
end)
--------------------------------------------------------------------------------

local prefix = '~~'
local f = string.format
local sw = discordia.Stopwatch()

-- require('./avatar')(client) -- avatar changer disabled

-- client.voice:loadOpus()
-- client.voice:loadSodium()

local DISCORDIA = '173885235002474497'

client:once('ready', function()

	p('Logged in as ' .. client.user.username)
	p('Startup time:', sw.milliseconds)

	local db = require('./Database')('luna', client)

	print(db:initChannel(DISCORDIA))
	print(db:getMessageCount(DISCORDIA))

	db:startEventHandlers()
	client.db = db

end)

client:on('resumed', function(id)
	p('shard resumed:', id)
end)

local function parseContent(content)
	if content:find(prefix, 1, true) ~= 1 then return end
	content = content:sub(prefix:len() + 1)
	local cmd, arg = content:match('(%S+)%s+(.*)')
	return cmd or content, arg
end

client:on('messageCreate', function(msg)
	if msg.author == client.user then return end
	if not msg.guild then
		return client.owner:sendMessage(f('%s said: %s', msg.author.mentionString, msg.content))
	else
		local spam = modules.spam
		if spam and spam(msg) then
			return msg:delete()
		end
		local cmds = modules.commands
		if cmds then
			local cmd, arg = parseContent(msg.content)
			if cmds[cmd] then
				return cmds[cmd](arg, msg)
			end
		end
	end
end)

client:run(readFile('token.dat'))
