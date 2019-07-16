local fs = require('fs') -- luvit built-in library
local pathjoin = require('pathjoin') -- luvit built-in library

local pathJoin = pathjoin.pathJoin
local splitPath = pathjoin.splitPath
local readFileSync = fs.readFileSync
local scandirSync = fs.scandirSync
local remove = table.remove

local DIR, PATH = module.dir, module.path -- luacheck: ignore

local env = setmetatable({
	require = require, -- inject luvit's custom require
}, {__index = _G})

local modules = {}

local function unloadModule(name)
	if modules[name] then
		modules[name] = nil
		print('Module unloaded: ' .. name)
	else
		print('Module not found: ' .. name)
	end
end

local function loadModule(path, name)

	if path == PATH then return end -- ignore this file

	local success, err = pcall(function()
		local code = assert(readFileSync(path))
		local fn = assert(loadstring(code, '@' .. name, 't', env))
		modules[name] = fn()
	end)

	if success then
		print('Module loaded: ' .. name)
	else
		print('Module not loaded: ' .. name)
		print(err)
	end

end

local function loadModuleByName(name)
	local path = pathJoin(DIR, name) .. '.lua'
	return loadModule(path, name)
end

local function loadModuleByPath(path)
	local name = remove(splitPath(path)):match('(.*)%.lua')
	return loadModule(path, name)
end

_G.process.stdin:on('data', function(data)

	data = data:split('%s+')
	if not data[2] then return end
	if data[1] == 'reload' then
		return loadModuleByName(data[2])
	elseif data[1] == 'unload' then
		return unloadModule(data[2])
	end

end)

return setmetatable(modules, {__call = function()
	for k, v in scandirSync(DIR) do
		if v == 'file' then
			loadModuleByPath(pathJoin(DIR, k))
		end
	end
end})
