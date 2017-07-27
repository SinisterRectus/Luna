local fs = require('fs')
local pathjoin = require('pathjoin')

local splitPath = pathjoin.splitPath
local pathJoin = pathjoin.pathJoin
local readFileSync = fs.readFileSync
local scandirSync = fs.scandirSync
local remove = table.remove

local env = setmetatable({
	require = require, -- luvit custom require
}, {__index = _G})

local modules = {}

local function loadModule(path)
	local name = remove(splitPath(path)):match('(.*).lua')
	local success, err = pcall(function()
		local code = assert(readFileSync(path))
		local fn = assert(loadstring(code, name, 't', env))
		modules[name] = fn()
	end)
	if success then
		print('module loaded: ' .. name)
	else
		print(err)
	end
end

local function unloadModule(name)
	if modules[name] then
		modules[name] = nil
		print('module unloaded: ' .. name)
	else
		print('module not found: ' .. name)
	end
end

local function scan(path, name)
	for k, v in scandirSync(path) do
		local joined = pathJoin(path, name)
		if v == 'file' then
			if k:lower() == name then
				return joined
			end
		else
			scan(joined)
		end
	end
end

local function loadModules(path)
	for k, v in scandirSync(path) do
		local joined = pathJoin(path, k)
		if v == 'file' then
			if k:find('.lua', -4, true) then
				loadModule(joined)
			end
		else
			loadModules(joined)
		end
	end
end

loadModules('./modules')

process.stdin:on('data', function(data)
	data = data:split('%s+')
	if not data[2] then return end
	if data[1] == 'reload' then
		local path = scan('./modules', data[2] .. '.lua')
		if path then
			return loadModule(path)
		end
	elseif data[1] == 'unload' then
		return unloadModule(data[2])
	end
end)

return modules
