#!/usr/bin/env lua
-- NAT超时时间检测 - 客户端
-- 支持TCP和UDP协议，支持两阶段探测算法

local socket = require("socket")

-- 配置
local config = {
    server_host = "127.0.0.1",  -- 服务器地址
    bind_host = "0.0.0.0",      -- 绑定地址
    tcp_port = 12345,
    udp_port = 12346,
    magic_string = "NAT_PROBE_v1",
    log_level = "INFO"
}

-- 全局状态变量
local client_state = {
    stage = "stage_one",
    last_successful_interval = nil,
    probe_count = 0
}

-- 命令行参数解析
local function parse_args(args)
    local parsed = {
        protocol = "tcp",
        host = config.server_host,
        port = nil,
        bind = config.bind_host
    }
    
    for i = 1, #args do
        if args[i] == "--host" and args[i+1] then
            parsed.host = args[i+1]
            i = i + 1
        elseif args[i] == "--port" and args[i+1] then
            parsed.port = tonumber(args[i+1])
            i = i + 1
        elseif args[i] == "--protocol" and args[i+1] then
            parsed.protocol = args[i+1]:lower()
            i = i + 1
        elseif args[i] == "--bind" and args[i+1] then
            parsed.bind = args[i+1]
            i = i + 1
        elseif args[i] == "--help" or args[i] == "-h" then
            return {help = true}
        end
    end
    
    -- 设置端口
    if parsed.port then
        config.tcp_port = parsed.port
        config.udp_port = parsed.port
    end
    
    if parsed.host then
        config.server_host = parsed.host
    end
    
    if parsed.bind then
        config.bind_host = parsed.bind
    end
    
    parsed.protocol = parsed.protocol or "tcp"
    return parsed
end

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

