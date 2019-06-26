local notice = [["Lua" (pronounced LOO-ah) means "Moon" in Portuguese. As such, it is neither an acronym nor an abbreviation, but a noun. More specifically, "Lua" is a name, the name of the Earth's moon and the name of the language. Like most names, it should be written in lower case with an initial capital, that is, "Lua". **Please do not write it as "LUA"**, which is both ugly and confusing, because then it becomes an acronym with different meanings for different people. So, please, write "Lua" right! - https://www.lua.org/about.html]]

local function hasNotice(channel)
	local messages = channel:getMessages(25)
	for message in messages:iter() do
		if message.content:find(notice, 1, true) then
			return true
		end
	end
end

return function(message)

	if message.guild.id ~= '377572091869790210' then return end -- luvit.io guild only

	if message.content:find('LUA') and not hasNotice(message.channel) then
		return message:reply {
			mention = message.author,
			content = notice,
		}
	end

end
