local socket = require("socket")

local str_map = {
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
}

local function gen_id()
    local id = {}
    math.randomseed(socket.gettime())
    for i = 1, 6 do
        table.insert(id, str_map[math.random(36)])
    end
    return table.concat(id)
end

--- @return table id_instance
local function new()
    local id = gen_id()
    return {
        --- 获取当前id
        --- @return string id
        get = function()
            return id
        end
    }
end

return {
    new = new
}
