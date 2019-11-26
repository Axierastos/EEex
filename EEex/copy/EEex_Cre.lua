
-- Arbitrary new maximum: can be adjusted if the need arises.
EEex_NewStatsCount = 0xFFFF
EEex_SimpleStatsSize = EEex_NewStatsCount * 4

EEex_ComplexStatDefinitions = {}
EEex_CurrentStatOffset = EEex_SimpleStatsSize
EEex_ComplexStatSpace = 0x0

EEex_VolatileStorageDefinitions = {}
EEex_VolatileStorageSpace = 0x0

EEex_MarshalRequestors = {}
EEex_HookMarshalDynamicStartVal = nil
EEex_HookMarshalCreatureData = {}

function EEex_RegisterVolatileField(name, attributeTable)

	-- attributeTable["construct"]
	-- attributeTable["destruct"]
	-- attributeTable["get"]
	-- attributeTable["set"]
	-- attributeTable["size"]

	local offset = EEex_VolatileStorageSpace
	attributeTable["offset"] = offset
	EEex_VolatileStorageSpace = EEex_VolatileStorageSpace + attributeTable["size"]
	EEex_VolatileStorageDefinitions[name] = attributeTable
	return offset
end

function EEex_AccessVolatileField(actorID, name)
	local volatileDef = EEex_VolatileStorageDefinitions[name]
	local volatileStart = EEex_ReadDword(EEex_GetActorShare(actorID) + 0x3B20)
	return volatileStart + volatileDef["offset"]
end

function EEex_GetVolatileField(actorID, name)
	local volatileDef = EEex_VolatileStorageDefinitions[name]
	local volatileStart = EEex_ReadDword(EEex_GetActorShare(actorID) + 0x3B20)
	local address = volatileStart + volatileDef["offset"]
	return volatileDef["get"](address)
end

function EEex_SetVolatileField(actorID, name, value)
	local volatileDef = EEex_VolatileStorageDefinitions[name]
	local volatileStart = EEex_ReadDword(EEex_GetActorShare(actorID) + 0x3B20)
	local address = volatileStart + volatileDef["offset"]
	return volatileDef["set"](address, value)
end

function EEex_GetVolatileFieldOffset(name)
	return EEex_VolatileStorageDefinitions[name]["offset"]
end

function EEex_RegisterComplexStat(name, attributeTable)

	-- attributeTable["construct"]
	-- attributeTable["destruct"]
	-- attributeTable["clear"]
	-- attributeTable["copy"]
	-- attributeTable["size"]

	local offset = EEex_CurrentStatOffset
	attributeTable["offset"] = offset
	local size = attributeTable["size"]

	EEex_CurrentStatOffset = EEex_CurrentStatOffset + size
	EEex_ComplexStatSpace = EEex_ComplexStatSpace + size

	EEex_ComplexStatDefinitions[name] = attributeTable

	return offset

end

function EEex_RegisterSimpleListStat(name, elementSize)
	return EEex_RegisterComplexStat(name, {
		["construct"] = function(address)
			EEex_Call(EEex_Label("CObList::CObList"), {10}, address, 0x0)
		end,
		["destruct"] = function(address)
			EEex_IterateCPtrList(address, function(overridePtr)
				EEex_Free(overridePtr)
			end)
			EEex_Call(EEex_Label("CObList::~CObList"), {}, address, 0x0)
		end,
		["clear"] = function(address)
			EEex_IterateCPtrList(address, function(overridePtr)
				EEex_Free(overridePtr)
			end)
			EEex_Call(EEex_Label("CObList::RemoveAll"), {}, address, 0x0)
		end,
		["copy"] = function(source, dest)
			EEex_IterateCPtrList(dest, function(overridePtr)
				EEex_Free(overridePtr)
			end)
			EEex_Call(EEex_Label("CObList::RemoveAll"), {}, dest, 0x0)
			EEex_IterateCPtrList(source, function(overridePtr)
				local copyOverridePtr = EEex_Malloc(elementSize)
				EEex_Call(EEex_Label("_memcpy"), {elementSize, overridePtr, copyOverridePtr}, nil, 0xC)
				EEex_Call(EEex_Label("CPtrList::AddTail"), {copyOverridePtr}, dest, 0x0)
			end)
		end,
		["size"] = 0x1C,
	})
