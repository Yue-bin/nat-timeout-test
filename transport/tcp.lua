local _M = {}

local socket = require("socket")
local log = require("log")

--- @param msg string 要发送的消息
--- @return boolean success
--- @return string? err
function _M:send(msg)
    log.debug("发送信息: " .. msg)
    local ok, err = self.tcp:send(msg)
    if ok == nil then
        log.error("发送信息" .. msg .. "失败，错误: " .. err)
        return false
    end
    return true
end

--- @return string msg
function _M:receive()
    local msg, err = self.tcp:receive()
    if msg then
        log.debug("收到信息: " .. msg)
        return msg
    end
    log.debug("接受信息失败: " .. err)
    return ""
end

function _M:close()
    self.tcp:close()
end

--- 用于初始化一个tcp server实例
--- @param bind_host string
--- @param bind_port integer
--- @return TCPSocketServer?
local function new_server(bind_host, bind_port)
    local tcp = socket.tcp()
    if tcp == nil then
        return nil
    end
    tcp:bind(bind_host, bind_port)
    tcp:listen(5)
    --- @cast tcp TCPSocketServer
    return tcp
end

--- 从tcp server阻塞等待一个连接
--- @param server TCPSocketServer
--- @return TCPSocketClient connect
local function get_connect(server)
    while true do
        log.info("等待TCP客户端连接...")
        local client, err = server:accept()

        if client then
            client:settimeout(0)
            local client_addr = client:getsockname()
            log.info("TCP客户端已连接: " .. tostring(client_addr))

            return client
        elseif err ~= "timeout" then
            log.error("接受连接失败: " .. tostring(err))
        end
    end
end

--- 新建tcp实例
--- @param local_info srv 本地要绑定到的host和port
--- @param remote_info srv 远程要连接到的host和port
--- @return transport?
local function new(local_info, remote_info)
    if remote_info then
        -- 客户端模式
        local remote_host = remote_info.host
        local remote_port = remote_info.port
        local local_host
        local local_port
        if local_info then
            local_host = local_info.host
            local_port = local_info.port
        end
        return setmetatable(
            {
                tcp = socket.connect(
                    remote_host,
                    remote_port,
                    local_host,
                    local_port
                )
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
    if server then
        return setmetatable(
            {
                tcp = get_connect(server)
            },
            {
                __index = _M
            }
        )
    end
    return nil
end

return {
    new = new
}
