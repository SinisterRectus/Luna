local fs = require('fs')
local loader = require('./loader')
local discordia = require('discordia')

local f = string.format

local DAPI_GUILD = '81384788765712384'
local DAPI_MODS_ROLE = '175643578071121920'
local DISCORDIA_CHANNEL = '173885235002474497'

local sw = discordia.Stopwatch()
local clock = discordia.Clock()
local client = discordia.Client {
	fetchMembers = true,
}

clock:on('hour', function()

	local guild = client:getGuild(DAPI_GUILD)
	if not guild then return end
	local role = guild:getRole(DAPI_MODS_ROLE)
	if not role then return end

	local online
	for m in guild.members do
		if m.status == 'online' and m:hasRole(role) then
			online = true
			break
		end
	end

	if not online then
		return client.owner:sendMessage('Mods are asleep!')
	end

end)

client:once('ready', function()

	p('Logged in as ' .. client.user.username)
	p('Startup time:', sw.milliseconds)

	local db = require('./Database')('luna', client)

	print(db:initChannel(DISCORDIA_CHANNEL))
	print(db:getMessageCount(DISCORDIA_CHANNEL))

	db:startEventHandlers()
	client.db = db

	clock:start()

end)

client:on('resumed', function(id)
	p('shard resumed:', id)
end)

local prefix = '~~'
local function parseContent(content)
	if content:find(prefix, 1, true) ~= 1 then return end
	content = content:sub(prefix:len() + 1)
	local cmd, arg = content:match('(%S+)%s+(.*)')
	return cmd or content, arg
end

client:on('messageCreate', function(msg)

	local author = msg.author

	if author.bot then return end
	if author == client.user then return end
	if not msg.guild then return client.owner:sendMessage(f('%s said: %s', author.mentionString, msg.content)) end

	local spam = loader.spam
	if spam and spam(msg) then
		return msg:delete()
	end

	local highlight = loader.highlight
	if highlight and highlight(msg) then
		return client.owner:sendMessage(f('%s said in %s: %s', author.mentionString, msg.channel.mentionString, msg.content))
	end

	local cmds = loader.commands
	if cmds then
		local cmd, arg = parseContent(msg.content)
		if cmd and cmds[cmd] then
			if author ~= client.owner then
				print(author.username .. ' used command: ' .. cmd)
			end
			return cmds[cmd](arg, msg)
		end
	end

end)

client:on('messageDelete', function(msg)
	for user in msg.mentionedUsers do
		if not user.bot then
			return client.owner:sendMessage(f('message from %s deleted in %s: %s', msg.author.mentionString, msg.channel.mentionString, msg.content))
		end
	end
end)

client:run(fs.readFileSync('token.dat'))
