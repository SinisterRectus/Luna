local fs = require('fs')
local json = require('json')
local discordia = require('discordia')

local cfg = json.decode(fs.readFileSync('config.json'))

local loader = require('./loader')
local modules = loader.modules

loader.loadAll()

local client = discordia.Client {
	cacheAllMembers = true,
}

client:enableAllIntents()

local clock = discordia.Clock()

clock:on('hour', function()
	if modules.pooper then
		modules.pooper(client)
	end
end)

client:once('ready', function()
	print('Ready: ' .. client.user.tag)
	clock:start()
end)

client:on('messageCreate', function(msg)

	local author = msg.author
	if author.bot and author.discriminator ~= '0000' then return end
	if author == client.user then return end

	if not msg.guild then
		return client.owner:sendf('%s said: %s', author.mentionString, msg.content)
	end

	if modules.commands then
		modules.commands.onMessageCreate(msg)
	end

	if modules.antispam then
		modules.antispam(msg)
	end

end)

client:on('messageDelete', function(msg)

	if modules.commands then
		modules.commands.onMessageDelete(msg)
	end

	if modules.undelete then
		modules.undelete(msg)
	end

end)

client:run(cfg.token)
