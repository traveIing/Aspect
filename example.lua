local Aspect = require("aspect_engine") -- This is up to your placement. The engine will need to be in a ModuleScript, or else it will not work.

-- // Custom Functions \\ --

local customFunctions = {
    ["Foo"] = {
        name = "Foo",
        main = function()
            print("Foo")
        end
    }
}

local registerState = Aspect.RegisterRuntimeFunctions(customFunctions, false)

if (registerState["distributions"] > 0) then
    print("Registered a function.")
end

-- // Using the Interpreter \\

local code = [[
declare foo1 as <Hello, world!>
declare foo2 as <Goodbye, world!>

print("@foo1") Comment Example
print("@foo2") Comment Example 2

Foo() Prints "Foo"
Test() Calls the Test function

if {5 == 5) [] Causes an Aspect Error to output
]]

Aspect.Interpret(code)
