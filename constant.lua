-- 常量
local constant = {}

local log = require("log")

constant.split_char = "#"
constant.head = "nat_probe"
constant.stage_sign = setmetatable(
    { -- index by stage
        "s1",
        "s2"
    },
    { -- default
        __index = function(_, stage)
            log.error("unknown_stage" .. tostring(stage))
            return "unknown_stage"
        end
    }
)

--- handshake packet
--- @class handshake_packet
--- @field id string 会话id
--- @field action actions 动作
--- @field ts number 时间戳

constant.handshake = {}

--- @enum actions
constant.handshake.actions = {
    "syn",
    "ack",
    "turn" -- 转换到stage2的请求
}

constant.handshake.format_str = table.concat(
    {
        constant.head,
        "<session_id>",
        "<timestamp>",
        "<action>"
    },
    constant.split_char
)

--- probe packet
--- @class probe_packet
--- @field id string 会话id
--- @field ts number 时间戳
--- @field stage integer 探测阶段
--- @field interval number 当前检测间隔

constant.probe = {}

constant.probe.format_str = table.concat(
    {
        constant.head,
        "<session_id>",
        "<timestamp>",
        "<stage_sign>",
        "<interval>"
    },
    constant.split_char
)

return constant
