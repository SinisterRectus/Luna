local fs = require('fs') -- luvit built-in library
local pathjoin = require('pathjoin') -- luvit built-in library

local pathJoin = pathjoin.pathJoin
local readFileSync = fs.readFileSync
local scandirSync = fs.scandirSync

local DIR = './modules'

local loader = {modules = {}}

local env = setmetatable({
	require = require, -- inject luvit's custom require
	loader = loader, -- inject this module
}, {__index = _G})

function loader.unload(name)
	if loader.modules[name] then
		loader.modules[name] = nil
		print('Module unloaded: ' .. name)
	else
		print('Unknown module: ' .. name)
	end
end

function loader.load(name)

	local success, err = pcall(function()
		local path = pathJoin(DIR, name) .. '.lua'
		local code = assert(readFileSync(path))
		local fn = assert(loadstring(code, '@' .. name, 't', env))
		loader.modules[name] = fn() or {}
	end)

	if success then
		print('Module loaded: ' .. name)
	else
		print('Module not loaded: ' .. name)
		print(err)
	end

end

_G.process.stdin:on('data', function(data)
	local cmd, name = data:match('(%S+)%s+(%S+)')
	if not cmd then return end
	if cmd == 'reload' then
		return loader.load(name)
	elseif cmd == 'unload' then
		return loader.unload(name)
	end
end)

for k, v in scandirSync(DIR) do
	if v == 'file' then
		local name = k:match('(.*)%.lua')
		if name and name:find('_') ~= 1 then
			loader.load(name)
		end
	end
end

return loader
