local utils = {}

local constant = require("constant")

--- 使用分隔符切割字符串并返回一个数组
--- @param str string 输入字符串
--- @return table str_content 切割出的数组
function utils.split(str)
    local str_content = {}
    for field in str:gmatch("[^" .. constant.split_char .. "]+") do
        table.insert(str_content, field)
    end
    return str_content
end

return utils
