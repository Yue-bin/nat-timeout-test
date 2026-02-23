--- @return table stage_instance
local function new()
    local stage = 1
    return {
        --- 获取当前stage
        --- @return integer stage
        get = function()
            return stage
        end,

        --- 将stage转变至2
        turn = function()
            stage = 2
        end
    }
end

return {
    new = new
}
