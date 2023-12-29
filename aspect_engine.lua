--[[
Copyright (C) 2023-2024 Teracron.
All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
]]

-- Registry | Data Storage

local Aspect = {}

local ASP_REGISTRY : table = {}

-- External Functions

local AspExt = {}

function AspExt.RemoveQuotationMarks(data)
	if (type(data) == "string") then
		return data:gsub('"', '')
	else
		return data
	end
end

function AspExt.ReturnErrors(errorList : table)
	if (errorList == nil) then return end
	for error_line, error_context in ipairs(errorList) do
		return error_line, error_context
	end
end

function AspExt.RuntimeError(error_content, RUNTIME : boolean, overrideDebugging : boolean?)
	if (not RUNTIME) then warn "Missing RUNTIME debug data. Unable to error." return end
	if (overrideDebugging == false and RUNTIME.DEBUGGING == true) or (overrideDebugging == true) then
		task.spawn(function() -- This is to reduce slowdowns, during runtime.
			pcall(function() -- To prevent any unhandled Lua errors.
				warn(
					tostring(error_content)
				)
			end)
		end)
	end
end

function AspExt.ConstructError(ISSUE, ISSUE_CORE, EXPECTED_USAGE)
	local ERROR = "Aspect Error\n"
	if (ISSUE ~= nil) then ERROR = ERROR .. " [Issue: " .. ISSUE .. "]\n" end
	if (ISSUE_CORE ~= nil) then ERROR = ERROR .. " [Issue Core: " .. ISSUE_CORE .. "]\n" end
	if (EXPECTED_USAGE ~= nil) then ERROR = ERROR .. " [Expected Usage: " .. EXPECTED_USAGE .. "]" end
	return ERROR
end

function AspExt.InterpretCondition(str)
	local OPEN_BRACKET, CLOSE_BRACKET = str:find("{([^}]*)}")

	if OPEN_BRACKET and CLOSE_BRACKET then
		return str:sub(OPEN_BRACKET + 1, CLOSE_BRACKET - 1)
	else
		return "SYNTAX_ERROR"
	end
end

function AspExt.InterpretAction(str)
	local DATA_PATTERN = "{.-}%s*%[(.-)%]%s*$"
	local DATA = str:match(DATA_PATTERN)
	if DATA then return DATA else return "SYNTAX_ERROR" end
end

function AspExt.ValidateEvaluation(EQ)
	local MATCH_NUM_OP_NUM = "(%d+%.?%d*[eE]?%+?%-?%d*)%s*([%=<>~][%=]?)%s*(%d+%.?%d*[eE]?%+?%-?%d*)"
	local NUM1, OP, NUM2 = EQ:match(MATCH_NUM_OP_NUM)

	if not (NUM1 and OP and NUM2) then return "SYNTAX_ERROR" end

	NUM1 = tonumber(NUM1)
	NUM2 = tonumber(NUM2)

	if (NUM1 == nil) or (NUM2 == nil) then return "SYNTAX_ERROR" end

	if OP == '==' or OP == "is" then return NUM1 == NUM2
	elseif OP == '~=' or OP == '!=' then return NUM1 ~= NUM2
	elseif OP == '>' then return NUM1 > NUM2
	elseif OP == '<' then return NUM1 < NUM2
	elseif OP == '>=' then return NUM1 >= NUM2
	elseif OP == '<=' then return NUM1 <= NUM2
	else return "SYNTAX_ERROR" end
end

function AspExt.InterpretFunction(str)
	local START_INDEX, END_INDEX = str:find("%b()")
	if not (START_INDEX and END_INDEX) then
		return false, nil
	end

	local FUNCTION_SIGNATURE = str:sub(1, END_INDEX)
	local PARAMETERS = FUNCTION_SIGNATURE:match("%b()")
	if PARAMETERS then
		local PARAM_LIST = {}
		local quotedParameters = PARAMETERS:match("%b()"):sub(2, -2)
		for PARAM in quotedParameters:gmatch('"%g+"') do
			table.insert(PARAM_LIST, PARAM)
		end
		return true, PARAM_LIST
	else
		return false, nil
	end
end

function AspExt.InterpretInstructions(code, INSTRUCT)
	if not code or not INSTRUCT then return end

	local LINE_CLASSIFIER = "[^\n]+"
	local OP_PARAMS_ENTIRE = "(%S+)%s*(.*)"
	local MATCH_PARAMS = "([^%s]+)%s*"
	local MATCH_PARAMS_QUOTATIONMARKS = '"(.-)"%s*"?([^"]*)"?$'

	for LINE in code:gmatch(LINE_CLASSIFIER) do
		local PARAM_LIST = {}
		local PARAM_LIST_QUOTATIONMARKS = {}

		local OP, PARAMETERS = LINE:match(OP_PARAMS_ENTIRE)
		if not (OP and PARAMETERS) then return end

		for PARAM in PARAMETERS:gmatch(MATCH_PARAMS) do
			table.insert(PARAM_LIST, PARAM)
		end

		for PARAM in PARAMETERS:gmatch(MATCH_PARAMS_QUOTATIONMARKS) do
			table.insert(PARAM_LIST_QUOTATIONMARKS, PARAM)
		end

		INSTRUCT(OP, PARAM_LIST, PARAM_LIST_QUOTATIONMARKS, LINE)
	end
