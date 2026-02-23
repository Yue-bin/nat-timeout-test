local log = require("log")

--- @enum protocol
local protocols = {
    "tcp",
    "udp"
}

--- @class srv 一个(host, port)元组
--- @field host string 主机
--- @field port integer 端口

--- 兜底函数
--- @param funcname string
--- @return function
local function default(funcname)
    return function()
        log.error(funcname .. "not implented")
    end
end

--- @class transport
local transport_funcs = {
    send = default("send"),
    receive = default("receive"),
    close = default("close"),
    is_connected = false -- 为了有连接的协议准备，对于无连接协议恒真
}

--- 实例化新传输层
--- 指定远程则为客户端模式，不指定则为服务器模式
--- @param protocol protocol 协议
--- @param local_info? srv 本地要绑定到的host和port
--- @param remote_info? srv 远程要连接到的host和port
--- @return transport
local function new(protocol, local_info, remote_info)
    local proto = require("transport." .. protocol)
    return setmetatable(
        proto.new(local_info, remote_info),
        {
            __index = transport_funcs
        }
    )
end

return {
    new = new
}
