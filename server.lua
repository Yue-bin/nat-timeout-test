#!/usr/bin/env lua
-- NAT超时时间检测 - 服务器端
-- 支持TCP和UDP协议

local socket = require("socket")
local log = require("logging")

-- 配置
local config = {
    tcp_port = 12345,
    udp_port = 12346,
    magic_string = "NAT_PROBE_v1",
    initial_interval = 1,  -- 初始探测间隔（秒）
    max_interval = 300,    -- 最大探测间隔（秒）
    log_level = "INFO"
}

-- 日志设置
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

-- TCP服务器
local function run_tcp_server()
    log_info("启动TCP服务器，端口: " .. config.tcp_port)
    
    local server = assert(socket.bind("*", config.tcp_port))
    server:settimeout(10)  -- 接受连接超时
    
    while true do
        log_info("等待TCP客户端连接...")
        local client, err = server:accept()
        
        if client then
            client:settimeout(0)  -- 非阻塞
            log_info("TCP客户端已连接: " .. tostring(client:getsockname()))
            
            local last_seen = socket.gettime()
            local probe_interval = config.initial_interval
            local connected = true
            
            while connected do
                -- 发送探测包
                local probe_msg = config.magic_string .. "|" .. socket.gettime()
                local sent, err = client:send(probe_msg .. "\n")
                
                if sent then
                    log_info(string.format("TCP探测间隔: %.1fs, 状态: 连接正常", probe_interval))
                    
                    -- 等待回应
                    local start_time = socket.gettime()
                    local response = nil
                    
                    while socket.gettime() - start_time < 1 do
                        response, err = client:receive()
                        if response then
                            last_seen = socket.gettime()
                            log_debug("收到客户端回应: " .. response)
                            break
                        end
                        socket.sleep(0.1)
                    end
                    
                    if not response then
                        log_warn("客户端未回应探测包")
                    end
                    
                    -- 增加探测间隔
                    probe_interval = probe_interval * 2
                    if probe_interval > config.max_interval then
                        probe_interval = config.max_interval
                    end
                    
                    socket.sleep(probe_interval)
                else
                    log_error("发送探测包失败: " .. tostring(err))
                    connected = false
                end
                
                -- 检查连接是否超时（超过3倍探测间隔无回应）
                if socket.gettime() - last_seen > probe_interval * 3 then
                    log_warn("TCP连接超时，估计NAT超时时间: ~" .. math.floor(probe_interval) .. "s")
                    connected = false
                end
            end
            
            client:close()
            log_info("TCP连接关闭")
        else
            if err ~= "timeout" then
                log_error("接受连接失败: " .. tostring(err))
            end
        end
    end
end

-- UDP服务器
local function run_udp_server()
    log_info("启动UDP服务器，端口: " .. config.udp_port)
    
    local server = assert(socket.udp())
    assert(server:setsockname("*", config.udp_port))
    server:settimeout(0)  -- 非阻塞
    
    local clients = {}  -- ip:port -> last_seen
    local probe_interval = config.initial_interval
    
    while true do
        -- 接收数据
        local data, ip, port = server:receivefrom()
        if data then
            local client_key = ip .. ":" .. port
            clients[client_key] = {
                ip = ip,
                port = port,
                last_seen = socket.gettime()
            }
            log_debug("收到UDP数据从 " .. client_key .. ": " .. data)
        end
        
        -- 发送探测包给所有客户端
        local current_time = socket.gettime()
        for client_key, client in pairs(clients) do
            if current_time - client.last_seen >= probe_interval then
                local probe_msg = config.magic_string .. "|" .. current_time
                local sent, err = server:sendto(probe_msg, client.ip, client.port)
                
                if sent then
                    log_info(string.format("UDP探测间隔: %.1fs, 客户端: %s, 状态: 活跃", 
                        probe_interval, client_key))
                else
                    log_error("发送UDP探测包失败: " .. tostring(err))
                end
                
                client.last_seen = current_time
            end
        end
        
        -- 清理超时客户端
        for client_key, client in pairs(clients) do
            if current_time - client.last_seen > probe_interval * 3 then
                log_warn("UDP客户端超时: " .. client_key .. ", 估计NAT超时时间: ~" .. math.floor(probe_interval) .. "s")
                clients[client_key] = nil
            end
        end
        
        -- 增加探测间隔
        probe_interval = probe_interval * 2
        if probe_interval > config.max_interval then
            probe_interval = config.max_interval
        end
        
        socket.sleep(1)  -- 主循环间隔
    end
end

-- 主函数
local function main()
    log_info("NAT超时时间检测服务器启动")
    log_info("TCP端口: " .. config.tcp_port .. ", UDP端口: " .. config.udp_port)
    log_info("初始探测间隔: " .. config.initial_interval .. "s")
    log_info("最大探测间隔: " .. config.max_interval .. "s")
    
    -- 启动TCP服务器线程（实际需要协程或并行）
    -- 这里简化处理，先运行TCP，UDP需要多线程支持
    print("\n选择协议:")
    print("1. TCP")
    print("2. UDP")
    print("3. 退出")
    
    io.write("请输入选择 (1-3): ")
    local choice = io.read()
    
    if choice == "1" then
        run_tcp_server()
    elseif choice == "2" then
        run_udp_server()
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
end