local fs = require('fs')
local loader = require('./loader')
local discordia = require('discordia')
local timer = require('timer')

discordia.extensions()

local DAPI_GUILD = '81384788765712384'
local DISCORDIA_CHANNEL = '381890411414683648'
-- local DAPI_GENERAL = '381870553235193857'
local LOG_CHANNEL = '430492289077477416'

local sw = discordia.Stopwatch()
local client = discordia.Client {
	-- logLevel = discordia.enums.logLevel.debug,
	cacheAllMembers = true,
}

local clock = discordia.Clock()

clock:on('hour', function()

	local guild = client:getGuild(DAPI_GUILD)
	if not guild then return end

	local me = guild:getMember(client.user)
	if not me then return end

	if me:hasPermission('manageNicknames') then
		local position = me.highestRole.position
		for member in guild.members:findAll(function(m)
			return m.name:startswith('!') and m.highestRole.position < position and m.status ~= 'offline'
		end) do
			member:setNickname('💩')
			timer.sleep(1000)
		end
	end

end)

local Database = require('./Database')

local db = Database('luna', client)
discordia.storage.db = db

client:once('ready', function()

	p('Logged in as ' .. client.user.username)
	p('Startup time:', sw.milliseconds)

	db:initChannel(client:getChannel(DISCORDIA_CHANNEL))
	db:startEventHandlers()

	clock:start()

end)

client:on('messageCreate', function(msg)

	local author = msg.author
	if author.bot and author.discriminator ~= '0000' then return end
	if author == client.user then return end

	local channel = msg.channel
	local guild = channel.guild

	if not guild then return client.owner:sendf('%s said: %s', author.mentionString, msg.content) end

	if loader.roblox then
		loader.roblox(msg)
	end

	local spam = loader.spam
	if spam and spam(msg) then
		if guild.me:hasPermission(channel, 'manageMessages') then
			return msg:delete()
		end
	end

	if loader.commands then
		loader.commands(msg)
	end

	if loader.clash then
		loader.clash(msg)
	end

end)

client:on('messageDelete', function(m)

	if #m.content == 0 then return end
	if not m.guild then return end
	if m.guild.id ~= DAPI_GUILD then return end
	if m.author == client.owner then return end

	local log = client:getChannel(LOG_CHANNEL)
	if not log then return end

	return log:send {
		content = '\n' .. m.content,
		mentions = {m.author, m.channel}
	}

end)

client:run(fs.readFileSync('token.dat'))