end

function AspExt.CallFunctionInRegistry(OP, RUNTIME : table)
	local is_function, param_values = AspExt.InterpretFunction(OP)
	if (is_function) then
		for FUNC_NAME, RESERVED_FUNCTION in pairs(ASP_REGISTRY) do
			local LENGTH_STORED = string.len(FUNC_NAME)
			if (string.sub(OP, 0, LENGTH_STORED) == FUNC_NAME) then
				local success, issue = pcall(function() RESERVED_FUNCTION(param_values, RUNTIME) end)
				if (success ~= true) and (issue ~= nil) then
					local Error = AspExt.ConstructError(
						"A registered function failed to execute as an action. Lua Error: " .. issue,
						"AspExt.CallFunctionInRegistry",
						"This is likely a result of an outdated engine, or a lack of error handling in the function. Ensure that any custom functions are properly coded."
					)
					return "RUNTIME_ERROR", Error
				else
					return "IN_REGISTRY", "IN_REGISTRY"
				end
			else
			end
		end
	else
		local Error = AspExt.ConstructError(
			"Registry function doesn't exist.",
			"AspExt.InterpretInstructions"
		)
		return "INVALID_FUNCTION", Error
	end
end

function AspExt.InterpretVariable(str)
	local ID = "declare"
	if string.sub(str, 1, #ID) ~= ID then
		return "SYNTAX_ERROR"
	end
	local START_BRACKET = string.find(str, "<")
	local END_BRACKET = string.find(str, ">") 
	if not (START_BRACKET and END_BRACKET and START_BRACKET < END_BRACKET) then
		return "SYNTAX_ERROR"
	end 
	local VARIABLE_NAME = string.match(str, "(%w+)%s+as%s+<")
	local EXTRACTED_DATA = string.match(str, "<(.-)>")

	if not (VARIABLE_NAME and EXTRACTED_DATA) then
		return "SYNTAX_ERROR"
	end
	return VARIABLE_NAME, EXTRACTED_DATA
end

function AspExt.FetchRuntimeVariable(str : string, RUNTIME : table)
	if (str:sub(1, 1) == "@") then
		local var = str:sub(2)
		if (RUNTIME.VARIABLES[var] ~= nil) then
			return RUNTIME.VARIABLES[var]
		else
			return "INVALID_VARIABLE"
		end
	else
		return "INVALID_VARIABLE"
	end
end

-- Built-In Functions

ASP_REGISTRY = {

	["print"] = function(PARAM_LIST, RUNTIME : table)
		for _, data in pairs(PARAM_LIST) do
			if (type(data) == "string") or (type(data) == "number") then
				for _, variable in pairs(RUNTIME.VARIABLES) do
					AspExt.RemoveQuotationMarks(variable)
				end
				data = AspExt.RemoveQuotationMarks(data)
				local variable = AspExt.FetchRuntimeVariable(data, RUNTIME)
				if (variable ~= "INVALID_VARIABLE") then
					print(variable)
				elseif (data == nil) then
					local Error = AspExt.ConstructError(
						"Nonexistent, or unreadable data has been received.",
						"print",
						'print("@data")'
					)
					AspExt.RuntimeError(Error, RUNTIME, false)
				else
					print(data)
				end
			else
				local Error = AspExt.ConstructError(
					"An invalid data type has been provided inside of the print() function.",
					"print (Engine Issue)",
					"No usage issues have been identified, as this is typically caused due to a Lua error. You may have an outdated, or malformed engine."
				)
				AspExt.RuntimeError(Error, RUNTIME, false)
				break
			end
		end
	end,

	["Test"] = function()
		print("Test function called at " .. os.date("%X") .. ".")
	end
}

-- Configurative Functions

function Aspect.RegisterRuntimeFunctions(functions : table, returnStateInStringFormat : boolean)
	local returnData : table = {}
	do
		returnData["distributions"] = 0
		returnData["incomplete"] = 0
		returnData["missingData"] = 0
	end
	local set, setError = pcall(function()
		for _, func in pairs(functions) do
			if (func["main"] ~= nil) and (func["name"] ~= nil) then
				if type(func["main"]) == "function" then
					ASP_REGISTRY[func["name"]] = func["main"]
					returnData["distributions"] = returnData["distributions"] + 1
				else
					returnData["incomplete"] = returnData["incomplete"] + 1
				end
			else
				returnData["missingData"] = returnData["missingData"] + 1
			end
		end
	end)
	if (not set) and (setError ~= nil) then
		returnData["issue"] = setError
	end

	if (returnStateInStringFormat == true) then
		local distributions = tostring(returnData["distributions"])
		local incomplete = tostring(returnData["incomplete"])
		local issue = tostring(returnData["issue"])
		local missingData = tostring(returnData["missingData"])
		return "[Distributions: " .. distributions .. "] [Unsuccessful: " .. incomplete .. "] [Malformed Functions: " .. missingData .. "] [Lua Issue: " .. issue .. "]"
	else
		return returnData
	end
end

-- Interpreter

function Aspect.Interpret(code : string, debugging : boolean?)
	local RUNTIME : table = {
		["ERROR_LIST"] = {},
		["VARIABLES"] = {},
		["DEBUGGING"] = debugging or true
	}

	local function insert_error(error_content) table.insert(RUNTIME.ERROR_LIST, error_content) end

	AspExt.InterpretInstructions(code,
		function(OP, PARAM_LIST, PARAM_LIST_QUOTATIONMARKS, LINE)
			-- print(OP)

			local INTERPRETATION_TYPES = {
				["SYNTAX_ERROR"] = "VOID",
				["IF_STATEMENT"] = "VOID",
				["IF_STATEMENT_ARITHMETIC"] = "VOID",
				["IF_STATMENT_REGISTRY_FUNCTION"] = "VOID",
				["IF_STATEMENT_SET_VARIABLE"] = "VOID",
				["REGISTRY_FUNCTION"] = "VOID",
				["SET_VARIABLE"] = "VOID"
			}

			-- Setting Variable

			if (OP == "declare") then
				INTERPRETATION_TYPES["SET_VARIABLE"] = true
				local VARIABLE_NAME, DATA = AspExt.InterpretVariable(LINE)
				if (VARIABLE_NAME ~= nil) and (DATA ~= nil) then RUNTIME.VARIABLES[VARIABLE_NAME] = DATA return end
				if (VARIABLE_NAME == "SYNTAX_ERROR") then INTERPRETATION_TYPES["SET_VARIABLE"] = false end
			end

			-- Registry Functions

			local CALL_STATUS, ISSUE = AspExt.CallFunctionInRegistry(OP, RUNTIME)
			if (CALL_STATUS == "IN_REGISTRY") then return end
			if (CALL_STATUS == "RUNTIME_ERROR") then AspExt.RuntimeError(ISSUE, RUNTIME, false) insert_error(ISSUE) return end
			if (CALL_STATUS == "INVALID_FUNCTION") then
				INTERPRETATION_TYPES["REGISTRY_FUNCTION"] = false
			end

			-- If Statements

			if (OP == "if") then
				INTERPRETATION_TYPES["IF_STATEMENT"] = true
				local CONDITION = AspExt.InterpretCondition(LINE)

				if (CONDITION == "SYNTAX_ERROR") then
					INTERPRETATION_TYPES["IF_STATEMENT"] = false
					local Error = AspExt.ConstructError(
						"A syntax error has been detected, involving a condition.",
						"if {condition} ",
						'Your statement should use the format: if {condition} [action] '
					)
					AspExt.RuntimeError(Error, RUNTIME, false) insert_error(ISSUE)
				end

				--> If Statement Action Processing During Arithmetic | 1: Call Registry Function, 2: Set Variable

				-- Initial Arithmetic
				local result = AspExt.ValidateEvaluation(CONDITION)
				if (result == "SYNTAX_ERROR") then INTERPRETATION_TYPES["IF_STATEMENT_ARITHMETIC"] = false return end
				if (result == false) then return end
				if (result == true) then INTERPRETATION_TYPES["IF_STATEMENT_ARITHMETIC"] = true end

				-- #1 - Call Registry Function
				local ACTION = AspExt.InterpretAction(LINE)
				local STATUS_IF_CALL, IF_ISSUE = AspExt.CallFunctionInRegistry(ACTION, RUNTIME)
				if (STATUS_IF_CALL == "IN_REGISTRY") then return end
				if (STATUS_IF_CALL == "RUNTIME_ERROR") then AspExt.RuntimeError(IF_ISSUE, RUNTIME, false) insert_error(ISSUE) return end
				if (STATUS_IF_CALL == "INVALID_FUNCTION") then INTERPRETATION_TYPES["REGISTRY_FUNCTION"] = false end

				-- #2 - Set Variable
				local VARIABLE_NAME, DATA = AspExt.InterpretVariable(ACTION)
				if (VARIABLE_NAME ~= nil) and (DATA ~= nil) then RUNTIME.VARIABLES[VARIABLE_NAME] = DATA return end
				if (VARIABLE_NAME == "SYNTAX_ERROR") then INTERPRETATION_TYPES["SET_VARIABLE"] = false end
			else
				-- print("Operation is not an if statement.")
				-- print("Received: " .. tostring(OP))
			end
		end)


	AspExt.ReturnErrors(RUNTIME.ERROR_LIST)
end

return Aspect
