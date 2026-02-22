#!/usr/bin/env lua
-- NAT超时时间检测 - 客户端
-- 支持TCP和UDP协议

local socket = require("socket")
local log = require("logging")

-- 配置
local config = {
    server_host = "127.0.0.1",  -- 服务器地址
    tcp_port = 12345,
    udp_port = 12346,
    magic_string = "NAT_PROBE_v1",
    log_level = "INFO"
}

-- 日志设置（与服务器端一致）
local level_colors = {
    DEBUG = "\27[36m",  -- 青色
    INFO = "\27[37m",   -- 白色
    WARN = "\27[33m",   -- 黄色
    ERROR = "\27[31m",  -- 红色
    RESET = "\27[0m"
}

local function log_msg(level, msg)
    local ts = os.date("%y-%m-%d %H:%M:%S")
    local color = level_colors[level] or level_colors.INFO
    print(string.format("%s%s [%s] %s%s", color, ts, level, msg, level_colors.RESET))
end

local function log_info(msg) log_msg("INFO", msg) end
local function log_debug(msg) log_msg("DEBUG", msg) end
local function log_warn(msg) log_msg("WARN", msg) end
local function log_error(msg) log_msg("ERROR", msg) end

-- TCP客户端
local function run_tcp_client()
    log_info("连接TCP服务器: " .. config.server_host .. ":" .. config.tcp_port)
    
    local client = socket.connect(config.server_host, config.tcp_port)
    if not client then
        log_error("连接TCP服务器失败")
        return false
    end
    
    client:settimeout(0)  -- 非阻塞
    log_info("TCP连接建立成功")
    
    local last_probe_time = 0
    local connected = true
    
    while connected do
        -- 接收数据
        local data, err = client:receive()
        if data then
            -- 检查是否是探测包
            if data:find(config.magic_string, 1, true) then
                last_probe_time = socket.gettime()
                local timestamp = data:match("|(.+)$") or "unknown"
                log_debug("收到服务器探测包，时间戳: " .. timestamp)
                
                -- 回应服务器
                local response = "PROBE_ACK|" .. socket.gettime()
                client:send(response .. "\n")
                log_debug("发送回应: " .. response)
            else
                log_debug("收到非探测数据: " .. data)
            end
        elseif err ~= "timeout" then
            log_error("接收数据错误: " .. tostring(err))
            connected = false
        end
        
        -- 检查是否超时（超过30秒没收到探测包）
        if last_probe_time > 0 and socket.gettime() - last_probe_time > 30 then
            log_warn("超过30秒未收到探测包，连接可能已断开")
            connected = false
        end
        
        socket.sleep(0.1)  -- 避免CPU占用过高
    end
    
    client:close()
    log_info("TCP客户端退出")
    return true
end

-- UDP客户端
local function run_udp_client()
    log_info("连接UDP服务器: " .. config.server_host .. ":" .. config.udp_port)
    
    local client = assert(socket.udp())
    assert(client:setpeername(config.server_host, config.udp_port))
    client:settimeout(0)  -- 非阻塞
    
    -- 先发送一个初始包让服务器知道我们的地址
    local init_msg = "UDP_CLIENT_INIT|" .. socket.gettime()
    client:send(init_msg)
    log_info("发送初始UDP包: " .. init_msg)
    
    local last_probe_time = 0
    local running = true
    
    while running do
        -- 接收数据
        local data, err = client:receive()
        if data then
            -- 检查是否是探测包
            if data:find(config.magic_string, 1, true) then
                last_probe_time = socket.gettime()
                local timestamp = data:match("|(.+)$") or "unknown"
                log_debug("收到服务器探测包，时间戳: " .. timestamp)
                
                -- 回应服务器
                local response = "UDP_PROBE_ACK|" .. socket.gettime()
                client:send(response)
                log_debug("发送UDP回应: " .. response)
            else
                log_debug("收到非探测数据: " .. data)
            end
        elseif err ~= "timeout" then
            log_error("接收UDP数据错误: " .. tostring(err))
        end
        
        -- 检查是否超时（超过60秒没收到探测包）
        if last_probe_time > 0 and socket.gettime() - last_probe_time > 60 then
            log_warn("超过60秒未收到探测包，UDP NAT映射可能已过期")
            running = false
        end
        
        socket.sleep(0.1)
    end
    
    log_info("UDP客户端退出")
    return true
end

-- 主函数
local function main()
    log_info("NAT超时时间检测客户端启动")
    log_info("服务器地址: " .. config.server_host)
    
    -- 读取命令行参数
    local args = {...}
    local protocol = args[1] or "tcp"
    local server_host = args[2] or config.server_host
    
    if server_host ~= config.server_host then
        config.server_host = server_host
        log_info("使用指定服务器地址: " .. server_host)
    end
    
    print("\n选择协议:")
    print("1. TCP (默认)")
    print("2. UDP")
    print("3. 退出")
    
    io.write("请输入选择 (1-3): ")
    local choice = io.read() or "1"
    
    if choice == "1" then
        log_info("使用TCP协议")
        run_tcp_client()
    elseif choice == "2" then
        log_info("使用UDP协议")
        run_udp_client()
    else
        log_info("退出")
    end
end

-- 运行
if pcall(require, "socket") then
    main()
else
    print("错误: 需要安装luasocket库")
    print("Ubuntu/Debian: sudo apt-get install lua-socket")
    print("或: luarocks install luasocket")
    
    print("\n使用示例:")
    print("服务器端: lua server.lua")
    print("客户端: lua client.lua [tcp|udp] [服务器地址]")
    print("示例: lua client.lua udp 192.168.1.100")
end