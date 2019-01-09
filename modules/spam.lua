local channels = {
	['381890411414683648'] = true, -- DAPI #lua_discordia
}

local stars = setmetatable({}, {__index = function() return 0 end})

local function star(msg)

	if msg.author.discriminator ~= '0000' then return end

	local embed = msg.embed
	if not embed then return end

	if not embed.title or not embed.title:find('star added') then return end

	local name = embed.author and embed.author.name
	if not name then return end

	local key = msg.channel.id .. name
	stars[key] = stars[key] + 1

	if stars[key] > 1 then
		if stars[key] == 2 then
			msg.client.owner:sendf(
				'Star spam detected at %q (%q) by %q',
				msg.channel.name,
				msg.channel.id,
				name
			)
		end
		return true
	end

end

local function dot(msg)
	return msg.content == '.'
end

local function caret(msg)
	if msg.content:find('%^') then
		local _, n = msg.content:gsub('%^', '')
		return n > 0.35 * msg.content:len()
	end
end

local function xd(msg)
	return msg.author.id == '366610426441498624' and msg.content:lower() == 'xd'
end

return function(msg)
	-- if channels[msg.channel.id] then
		return star(msg)
	-- end
end
