local fs = require('fs')
local json = require('json')
local modules = require('./modules')
local discordia = require('discordia')

local cfg = json.decode(fs.readFileSync('config.json'))

discordia.storage.apixu_key = cfg.apixu_key
discordia.extensions()
modules()

local client = discordia.Client {
	cacheAllMembers = true,
}

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
		modules.commands(msg)
	end

	if modules.acronym then
		modules.acronym(msg)
	end

	if modules.antispam then
		modules.antispam(msg)
	end

end)

client:on('messageDelete', function(message)
	if modules.undelete then
		modules.undelete(message)
	end
end)

client:run(cfg.token)
