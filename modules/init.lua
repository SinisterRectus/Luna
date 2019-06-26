local fs = require('fs') -- luvit built-in library
local pathjoin = require('pathjoin') -- luvit built-in library

local splitPath = pathjoin.splitPath
local pathJoin = pathjoin.pathJoin
local readFileSync = fs.readFileSync
local scandirSync = fs.scandirSync
local remove = table.remove
local format = string.format

local env = setmetatable({
	require = require, -- inject luvit's custom require
}, {__index = _G})

local function isCallable(obj)
	local t = type(obj)
	if t == 'function' then
		return true
	elseif t == 'table' then
		local meta = getmetatable(obj)
		if meta and isCallable(meta.__call) then
			return true
		end
	end
end

local modules = {}

local function unloadModule(name)
	if modules[name] then
		modules[name] = nil
		print('Module unloaded: ' .. name)
	else
		print('Module not found: ' .. name)
	end
end

local function loadModule(path, silent)

	local name = remove(splitPath(path)):match('(.*)%.lua')
	if name == 'init' or name:find('_') == 1 then return end -- ignore init and private files

	local success, err = pcall(function()

		local code = assert(readFileSync(path))
		local fn = assert(loadstring(code, '@' .. name, 't', env))
		local module = fn()

		assert(isCallable(module), format('Module %q must be a callable as a function', name))

		modules[name] = function(...)
			local success2, err2 = pcall(module, ...)
			if not success2 then
				print(err2)
				print(debug.traceback())
				unloadModule(name) -- TODO: maybe notify bot owner of module error
			end
		end

	end)

	if success then
		if not silent then
			print('Module loaded: ' .. name)
		end
	else
		print('Module not loaded: ' .. name)
		print(err)
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

local function getFullPath(directory, name)
	for k, v in scandirSync(directory) do
		local joined = pathJoin(directory, name)
		if v == 'file' then
			if k:lower() == name then
				return joined
			end
		else
			getFullPath(joined)
		end
	end
end

----

local dir = module.dir -- luacheck: ignore

_G.process.stdin:on('data', function(data)

	data = data:split('%s+')
	if not data[2] then return end

	if data[1] == 'reload' then
		local path = getFullPath(dir, data[2] .. '.lua')
		if path then
			return loadModule(path)
		end
	elseif data[1] == 'unload' then
		return unloadModule(data[2])
	end

end)

loadModules(dir)

return modules