end

function EEex_RegisterComplexListStat(name, attributeTable)
	return EEex_RegisterComplexStat(name, {
		["construct"] = function(address)
			EEex_Call(EEex_Label("CObList::CObList"), {10}, address, 0x0)
		end,
		["destruct"] = function(address)
			EEex_IterateCPtrList(address, function(overridePtr)
				attributeTable["destruct"](overridePtr)
				EEex_Free(overridePtr)
			end)
			EEex_Call(EEex_Label("CObList::~CObList"), {}, address, 0x0)
		end,
		["clear"] = function(address)
			EEex_IterateCPtrList(address, function(overridePtr)
				attributeTable["destruct"](overridePtr)
				EEex_Free(overridePtr)
			end)
			EEex_Call(EEex_Label("CObList::RemoveAll"), {}, address, 0x0)
		end,
		["copy"] = function(source, dest)
			EEex_IterateCPtrList(dest, function(overridePtr)
				attributeTable["destruct"](overridePtr)
				EEex_Free(overridePtr)
			end)
			EEex_Call(EEex_Label("CObList::RemoveAll"), {}, dest, 0x0)
			EEex_IterateCPtrList(source, function(overridePtr)
				local copyOverridePtr = EEex_Malloc(attributeTable["size"])
				attributeTable["construct"](copyOverridePtr)
				attributeTable["copy"](overridePtr, copyOverridePtr)
				EEex_Call(EEex_Label("CPtrList::AddTail"), {copyOverridePtr}, dest, 0x0)
			end)
		end,
		["size"] = 0x1C,
	})
end

function EEex_AccessComplexStat(actorID, name)

	local creatureData = EEex_GetActorShare(actorID)

	local newStats = nil
	if EEex_ReadDword(creatureData + 0x3748) == 0x0 then
		newStats = EEex_ReadDword(creatureData + 0x3B1C)
	else
		newStats = EEex_ReadDword(creatureData + 0x3B18)
	end

	return newStats + EEex_ComplexStatDefinitions[name]["offset"]

end

function EEex_HookConstructCreature(fromFile, toStruct)

	local newStats = EEex_Malloc(EEex_SimpleStatsSize + EEex_ComplexStatSpace)
	local newTempStats = EEex_Malloc(EEex_SimpleStatsSize + EEex_ComplexStatSpace)
	local volatileStorage = EEex_Malloc(EEex_VolatileStorageSpace)

	EEex_WriteDword(toStruct + 0x3B18, newStats)
	EEex_WriteDword(toStruct + 0x3B1C, newTempStats)
	EEex_WriteDword(toStruct + 0x3B20, volatileStorage)

	for _, complexStatDef in pairs(EEex_ComplexStatDefinitions) do
		local constructFunction = complexStatDef["construct"]
		if constructFunction then
			local statOffset = complexStatDef["offset"]
			constructFunction(newStats + statOffset)
			constructFunction(newTempStats + statOffset)
		end
	end

	for _, volatileDef in pairs(EEex_VolatileStorageDefinitions) do
		local constructFunction = volatileDef["construct"]
		if constructFunction then
			local offset = volatileDef["offset"]
			constructFunction(volatileStorage + offset)
		end
	end

end

-----------------------------
-- Marshal Functions Start --
-----------------------------