-- 解析探测包
local function parse_probe_packet(data)
    local parts = {}
    for part in data:gmatch("[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 4 then
        return {
            magic = parts[1],
            stage = parts[2],
            timestamp = tonumber(parts[3]),
            interval = tonumber(parts[4])
        }
    end
    return nil
end

-- 处理第一阶段结束信号
local function handle_stage_one_end(data)
    local parts = {}
    for part in data:gmatch("[^|]+") do
        table.insert(parts, part)
    end
    
    if #parts >= 3 and parts[1] == "STAGE_ONE_END" then
        local lower_bound = tonumber(parts[2])
        local upper_bound = tonumber(parts[3])
        
        if lower_bound and upper_bound then
            log_info(string.format("第一阶段完成，范围: %.1fs - %.1fs", lower_bound, upper_bound))
            return lower_bound
        end
    end
    return nil
end

-- 连接TCP服务器
local function connect_tcp_server(host, port, bind_host)
    log_info("连接TCP服务器: " .. host .. ":" .. port)
    log_info("绑定地址: " .. bind_host)
    
    -- 创建TCP客户端
    local client = socket.tcp()
    if not client then
        log_error("创建TCP客户端失败")
        return nil
    end
    
    -- 绑定到指定地址（可选）
    if bind_host ~= "0.0.0.0" then
        local ok, err = client:bind(bind_host, 0)  -- 0表示系统分配端口
        if not ok then
            log_warn("绑定到 " .. bind_host .. " 失败: " .. tostring(err))
        else
            log_info("已绑定到: " .. bind_host)
        end
    end
    
    -- 连接服务器
    local ok, err = client:connect(host, port)
    if not ok then
        log_error("连接TCP服务器失败: " .. tostring(err))
        return nil
    end
    
    client:settimeout(0)  -- 非阻塞
    log_info("TCP连接建立成功")
    return client
end

-- TCP客户端（支持两阶段）
local function run_tcp_client()
    local host = config.server_host
    local port = config.tcp_port
    local bind_host = config.bind_host
    
    log_debug("当前状态: stage=" .. client_state.stage .. 
              ", last_interval=" .. tostring(client_state.last_successful_interval))
    
    while true do
        -- 连接服务器
        local client = connect_tcp_server(host, port, bind_host)
        if not client then
            log_error("无法连接服务器")
            return false
        end
        
        -- 根据阶段发送初始信息
        if client_state.stage == "stage_two" and client_state.last_successful_interval then
            local handshake = "FINE_PROBE_START|" .. client_state.last_successful_interval
            -- 立即发送握手信号，不要等待
            client:send(handshake .. "\n")
            log_info("发送第二阶段握手: " .. handshake)
            log_debug("握手信号已发送，等待服务器响应...")
        else
            log_info("等待服务器探测...")
        end
        
        local last_probe_time = 0
        local connected = true
        local should_reconnect = false  -- 标记是否需要重新连接
        local phase_completed = false   -- 标记当前阶段是否完成
        
        while connected and not phase_completed do
            -- 接收数据
            local data, err = client:receive()
            if data then
                -- 检查是否是探测包
                if data:find(config.magic_string, 1, true) then
                    local probe = parse_probe_packet(data)
                    if probe then
                        last_probe_time = socket.gettime()
                        client_state.probe_count = client_state.probe_count + 1
                        
                        log_info(string.format("收到第%d个探测包，阶段: %s, 间隔: %.1fs", 
                            client_state.probe_count, probe.stage, probe.interval))
                        
                        -- 回应服务器
                        local response = "PROBE_ACK|" .. socket.gettime() .. "|" .. client_state.probe_count
                        client:send(response .. "\n")
                        log_debug("发送回应: " .. response)
                    else
                        log_debug("收到探测包但解析失败: " .. data)
                    end
                -- 检查是否是第一阶段结束信号
                elseif data:find("STAGE_ONE_END", 1, true) then
                    log_info("收到第一阶段结束信号: " .. data)
                    client_state.last_successful_interval = handle_stage_one_end(data)
                    if client_state.last_successful_interval then
                        client_state.stage = "stage_two"
                        should_reconnect = true  -- 需要重新连接进行第二阶段
                        phase_completed = true   -- 当前阶段完成
                        log_info("准备重新连接进行第二阶段探测...")
                    end
                -- 检查是否是第二阶段就绪信号
                elseif data:find("STAGE_TWO_READY", 1, true) then
                    log_info("收到第二阶段就绪信号: " .. data)
                    local parts = {}
                    for part in data:gmatch("[^|]+") do
                        table.insert(parts, part)
                    end
                    if #parts >= 3 then
                        local start = tonumber(parts[2])
                        local end_interval = tonumber(parts[3])
                        if start and end_interval then
                            log_info(string.format("第二阶段探测范围: %.1fs - %.1fs", start, end_interval))
                        end
                    end
                -- 检查是否是最终结果
                elseif data:find("FINAL_RESULT", 1, true) then
                    log_info("收到最终结果: " .. data)
                    local parts = {}
                    for part in data:gmatch("[^|]+") do
                        table.insert(parts, part)
                    end
                    if #parts >= 3 then
                        local lower = tonumber(parts[2])
                        local upper = tonumber(parts[3])
                        if lower and upper then
                            log_info(string.format("精确NAT超时时间: %.1fs - %.1fs", lower, upper))
                            log_info(string.format("建议设置心跳间隔: %.1fs", lower * 0.8))
                        end
                    end
                    phase_completed = true  -- 整个探测完成
                else
                    log_debug("收到其他数据: " .. data)
                end
            elseif err ~= "timeout" then
                log_error("接收数据错误: " .. tostring(err))
                connected = false
            end
            
            -- 检查是否超时（超过30秒没收到探测包）
            if last_probe_time > 0 and socket.gettime() - last_probe_time > 30 then
                log_warn("超过30秒未收到探测包，连接可能已断开")
                log_info("总共收到 " .. client_state.probe_count .. " 个探测包")
                connected = false
            end
            
            socket.sleep(0.1)  -- 避免CPU占用过高
        end
        
        client:close()
        
        -- 检查是否需要退出或重新连接
        if phase_completed and client_state.stage == "stage_two" and not should_reconnect then
            -- 第二阶段真正完成，退出
            log_info("第二阶段探测完成")
            break
        elseif not connected then
            -- 连接断开，等待后重试
            log_info("连接断开，等待5秒后重试...")
            socket.sleep(5)
        elseif should_reconnect then
            -- 第一阶段完成，立即重新连接进行第二阶段
            log_info("立即重新连接进行第二阶段探测...")
            socket.sleep(1)  -- 短暂等待确保服务器准备好
        end
    end
    
    log_info("TCP客户端退出")
    return true
end

-- UDP客户端
local function run_udp_client()
    local host = config.server_host
    local port = config.udp_port
    local bind_host = config.bind_host
    
    log_info("连接UDP服务器: " .. host .. ":" .. port)
    log_info("绑定地址: " .. bind_host)
    
    local client = assert(socket.udp())
    
    -- 绑定到指定地址
    local ok, err = client:setsockname(bind_host, 0)  -- 0表示系统分配端口
    if not ok then
        log_error("绑定UDP套接字失败: " .. tostring(err))
        return false
    end
    
    log_info("UDP套接字绑定成功: " .. bind_host)
    
    -- 设置对端地址
    ok, err = client:setpeername(host, port)
    if not ok then
        log_error("设置UDP对端地址失败: " .. tostring(err))
        return false
    end
    
    client:settimeout(0)  -- 非阻塞
    
    -- 先发送一个初始包让服务器知道我们的地址
    local init_msg = "UDP_CLIENT_INIT|" .. socket.gettime()
    client:send(init_msg)
    log_info("发送初始UDP包: " .. init_msg)
    
    local last_probe_time = 0
    local running = true
    local probe_count = 0
    
    while running do
        -- 接收数据
        local data, err = client:receive()
        if data then
            -- 检查是否是探测包
            if data:find(config.magic_string, 1, true) then
                last_probe_time = socket.gettime()
                probe_count = probe_count + 1
                
                -- 解析探测包信息
                local parts = {}
                for part in data:gmatch("[^|]+") do
                    table.insert(parts, part)
                end
                
                if #parts >= 4 then
                    local probe_interval = tonumber(parts[4]) or 0
                    log_info(string.format("收到第%d个UDP探测包，间隔: %.1fs", probe_count, probe_interval))
                else
                    log_debug("收到UDP探测包: " .. data)
                end
                
                -- 回应服务器
                local response = "UDP_PROBE_ACK|" .. socket.gettime() .. "|" .. probe_count
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
            log_info("总共收到 " .. probe_count .. " 个探测包")
            running = false
        end
        
        socket.sleep(0.1)
    end
    
    log_info("UDP客户端退出")
    return true
end

-- 显示帮助信息
local function show_help()
    print("NAT超时时间检测客户端")
    print("用法: lua client.lua [选项]")
    print()
    print("选项:")
    print("  --host <地址>     服务器地址（默认: 127.0.0.1）")
    print("  --port <端口>     服务器端口（默认: 12345）")
    print("  --protocol <协议> 协议: tcp 或 udp（默认: tcp）")
    print("  --bind <地址>     绑定地址（默认: 0.0.0.0）")
    print("  --help, -h        显示此帮助信息")
    print()
    print("示例:")
    print("  lua client.lua --host 192.168.1.100 --protocol tcp")
    print("  lua client.lua --host example.com --port 54321 --protocol udp")
    print("  lua client.lua --host server.com --bind 192.168.1.50 --protocol tcp")
end

-- 主函数
local function main()
    local args = parse_args(arg)
    
    -- 检查是否需要显示帮助
    if args.help then
        show_help()
        return
    end
    
    log_info("NAT超时时间检测客户端启动")
    log_info("服务器地址: " .. config.server_host)
    log_info("绑定地址: " .. config.bind_host)
    
    if args.protocol == "tcp" then
        log_info("使用TCP协议，端口: " .. config.tcp_port)
        run_tcp_client()
    elseif args.protocol == "udp" then
        log_info("使用UDP协议，端口: " .. config.udp_port)
        run_udp_client()
    else
        log_error("不支持的协议: " .. tostring(args.protocol))
        print("支持的协议: tcp, udp")
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
    print("lua client.lua --host 192.168.1.100 --protocol tcp")
    print("lua client.lua --host example.com --port 54321 --protocol udp")
    print("lua client.lua --host server.com --bind 192.168.1.50 --protocol tcp")
end
