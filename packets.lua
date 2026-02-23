local _M = {}

local constant = require("constant")
local utils = require("utils")

--- @alias packet handshake_packet|probe_packet 包抽象

--- 解析包通用函数
--- @param packet_str string str格式的包
--- @return packet packet
function _M.parse(packet_str)
    return utils.split(packet_str)
end

--- 握手包
_M.handshake = {}

--- 构建握手包
--- @param packet handshake_packet 握手包
--- @return string packet_str str格式的包
function _M.handshake.build(packet)
    return (
        constant.probe.format_str
        :gsub("<session_id>", tostring(packet.id))
        :gsub("<timestamp>", tostring(packet.ts))
        :gsub("<action>", constant.stage_sign[packet.action])
    )
end

--- 探测包
_M.probe = {}

--- 构建探测包
--- @param packet probe_packet 探测包
--- @return string packet_str str格式的包
function _M.probe.build(packet)
    return (
        constant.probe.format_str
        :gsub("<session_id>", tostring(packet.id))
        :gsub("<timestamp>", tostring(packet.ts))
        :gsub("<stage_sign>", constant.stage_sign[packet.stage])
        :gsub("<interval>", tostring(packet.interval))
    )
end

return _M