--[[

table keys include the following functions:

["marshalSize"] = function(creatureData) => Should return the size of the field that the requestor is about to write.
["marshal"] = function(creatureData, marshalAddress) => Should write the field to [marshalAddress].
["unmarshal"] = function(creatureData, address, fieldSize) => Should read the field from [address].
["default"] = function(creatureData) => The field wasn't found on the creature when reading; should read the field using a default value.

Example:

EEex_AddMarshalRequestor("B3HelloWorldTest", {
	["marshalSize"] = function(creatureData)
		Infinity_DisplayString("[marshalSize] on "..EEex_ToHex(EEex_GetActorIDShare(creatureData)))
		return 13
	end,
	["marshal"] = function(creatureData, marshalAddress)
		Infinity_DisplayString("[marshal] on "..EEex_ToHex(EEex_GetActorIDShare(creatureData)))
		EEex_WriteString(marshalAddress, "Hello World!")
	end,
	["unmarshal"] = function(creatureData, address, fieldSize)
		Infinity_DisplayString("Read stored field on "..EEex_ToHex(EEex_GetActorIDShare(creatureData))..": \""..EEex_ReadString(address).."\"")
	end,
	["default"] = function(creatureData)
		Infinity_DisplayString("I wasn't stored on the cre: "..EEex_ToHex(EEex_GetActorIDShare(creatureData)))
	end,
})

--]]

function EEex_AddMarshalRequestor(fieldName, table)
	EEex_MarshalRequestors[fieldName] = table
end

function EEex_HookMarshalCreatureSize(cre)

	EEex_HookMarshalCreatureData = {}

	-- Account for terminating null in EEex data
	local additionalSize = 1

	for fieldName, requestor in pairs(EEex_MarshalRequestors) do
		
		local requestedSize = requestor.marshalSize(cre)
		EEex_HookMarshalCreatureData[fieldName] = requestedSize

		--                                 name + null + datasize + data
		additionalSize = additionalSize + #fieldName + 1 + 4 + requestedSize
	end

	EEex_HookMarshalDynamicStartVal = 0x2D4 + additionalSize
	return additionalSize

end

function EEex_HookMarshalDynamicStart()
	return EEex_HookMarshalDynamicStartVal
end

function EEex_HookMarshalCreature(cre, allocatedMem)

	local currentAddress = allocatedMem + 0x2D4

	for fieldName, requestor in pairs(EEex_MarshalRequestors) do
		
		EEex_WriteString(currentAddress, fieldName)
		currentAddress = currentAddress + #fieldName + 1

		local requestedSize = EEex_HookMarshalCreatureData[fieldName]
		EEex_WriteDword(currentAddress, requestedSize)
		currentAddress = currentAddress + 0x4

		requestor.marshal(cre, currentAddress)
		currentAddress = currentAddress + requestedSize

	end

	EEex_WriteByte(currentAddress, 0x0)

end

function EEex_HookUnmarshalCreature(CGameSprite, pCreature)

	local seenFields = {}
	local knownSpellsOffset = EEex_ReadDword(pCreature + 0x2A0)
	local memorizationInfoOffset = EEex_ReadDword(pCreature + 0x2A8)

	if knownSpellsOffset ~= 0x2D4 and memorizationInfoOffset ~= 0x2D4 then

		local currentAddress = pCreature + 0x2D4
		local currentFieldName = EEex_ReadString(currentAddress)

		while currentFieldName ~= "" do
			
			seenFields[currentFieldName] = true
			currentAddress = currentAddress + #currentFieldName + 1
	
			local fieldSize = EEex_ReadDword(currentAddress)
			currentAddress = currentAddress + 0x4
	
			local requestor = EEex_MarshalRequestors[currentFieldName]
			if requestor then
				requestor.unmarshal(CGameSprite, currentAddress, fieldSize)
			end
			
			currentAddress = currentAddress + fieldSize
			currentFieldName = EEex_ReadString(currentAddress)
	
		end

	end

	for fieldName, requestor in pairs(EEex_MarshalRequestors) do
		if not seenFields[fieldName] then
			requestor.default(CGameSprite)
		end
	end

end

---------------------------
-- Marshal Functions End --
---------------------------

