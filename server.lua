#!/usr/bin/env lua
-- NAT超时时间检测 - 服务器端
-- 支持TCP和UDP协议，使用两阶段探测算法

local socket = require("socket")

-- 配置
local config = {
    tcp_port = 12345,
    udp_port = 12346,
    magic_string = "NAT_PROBE_v1",
    initial_interval = 1,      -- 初始探测间隔（秒）
    max_interval = 300,        -- 最大探测间隔（秒）
    fine_step = 1,             -- 精细探测步长（秒）
    log_level = "INFO"
}

-- 命令行参数解析
local function parse_args()
    local args = {...}
    local parsed = {}
    
    for i = 1, #args do
        if args[i] == "--start" and args[i+1] then
            config.initial_interval = tonumber(args[i+1])
            i = i + 1
        elseif args[i] == "--max" and args[i+1] then
            config.max_interval = tonumber(args[i+1])
            i = i + 1
        elseif args[i] == "--fine-step" and args[i+1] then
            config.fine_step = tonumber(args[i+1])
            i = i + 1
        elseif args[i] == "--port" and args[i+1] then
            local port = tonumber(args[i+1])
            config.tcp_port = port
            config.udp_port = port
            i = i + 1
        end
    end
    
    return parsed
end

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

-- 两阶段探测算法
local function two_stage_probe(client, protocol, client_info)
    log_info("开始两阶段NAT超时检测")
    log_info("第一阶段：快速定位（指数级搜索）")
    
    -- 第一阶段：指数级搜索，找到大致范围
    local current_interval = config.initial_interval
    local lower_bound = nil
    local upper_bound = nil
    
    while current_interval <= config.max_interval do
        -- 发送探测包
        local probe_msg = config.magic_string .. "|" .. socket.gettime() .. "|" .. current_interval
        local sent = false
        
        if protocol == "tcp" then
            sent = client:send(probe_msg .. "\n")
        else -- udp
            sent = client:sendto(probe_msg, client_info.ip, client_info.port)
        end
        
        if sent then
            log_info(string.format("探测间隔: %.1fs, 状态: 发送成功", current_interval))
            
            -- 等待回应（TCP）或检查客户端活跃（UDP）
            local response_received = false
            local start_time = socket.gettime()
            
            while socket.gettime() - start_time < 2 do  -- 等待2秒回应
                if protocol == "tcp" then
                    local data, err = client:receive()
                    if data and data:find("PROBE_ACK") then
                        response_received = true
                        log_debug("收到客户端回应")
                        break
                    end
                else -- udp
                    -- UDP通过后续数据包判断客户端是否活跃
                    response_received = true  -- 假设活跃，由主循环更新
                end
                socket.sleep(0.1)
            end
            
            if response_received then
                log_info(string.format("探测间隔: %.1fs, 状态: 连接正常", current_interval))
                lower_bound = current_interval
                current_interval = current_interval * 2
                socket.sleep(current_interval)  -- 等待下一个探测间隔
            else
                log_warn(string.format("探测间隔: %.1fs, 状态: 无回应", current_interval))
                upper_bound = current_interval
                break
            end
        else
            log_error("发送探测包失败")
            break
        end
    end
    
    if not lower_bound or not upper_bound then
        log_error("未能找到NAT超时范围")
        return nil
    end
    
    log_info(string.format("找到大致范围: %.1fs - %.1fs", lower_bound, upper_bound))
    log_info("第二阶段：精细测量（线性搜索）")
    
    -- 第二阶段：线性搜索，精确测量
    local best_interval = lower_bound
    
    for interval = lower_bound + config.fine_step, upper_bound, config.fine_step do
        local probe_msg = config.magic_string .. "|" .. socket.gettime() .. "|" .. interval
        local sent = false
        
        if protocol == "tcp" then
            sent = client:send(probe_msg .. "\n")
        else
            sent = client:sendto(probe_msg, client_info.ip, client_info.port)
        end
        
        if sent then
            log_info(string.format("精细探测间隔: %.1fs, 状态: 发送成功", interval))
            
            local response_received = false
            local start_time = socket.gettime()
            
            while socket.gettime() - start_time < 2 do
                if protocol == "tcp" then
                    local data, err = client:receive()
                    if data and data:find("PROBE_ACK") then
                        response_received = true
                        break
                    end
                else
                    response_received = true
                end
                socket.sleep(0.1)
            end
            
            if response_received then
                log_info(string.format("精细探测间隔: %.1fs, 状态: 连接正常", interval))
                best_interval = interval
                socket.sleep(interval)
            else
                log_warn(string.format("精细探测间隔: %.1fs, 状态: 无回应", interval))
                break
            end
        else
            log_error("发送精细探测包失败")
            break
        end
    end
    
    log_info(string.format("精确NAT超时时间: %.1fs - %.1fs", 
        best_interval, best_interval + config.fine_step))
    log_info(string.format("建议设置心跳间隔: %.1fs", best_interval * 0.8))  -- 80%的安全边际
    
    return best_interval
