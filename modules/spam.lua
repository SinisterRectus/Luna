local f = string.format

local channels = {
	['173885235002474497'] = true, -- DAPI #lua_discordia
}

local stars = {}

local function star(msg)

	if msg.author.discriminator ~= '0000' then return end

	local embed = msg.embed
	if not embed then return end

	if not embed.title or not embed.title:find('star added') then return end

	local name = embed.author and embed.author.name
	if not name then return end

	local key = msg.channel.id .. name
	stars[key] = stars[key] and stars[key] + 1 or 1
	if stars[key] > 1 then
		if stars[key] == 2 then
			msg.client.owner:sendMessage(f(
				'Star spam detected at %q (%q) by %q',
				msg.channel.name,
				msg.channel.id,
				name
			))
		end
		return true
	end

end

local function caret(msg)
	if msg.content:find('%^') then
		local _, n = msg.content:gsub('%^', '')
		return n > 0.35 * msg.content:len()
	end
end

-- local function kek(msg)
-- 	return msg.content:gsub('%W', ''):lower():find('k[aeiou1-9]+k')
-- end

return function(msg)
	if not channels[msg.channel.id] then return end
	return caret(msg) or star(msg)
end