function EEex_HookDeconstructCreature(cre)

	local newStats = EEex_ReadDword(cre + 0x3B18)
	local newTempStats = EEex_ReadDword(cre + 0x3B1C)
	local volatileStorage = EEex_ReadDword(cre + 0x3B20)

	for _, complexStatDef in pairs(EEex_ComplexStatDefinitions) do
		local destructFunction = complexStatDef["destruct"]
		if destructFunction then
			local statOffset = complexStatDef["offset"]
			destructFunction(newStats + statOffset)
			destructFunction(newTempStats + statOffset)
		end
	end

	for _, volatileDef in pairs(EEex_VolatileStorageDefinitions) do
		local destructFunction = volatileDef["destruct"]
		if destructFunction then
			local offset = volatileDef["offset"]
			destructFunction(volatileStorage + offset)
		end
	end

	EEex_Free(newStats)
	EEex_Free(newTempStats)
	EEex_Free(volatileStorage)

end

function EEex_HookReloadStats(cre)

	local newStats = EEex_ReadDword(cre + 0x3B18)
	local newTempStats = EEex_ReadDword(cre + 0x3B1C)

	-- Only the DERIVED base is reloaded - temp needs to be preserved
	-- so that stats can be detected within effect calls
	EEex_Memset(newStats, EEex_SimpleStatsSize, 0x0)

	for _, complexStatDef in pairs(EEex_ComplexStatDefinitions) do
		local clearFunction = complexStatDef["clear"]
		if clearFunction then
			local statOffset = complexStatDef["offset"]
			clearFunction(newStats + statOffset)
			clearFunction(newTempStats + statOffset)
		end
	end

end

function EEex_HookCopyStats(cre)

	local newStats = EEex_ReadDword(cre + 0x3B18)
	local newTempStats = EEex_ReadDword(cre + 0x3B1C)
	EEex_Call(EEex_Label("_memcpy"), {EEex_SimpleStatsSize, newStats, newTempStats}, nil, 0xC)

	for _, complexStatDef in pairs(EEex_ComplexStatDefinitions) do
		local copyFunction = complexStatDef["copy"]
		if copyFunction then
			local statOffset = complexStatDef["offset"]
			copyFunction(newStats + statOffset, newTempStats + statOffset)
		end
	end

end

