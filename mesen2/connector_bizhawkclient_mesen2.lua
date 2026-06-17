--[[
This is a connector script that will allow Mesen2 to Archipelago's BizHawk
Client.

Currently supports:
  - GB/GBC
  - GBA
  - NES

Place it in the same directory as the normal BizHawk connector
(`Archipelago/data/lua/`). Open your ROM in Mesen2, and open
`Debug > Script Window` in the menus. By default, this will open and run an
example script. Stop it and open `Script > Settings`. You can choose what
happens when you open this window in the future. At the bottom, check
`Allow access to I/O and OS functions` and `Allow network access`. We need
these for the script to communicate with the client window. Save the settings
and then in the Script Window, click `File > Open` and open this file. If you
need to run it manually, click the Run Script button in the toolbar at the top.
]]

local SCRIPT_VERSION = 1
local DEBUG = false

--[[
Copyright (c) 2026 Zunawe
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local PORT_FIRST = 43055
local PORT_LAST = 43059

local romHash = emu.getRomInfo()["fileSha1Hash"]

local socket = require("socket.core")
local json = require("json")
local base64 = require("base64")

local server = nil
local client = nil
local locked = false

function queuePush (self, value)
	self[self.right] = value
	self.right = self.right + 1
end

function queueIsEmpty (self)
	return self.right == self.left
end

function queueShift (self)
	value = self[self.left]
	self[self.left] = nil
	self.left = self.left + 1
	return value
end

function newQueue ()
	local queue = {left = 1, right = 1}
	return setmetatable(queue, {__index = {isEmpty = queueIsEmpty, push = queuePush, shift = queueShift}})
end

local messageQueue = newQueue()
local messageTimer = 0
local messageInterval = 0

local currentTime = 0
local previousTime = currentTime
local deltaTime = 0

function lock ()
	locked = true
	client:settimeout(2)
end

function unlock ()
	locked = false
	client:settimeout(0)
end

function identifySystem ()
	if emu.getMemorySize(emu.memType.nesPrgRom) > 0 then
		return "NES"
	elseif emu.getMemorySize(emu.memType.gbPrgRom) > 0 then
		if emu.read(0x143, emu.memType.gbPrgRom, false) == 0xC0 then
			return "GBC"
		end
		return "GB"
	elseif emu.getMemorySize(emu.memType.gbaPrgRom) > 0 then
		return "GBA"
	-- elseif emu.getMemorySize(emu.memType.snesPrgRom) > 0 then
	--	 return "SNES"
	-- elseif emu.getMemorySize(emu.memType.pcePrgRom) > 0 then
	--	 return "PC Engine"
	-- elseif emu.getMemorySize(emu.memType.smsPrgRom) > 0 then
	--	 return "SMS"
	-- elseif emu.getMemorySize(emu.memType.wsPrgRom) > 0 then
	--	 return "WS"
	end
end
local system = identifySystem()

local memTypeMap = {
	["NES"] = {
		-- Common/quickerNES
		["RAM"] = emu.memType.nesInternalRam,
		["WRAM"] = emu.memType.nesWorkRam,
		["CHR"] = emu.memType.nesChrRom,
		["CIRAM"] = emu.memType.nesNametableRam,
		["PRG ROM"] = emu.memType.nesPrgRom,
		["PALRAM"] = emu.memType.nesPaletteRam,
		["OAM"] = emu.memType.nesSpriteRam,
		["System Bus"] = emu.memType.nesDebug,
		-- NesHawk
		["PPU Bus"] = emu.memType.nesPpuDebug,
		["Battery RAM"] = emu.memType.nesSaveRam,
		["VRAM"] = emu.memType.nesChrRam,
		-- BizHawk 2.10 NesHawk
		["CHR VROM"] = emu.memType.nesChrRom,
	},
	["GB"] = {
		["ROM"] = emu.memType.gbPrgRom,
		["VRAM"] = emu.memType.gbVideoRam,
		["SRAM"] = emu.memType.gbCartRam,
		["WRAM"] = emu.memType.gbWorkRam,
		["OAM"] = emu.memType.gbSpriteRam,
		["IO"] = emu.memType.gbBootRom,
		["HRAM"] = emu.memType.gbHighRam,
		["System Bus"] = emu.memType.gameboyDebug,
	},
	["GBC"] = {
		["ROM"] = emu.memType.gbPrgRom,
		["VRAM"] = emu.memType.gbVideoRam,
		["SRAM"] = emu.memType.gbCartRam,
		["WRAM"] = emu.memType.gbWorkRam,
		["OAM"] = emu.memType.gbSpriteRam,
		["IO"] = emu.memType.gbBootRom,
		["HRAM"] = emu.memType.gbHighRam,
		["System Bus"] = emu.memType.gameboyDebug,
	},
	["GBA"] = {
		["BIOS"] = emu.memType.gbaBootRom,
		["ROM"] = emu.memType.gbaPrgRom,
		["EWRAM"] = emu.memType.gbaExtWorkRam,
		["IWRAM"] = emu.memType.gbaIntWorkRam,
		["VRAM"] = emu.memType.gbaVideoRam,
		["OAM"] = emu.memType.gbaSpriteRam,
		["Combined WRAM"] = nil,
		["System Bus"] = emu.memType.gbaDebug,
	},
}

if emu.getMemorySize(emu.memType.nesWorkRam) == 0 then
	-- BizHawk cores redirect the WRAM domain to SRAM if WRAM isn't used
	memTypeMap["NES"]["WRAM"] = emu.memType.nesSaveRam
end

local requestHandlers = {
	["PING"] = function (req)
		local res = {}

		res["type"] = "PONG"

		return res
	end,

	["SYSTEM"] = function (req)
		local res = {}

		res["type"] = "SYSTEM_RESPONSE"
		res["value"] = system

		return res
	end,

	["PREFERRED_CORES"] = function (req)
		local res = {}

		res["type"] = "PREFERRED_CORES_RESPONSE"
		res["value"] = {}

		return res
	end,

	["HASH"] = function (req)
		local res = {}

		res["type"] = "HASH_RESPONSE"
		res["value"] = romHash

		return res
	end,

	["MEMORY_SIZE"] = function (req)
		local res = {}

		res["type"] = "MEMORY_SIZE_RESPONSE"
		res["value"] = emu.getMemorySize(memTypeMap[system][req["domain"]])

		return res
	end,

	["GUARD"] = function (req)
		local res = {}
		local expectedData = base64.decode(req["expected_data"])

		local actualData = {}
		for i = 1, #expectedData do
			actualData[i] = emu.read(req["address"] + i - 1, memTypeMap[system][req["domain"]], false)
		end

		local dataIsValidated = true
		for i, byte in ipairs(actualData) do
			if byte ~= expectedData[i] then
				dataIsValidated = false
				break
			end
		end

		res["type"] = "GUARD_RESPONSE"
		res["value"] = dataIsValidated
		res["address"] = req["address"]

		return res
	end,

	["LOCK"] = function (req)
		local res = {}

		res["type"] = "LOCKED"
		lock()

		return res
	end,

	["UNLOCK"] = function (req)
		local res = {}

		res["type"] = "UNLOCKED"
		unlock()

		return res
	end,

	["READ"] = function (req)
		local res = {}

		local data = {}
		for i = 1, req["size"] do
		   data[i] = emu.read(req["address"] + i - 1, memTypeMap[system][req["domain"]], false)
		end

		res["type"] = "READ_RESPONSE"
		res["value"] = base64.encode(data)

		return res
	end,

	["WRITE"] = function (req)
		local res = {}

		local data = base64.decode(req["value"])
		for i, byte in ipairs(data) do
			emu.write(req["address"] + i - 1, byte, memTypeMap[system][req["domain"]])
		end

		res["type"] = "WRITE_RESPONSE"

		return res
	end,

	["DISPLAY_MESSAGE"] = function (req)
		local res = {}

		res["type"] = "DISPLAY_MESSAGE_RESPONSE"
		messageQueue:push(req["message"])

		return res
	end,

	["SET_MESSAGE_INTERVAL"] = function (req)
		local res = {}

		res["type"] = "SET_MESSAGE_INTERVAL_RESPONSE"
		messageInterval = req["value"]

		return res
	end,

	["default"] = function (req)
		local res = {}

		res["type"] = "ERROR"
		res["err"] = "Unknown command: "..req["type"]

		return res
	end,
}

function receive ()
	local message, err = client:receive()
	if err == "closed" then
		emu.log("Connection closed")
		unlock()
		client = nil
		showedLookingMessage = false
		return
	elseif err == "timeout" then
		unlock()
		return
	elseif err ~= nil then
		emu.log("Connection closed")
		unlock()
		client:close()
		client = nil
		showedLookingMessage = false
		return
	end

	if DEBUG then
		emu.log('Received Message: "'..message..'"')
	end

	if message == "VERSION" then
		client:send(tostring(SCRIPT_VERSION).."\n")
		return
	end

	local requests = json.decode(message)
	local responses = {}
	local failedGuard = nil
	for i, req in ipairs(requests) do
		if failedGuard ~= nil then
			responses[i] = failedGuard
		else
			local reqType = req["type"]
			if reqType == "READ" or reqType == "WRITE" or reqType == "GUARD" or reqType == "MEMORY_SIZE" then 
				local memType = memTypeMap[system][req["domain"]]
				if memType == nil then
					responses[i] = {}
					responses[i]["type"] = "ERROR"
					responses[i]["err"] = "Unknown domain: "..req["domain"]
				end
			end
			if responses[i] == nil then
				local handler = requestHandlers[reqType]
				if handler == nil then
					handler = requestHandlers["default"]
				end
				responses[i] = handler(requests[i])
				if responses[i]["type"] == "GUARD_RESPONSE" and not responses[i]["value"] then
					failedGuard = responses[i]
				end
			end
		end
	end

	client:send(json.encode(responses).."\n")
end

function initializeServer ()
	emu.log("Starting server")
	local result, err
	server, err = socket.tcp4()
	if err then
		return err
	end

	local port = PORT_FIRST
	while result == nil and port <= PORT_LAST do
		result, err = server:bind("localhost", tostring(port))
		if result == nil and err ~= "address already in use" then
			return err
		end
		if res == nil then
			port = port + 1
		end
	end

	if port > PORT_LAST then
		return "Too many instances of connector scripts already running. Exiting."
	end

	result, err = server:listen(0)
	if err then
		return err
	end

	server:settimeout(0)
	return nil
end

local showedLookingMessage = false
local deadScript = false
function onFrame ()
	if deadScript then
		return
	end

	currentTime = socket.gettime()
	deltaTime = currentTime - previousTime
	previousTime = currentTime

	messageTimer = messageTimer - deltaTime
	if messageTimer < 0 and not messageQueue:isEmpty() then
		emu.displayMessage("AP", messageQueue:shift())
		messageTimer = messageInterval
	end

	local result, err
	if client == nil and server == nil then
		result = initializeServer()
		if result ~= nil then
			emu.log(result)
			deadScript = true
		end
		return
	end

	if client == nil then
		if not showedLookingMessage then
			emu.log("Looking for client...")
			showedLookingMessage = true
		end
		client, err = server:accept()
		if client == nil then
			if err ~= "timeout" then
				emu.log(err)
			end
			return
		end

		emu.log("Client connected")
		client:settimeout(0)
		server:close()
		server = nil
	end

	repeat
		receive()
	until not locked
end

emu.addEventCallback(onFrame, emu.eventType.endFrame)
