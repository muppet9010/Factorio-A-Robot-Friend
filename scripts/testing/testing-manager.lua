-- WHEN MAKING: This should be a copy of the railway tunnel testing framework, but maybe tidied up a bit. Is all just temporary at present. Also look to make it a Utility with the better Sumneko support?

local TestingManager = {} ---@class TestingManager

TestingManager.CreateGlobals = function()
    global.TestingManager = global.TestingManager or {} ---@class Global_TestingManager
end

TestingManager.OnLoad = function()
    MOD.Interfaces.Testing = MOD.Interfaces.Testing or {} ---@class MOD_InternalInterfaces_Testing
end

return TestingManager