function EEex_InstallCreatureHooks()

	EEex_DisableCodeProtection()

	-- Increase creature struct size by 0xC bytes (in memory)
	for _, address in ipairs(EEex_Label("CreAllocationSize")) do
		EEex_WriteAssembly(address + 1, {{0x3B24, 4}})
	end

	local hookNameLoad = "EEex_HookConstructCreature"
	local hookNameLoadAddress = EEex_Malloc(#hookNameLoad + 1)
	EEex_WriteString(hookNameLoadAddress, hookNameLoad)

	local hookAddressLoad = EEex_WriteAssemblyAuto({[[

		!call >CGameAIBase::CGameAIBase

		!push_dword ]], {hookNameLoadAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!push_[ebp+byte] 08
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_ebx
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 02
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!ret
	]]})

	-- Install EEex_HookConstructCreature
	EEex_WriteAssembly(EEex_Label("HookConstructCreature1"), {{hookAddressLoad, 4, 4}})
	EEex_WriteAssembly(EEex_Label("HookConstructCreature2"), {{hookAddressLoad, 4, 4}})

	-------------------------
	-- Marshal Hooks Start --
	-------------------------

	local hookNameMarshalSize = "EEex_HookMarshalCreatureSize"
	local hookNameMarshalSizeAddress = EEex_Malloc(#hookNameMarshalSize + 1)
	EEex_WriteString(hookNameMarshalSizeAddress, hookNameMarshalSize)

	local hookNameMarshal = "EEex_HookMarshalCreature"
	local hookNameMarshalAddress = EEex_Malloc(#hookNameMarshal + 1)
	EEex_WriteString(hookNameMarshalAddress, hookNameMarshal)

	local hookMarshalAddress = EEex_Label("CGameSprite::Marshal()_AllocateHook")

	local marshalHook = EEex_WriteAssemblyAuto({[[

		!push_registers

		!push_dword ]], {hookNameMarshalSizeAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!push_ebx
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 01
		!push_byte 01
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!push_byte 00
		!push_byte FF
		!push_[dword] *_g_lua
		!call >_lua_tonumberx
		!add_esp_byte 0C

		!call >__ftol2_sse
		!mov_esi_[esp+byte] 14
		!add_esi_eax
		!mov_ecx_[ebp+byte] 0C
		!add_[ecx]_eax

		!push_byte FE
		!push_[dword] *_g_lua
		!call >_lua_settop
		!add_esp_byte 08

		!push_esi
		!call >_malloc
		!add_esp_byte 04
		!mov_edi_eax

		!push_esi
		!push_byte 00
		!push_edi
		!call >_memset
		!add_esp_byte 0C

		!push_dword ]], {hookNameMarshalAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!push_ebx
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_edi
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 02
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!mov_eax_edi
		!pop_registers

		!sub_esp_byte 0C
		!jmp_dword ]], {hookMarshalAddress + 0x5, 4, 4},

	})
	EEex_WriteAssembly(hookMarshalAddress, {"!jmp_dword", {marshalHook, 4, 4}})
	local skipMemsetAddress = EEex_Label("CGameSprite::Marshal()_SkipMemsetHook")
	EEex_WriteAssembly(skipMemsetAddress, {"!jmp_dword", {skipMemsetAddress + 0xA, 4, 4}})

	local hookNameMarshalDynamicStart = "EEex_HookMarshalDynamicStart"
	local hookNameMarshalDynamicStartAddress = EEex_Malloc(#hookNameMarshalDynamicStart + 1)
	EEex_WriteString(hookNameMarshalDynamicStartAddress, hookNameMarshalDynamicStart)

	local dynamicStartHook = EEex_WriteAssemblyAuto({[[

		!push_eax
		!push_ebx
		!push_ecx
		!push_edx
		!push_esi

		!push_dword ]], {hookNameMarshalDynamicStartAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 01
		!push_byte 00
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!push_byte 00
		!push_byte FF
		!push_[dword] *_g_lua
		!call >_lua_tonumberx
		!add_esp_byte 0C
		!call >__ftol2_sse
		!mov_edi_eax

		!push_byte FE
		!push_[dword] *_g_lua
		!call >_lua_settop
		!add_esp_byte 08

		!pop_esi
		!pop_edx
		!pop_ecx
		!pop_ebx
		!pop_eax
		!ret

	]]})
	EEex_WriteAssembly(EEex_Label("CGameSprite::Marshal()_DynamicStartHook1"), {"!call", {dynamicStartHook, 4, 4}})
	local dynamicStartWrapper = EEex_WriteAssemblyAuto({[[
		!call ]], {dynamicStartHook, 4, 4}, [[
		!add_edi_esi
		!ret
	]]})
	EEex_WriteAssembly(EEex_Label("CGameSprite::Marshal()_DynamicStartHook2"), {"!call", {dynamicStartWrapper, 4, 4}, "!nop"})

	local hookNameUnmarshal = "EEex_HookUnmarshalCreature"
	local hookNameUnmarshalAddress = EEex_Malloc(#hookNameUnmarshal + 1)
	EEex_WriteString(hookNameUnmarshalAddress, hookNameUnmarshal)

	local hookUnmarshalAddress = EEex_Label("CGameSprite::Unmarshal()_Hook")

	local unmarshalHook = EEex_WriteAssemblyAuto({[[

		!call >CGameSprite::ClearMarshal

		!push_registers

		!push_dword ]], {hookNameUnmarshalAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!push_ebx
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_esi
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 02
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!pop_registers
		!jmp_dword ]], {hookUnmarshalAddress + 0x5, 4, 4},

	})
	EEex_WriteAssembly(hookUnmarshalAddress, {"!jmp_dword", {unmarshalHook, 4, 4}})

	-----------------------
	-- Marshal Hooks End --
	-----------------------

	local hookNameReload = "EEex_HookReloadStats"
	local hookNameReloadAddress = EEex_Malloc(#hookNameReload + 1)
	EEex_WriteString(hookNameReloadAddress, hookNameReload)

	-- Instead of repushing all of the stack args, I'm using a
	-- hack here and storing the ret ptr somewhere in memory,
	-- then restoring it right before it is time to return.
	local hookReloadRetPtr = EEex_Malloc(0x4)

	local hookReload1 = EEex_WriteAssemblyAuto({[[

		!mov_eax_[esp]
		!mov_[dword]_eax ]], {hookReloadRetPtr, 4}, [[
		!add_esp_byte 04

		!call >CDerivedStats::Reload

		!push_ebx

		!push_dword ]], {hookNameReloadAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 01
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!push_[dword] ]], {hookReloadRetPtr, 4}, [[
		!ret

	]]})

	local hookReload2 = EEex_WriteAssemblyAuto({[[

		!mov_eax_[esp]
		!mov_[dword]_eax ]], {hookReloadRetPtr, 4}, [[
		!add_esp_byte 04

		!call >CDerivedStats::Reload

		!push_esi

		!push_dword ]], {hookNameReloadAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 01
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!push_[dword] ]], {hookReloadRetPtr, 4}, [[
		!ret

	]]})

	-- Install EEex_HookReloadStats
	EEex_WriteAssembly(EEex_Label("HookReloadStats1"), {{hookReload1, 4, 4}})
	EEex_WriteAssembly(EEex_Label("HookReloadStats2"), {{hookReload1, 4, 4}})
	EEex_WriteAssembly(EEex_Label("HookReloadStats3"), {{hookReload1, 4, 4}})
	EEex_WriteAssembly(EEex_Label("HookReloadStats4"), {{hookReload2, 4, 4}})

	local hookNameDeconstruct = "EEex_HookDeconstructCreature"
	local hookNameDeconstructAddress = EEex_Malloc(#hookNameDeconstruct + 1)
	EEex_WriteString(hookNameDeconstructAddress, hookNameDeconstruct)

	local deconstructHookAddress = EEex_Label("CGameSprite::~CGameSprite")

	local hookDeconstruct = EEex_WriteAssemblyAuto({[[

		!push_state

		!push_ecx

		!push_dword ]], {hookNameDeconstructAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08

		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 01
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18

		!pop_state

		!push_ebp
		!mov_ebp_esp
		!push_ecx
		!push_ebx

		!jmp_dword ]], {deconstructHookAddress + 0x5, 4, 4},

	})

	-- Install EEex_HookDeconstructCreature
	EEex_WriteAssembly(deconstructHookAddress, {"!jmp_dword", {hookDeconstruct, 4, 4}})

	-- Allow engine functions to access extended states...
	local hookAccessState = EEex_WriteAssemblyAuto({[[

		$EEex_AccessStat

		!build_stack_frame
		!push_registers

		!mov_eax_[ebp+byte] 08

		!cmp_eax_dword #CB
		!jb_dword >not_my_problem

		!sub_eax_dword #CB
		!cmp_eax_dword ]], {EEex_NewStatsCount, 4}, [[
		!jae_dword >it_was_your_only_job

		!cmp_[ecx+dword]_byte #3748 00
		!je_dword >new_temp_stats

		!mov_ecx_[ecx+dword] #3B18
		!jmp_dword >access_new_stats

		@new_temp_stats
		!mov_ecx_[ecx+dword] #3B1C

		@access_new_stats
		!mov_eax_[ecx+eax*4]
		!jmp_dword >ret

		@not_my_problem

		!call >CGameSprite::GetActiveStats
		!mov_ecx_eax

		!push_[ebp+byte] 08
		!call >CDerivedStats::GetAtOffset

		!jmp_dword >ret

		@it_was_your_only_job
		!xor_eax_eax

		@ret
		!restore_stack_frame
		!ret_word 04 00

	]]})

	local hookNameCopy = "EEex_HookCopyStats"
	local hookNameCopyAddress = EEex_Malloc(#hookNameCopy + 1)
	EEex_WriteString(hookNameCopyAddress, hookNameCopy)

	local hookCopy1 = EEex_WriteAssemblyAuto({[[
		!push_state
		!push_esi
		!push_[ebp+byte] 08
		!call >CDerivedStats::operator_equ
		!push_dword ]], {hookNameCopyAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 01
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18
		!pop_state
		!ret_word 04 00
	]]})

	local hookCopy2 = EEex_WriteAssemblyAuto({[[
		!push_state
		!push_edi
		!push_[ebp+byte] 08
		!call >CDerivedStats::operator_equ
		!push_dword ]], {hookNameCopyAddress, 4}, [[
		!push_[dword] *_g_lua
		!call >_lua_getglobal
		!add_esp_byte 08
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[dword] *_g_lua
		!call >_lua_pushnumber
		!add_esp_byte 0C
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 00
		!push_byte 01
		!push_[dword] *_g_lua
		!call >_lua_pcallk
		!add_esp_byte 18
		!pop_state
		!ret_word 04 00
	]]})

	EEex_WriteAssembly(EEex_Label("HookStatsTempSet1"), {{hookCopy1, 4, 4}})
	EEex_WriteAssembly(EEex_Label("HookStatsTempSet2"), {{hookCopy2, 4, 4}})

	-- lua wrapper for above function; overrides the default
	-- value in M__EEex.lua that uses inbuilt functions.
	EEex_WriteAssemblyFunction("EEex_GetActorStat", {[[

		!build_stack_frame
		!sub_esp_byte 04
		!push_registers

		!push_byte 00
		!push_byte 02
		!push_[dword] *_g_lua
		!call >_lua_tonumberx
		!add_esp_byte 0C
		!call >__ftol2_sse
		!push_eax

		!push_byte 00
		!push_byte 01
		!push_[dword] *_g_lua
		!call >_lua_tonumberx
		!add_esp_byte 0C
		!call >__ftol2_sse

		!lea_ecx_[ebp+byte] FC
		!push_ecx
		!push_eax
		!call >CGameObjectArray::GetShare
		!add_esp_byte 08
		!mov_ecx_[ebp+byte] FC

		!call ]], {hookAccessState, 4, 4}, [[

		!push_eax
		!fild_[esp]
		!sub_esp_byte 04
		!fstp_qword:[esp]
		!push_[ebp+byte] 08
		!call >_lua_pushnumber
		!add_esp_byte 0C

		!mov_eax #01
		!restore_stack_frame
		!ret

	]]})

	-- CheckStat
	EEex_WriteAssembly(EEex_Label("HookCheckStat"), {{hookAccessState, 4, 4}, "!nop !nop !nop !nop !nop !nop !nop"})

	-- CheckStatGT
	EEex_WriteAssembly(EEex_Label("HookCheckStatGT"), {{hookAccessState, 4, 4}, "!nop !nop !nop !nop !nop !nop !nop"})

	-- CheckStatLT
	EEex_WriteAssembly(EEex_Label("HookCheckStatLT"), {{hookAccessState, 4, 4}, "!nop !nop !nop !nop !nop !nop !nop"})

	-- Opcodes #318, #324, #326
	local hookSplprotOpcodesAddress = EEex_Label("HookSplprotOpcodes")
	EEex_WriteAssembly(hookSplprotOpcodesAddress, {[[
		!push_ecx ; relation ;
		!push_esi ; b ;
		!push_eax
		!mov_ecx_edi
		!call ]], {hookAccessState, 4, 4}, [[
		!jmp_dword ]], {hookSplprotOpcodesAddress + 33, 4, 4}, [[
	]]})

	EEex_EnableCodeProtection()
end
EEex_InstallCreatureHooks()