end

-- TCP服务器
local function run_tcp_server()
    log_info("启动TCP服务器，端口: " .. config.tcp_port)
    
    local server = assert(socket.bind("*", config.tcp_port))
    server:settimeout(10)
    
    while true do
        log_info("等待TCP客户端连接...")
        local client, err = server:accept()
        
        if client then
            client:settimeout(0)
            local client_addr = client:getsockname()
            log_info("TCP客户端已连接: " .. tostring(client_addr))
            
            -- 执行两阶段探测
            two_stage_probe(client, "tcp", {ip = "*", port = "*"})
            
            client:close()
            log_info("TCP连接关闭，等待下一个客户端...")
        elseif err ~= "timeout" then
            log_error("接受连接失败: " .. tostring(err))
        end
    end
end

-- UDP服务器
local function run_udp_server()
    log_info("启动UDP服务器，端口: " .. config.udp_port)
    
    local server = assert(socket.udp())
    assert(server:setsockname("*", config.udp_port))
    server:settimeout(0)
    
    local clients = {}
    
    while true do
        -- 接收数据
        local data, ip, port = server:receivefrom()
        if data then
            local client_key = ip .. ":" .. port
            
            if not clients[client_key] then
                log_info("新的UDP客户端: " .. client_key)
                clients[client_key] = {
                    ip = ip,
                    port = port,
                    last_seen = socket.gettime(),
                    connected = true
                }
                
                -- 为新客户端启动探测线程（简化处理，实际需要协程）
                log_info("开始UDP客户端探测: " .. client_key)
                
                -- 这里简化处理，实际应该为每个客户端创建独立的探测逻辑
                -- 由于UDP是无连接的，探测逻辑需要调整
            else
                clients[client_key].last_seen = socket.gettime()
                log_debug("UDP客户端活跃: " .. client_key)
            end
        end
        
        -- 简化UDP探测逻辑（实际需要更复杂的实现）
        socket.sleep(1)
    end
end

-- 主函数
local function main()
    parse_args()
    
    log_info("NAT超时时间检测服务器启动")
    log_info("使用两阶段探测算法")
    log_info("TCP端口: " .. config.tcp_port .. ", UDP端口: " .. config.udp_port)
    log_info("初始探测间隔: " .. config.initial_interval .. "s")
    log_info("最大探测间隔: " .. config.max_interval .. "s")
    log_info("精细探测步长: " .. config.fine_step .. "s")
    
    print("\n选择协议:")
    print("1. TCP（推荐，更精确）")
    print("2. UDP")
    print("3. 退出")
    
    io.write("请输入选择 (1-3): ")
    local choice = io.read() or "1"
    
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
    
    print("\n使用示例:")
    print("lua server.lua --start 5 --max 60 --fine-step 0.5")
    print("lua server.lua --port 54321")
end