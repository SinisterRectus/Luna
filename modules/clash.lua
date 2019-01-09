local gamingRoles = {
	['514872890613825544'] = {'513733703243923460', 'https://www.codingame.com/clashofcode/clash/%w+'}, -- clashers,
	['514879656717975569'] = {'514922820539514901', 'https://skribbl.io/%?%w+'}, -- skribblers,
}

return function(msg)

	for k, v in pairs(gamingRoles) do

		if msg.channel.id == k then

			local role = msg.guild:getRole(v[1])
			local url = msg.content:match(v[2])

			if url and role then
				if role:enableMentioning() then
					if msg:reply {mention = role, content = '<' .. url .. '> from ' .. msg.author.mentionString} then
					  msg:delete()
					end
					role:disableMentioning()
				end
			end

		end

	end

end
