local _M = {}

local socket = require("socket")
local log = require("log")

--- 连接
--- @param msg string 要发送的消息
--- @return boolean success
function _M:send(msg)
    log.debug("发送信息: " .. msg)
    local ok, err = self.udp:send(msg)
    if ok == nil then
        log.error("发送信息" .. msg .. "失败，错误: " .. err)
        return false
    end
    return true
end

--- @return string msg
function _M:receive()
    local msg, err = self.udp:receive()
    if msg then
        log.debug("收到信息: " .. msg)
        return msg
    end
    log.debug("接受信息失败: " .. err)
    return ""
end

function _M:close()
    self.udp:close()
end

--- 用于包裹会返回错误的调用
--- @param success any
--- @param err? string
--- @return any success
local function err_with_log(success, err)
    if not success then
        log.error("udp内部错误: " .. err)
        os.exit(1)
    end
    return success
end

--- 用于初始化一个udp server实例
--- @param bind_host string
--- @param bind_port integer
--- @return UDPSocketUnconnected
local function new_server(bind_host, bind_port)
    local udp = err_with_log(socket.udp())
    err_with_log(udp:setsockname(bind_host, bind_port))

    --- @cast udp UDPSocketUnconnected
    return udp
end

--- 新建udp客户端实例
--- @param remote_info srv
--- @param local_info? srv
--- @return UDPSocketConnected
local function new_client(remote_info, local_info)
    local udp = err_with_log(socket:udp())
    if local_info then
        err_with_log(udp:setsockname(local_info.host, local_info.port))
    end
    err_with_log(udp:setpeername(remote_info.host, remote_info.port))

    --- @cast udp UDPSocketConnected
    return udp
end

--- 新建udp实例
--- @param local_info srv 本地要绑定到的host和port
--- @param remote_info srv 远程要连接到的host和port
--- @return transport
local function new(local_info, remote_info)
    if remote_info then
        -- 客户端模式
        return setmetatable(
            {
                udp = new_client(remote_info, local_info)
            },
            {
                __index = _M
            }
        )
    end

    -- 服务器模式
    local local_host = local_info.host
    local local_port = local_info.port
    local server = new_server(local_host, local_port)
    return setmetatable(
        {
            udp = new_client(remote_info, local_info)
        },
        {
            __index = _M
        }
    )
end

return {
    new = new
}
