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
local function parse_args(args)
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

-- 第一阶段：指数级搜索
local function stage_one_exponential_search(client, protocol, client_info)
    log_info("第一阶段：快速定位（指数级搜索）")
    
    local current_interval = config.initial_interval
    local lower_bound = nil
    local upper_bound = nil
    
    while current_interval <= config.max_interval do
        -- 发送探测包
        local probe_msg = config.magic_string .. "|STAGE_ONE|" .. socket.gettime() .. "|" .. current_interval
        local sent = false
        
        if protocol == "tcp" then
            sent = client:send(probe_msg .. "\n")
        else -- udp
            sent = client:sendto(probe_msg, client_info.ip, client_info.port)
        end
        
        if sent then
            log_info(string.format("探测间隔: %.1fs, 状态: 发送成功", current_interval))
            
            -- 等待回应
            local response_received = false
            local start_time = socket.gettime()
            
            while socket.gettime() - start_time < 2 do
                if protocol == "tcp" then
                    local data, err = client:receive()
                    if data and data:find("PROBE_ACK") then
                        response_received = true
                        log_debug("收到客户端回应")
                        break
                    end
                else -- udp
                    response_received = true
                end
                socket.sleep(0.1)
            end
            
            if response_received then
                log_info(string.format("探测间隔: %.1fs, 状态: 连接正常", current_interval))
                lower_bound = current_interval
                current_interval = current_interval * 2
                socket.sleep(current_interval)
            else
                log_warn(string.format("探测间隔: %.1fs, 状态: 无回应", current_interval))
                upper_bound = current_interval
                break
            end
        else
            log_error("发送探测包失败")
            return nil, nil
        end
    end
    
    return lower_bound, upper_bound
end

-- 第二阶段：线性精细搜索
local function stage_two_linear_search(client, protocol, client_info, start_interval, end_interval)
    log_info("第二阶段：精细测量（线性搜索）")
    log_info(string.format("搜索范围: %.1fs - %.1fs, 步长: %.1fs", 
        start_interval, end_interval, config.fine_step))
    
    local best_interval = start_interval
    
    for interval = start_interval + config.fine_step, end_interval, config.fine_step do
        local probe_msg = config.magic_string .. "|STAGE_TWO|" .. socket.gettime() .. "|" .. interval
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
    
    return best_interval
end

-- 处理客户端连接（支持两阶段）
local function handle_client(client, protocol, client_info)
    log_info("开始处理客户端连接")
    
    -- 第一阶段：等待客户端发送阶段信息
    local stage = "stage_one"  -- 默认从第一阶段开始
    local last_successful_interval = nil
    
    -- 设置接收超时为10秒，给客户端更多时间发送握手信号
    client:settimeout(10)
    
    -- 接收客户端初始信息
    local data, err = client:receive()
    if data then
        log_debug("收到客户端初始信息: " .. data)
        
        -- 检查是否是第二阶段握手
        if data:find("FINE_PROBE_START") then
            stage = "stage_two"
            -- 解析上次成功的间隔
            local parts = {}
            for part in data:gmatch("[^|]+") do
                table.insert(parts, part)
            end
            if #parts >= 2 then
                last_successful_interval = tonumber(parts[2])
                log_info("客户端请求第二阶段探测，上次成功间隔: " .. tostring(last_successful_interval))
            end
        end
    else
        log_debug("未收到客户端初始信息: " .. tostring(err))
    end
    
    -- 重置为非阻塞
    client:settimeout(0)
    
    if stage == "stage_one" then
        log_info("开始第一阶段探测")
        local lower_bound, upper_bound = stage_one_exponential_search(client, protocol, client_info)
        
        if lower_bound and upper_bound then
            log_info(string.format("第一阶段完成，范围: %.1fs - %.1fs", lower_bound, upper_bound))
            log_info("等待客户端重新连接进行第二阶段...")
            
            -- 告诉客户端进入第二阶段
            local stage_end_msg = "STAGE_ONE_END|" .. lower_bound .. "|" .. upper_bound
            client:send(stage_end_msg .. "\n")
            log_info("发送第一阶段结束信号: " .. stage_end_msg)
            
            -- 关闭连接，等待客户端重新连接
            client:close()
            return lower_bound, upper_bound
        else
            log_error("第一阶段探测失败")
            client:close()
            return nil, nil
        end
        
    elseif stage == "stage_two" and last_successful_interval then
        log_info("开始第二阶段探测")
        
        -- 计算搜索范围
        local start_interval = last_successful_interval
        local end_interval = last_successful_interval * 2
        
        -- 立即确认客户端准备好
        client:send("STAGE_TWO_READY|" .. start_interval .. "|" .. end_interval .. "\n")
        log_info("发送第二阶段就绪信号")
        
        -- 等待客户端确认（如果有的话）
        socket.sleep(1)
        
        -- 执行第二阶段探测
        local best_interval = stage_two_linear_search(client, protocol, client_info, 
            start_interval, end_interval)
        
        if best_interval then
            log_info(string.format("精确NAT超时时间: %.1fs - %.1fs", 
                best_interval, best_interval + config.fine_step))
            log_info(string.format("建议设置心跳间隔: %.1fs", best_interval * 0.8))
            
            -- 发送最终结果
            local final_result = "FINAL_RESULT|" .. best_interval .. "|" .. (best_interval + config.fine_step)
            client:send(final_result .. "\n")
            log_info("发送最终结果: " .. final_result)
        end
        
        client:close()
        return best_interval, nil
    end
    
    client:close()
    return nil, nil
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
            
            -- 处理客户端（支持两阶段）
            handle_client(client, "tcp", {ip = "*", port = "*"})
            
            log_info("TCP连接处理完成，等待下一个客户端...")
        elseif err ~= "timeout" then
            log_error("接受连接失败: " .. tostring(err))
        end
    end
end

-- UDP服务器（简化版）
local function run_udp_server()
    log_info("启动UDP服务器，端口: " .. config.udp_port)
    
    local server = assert(socket.udp())
    assert(server:setsockname("*", config.udp_port))
    server:settimeout(0)
    
    log_info("UDP服务器运行中（简化实现）...")
    
    while true do
        local data, ip, port = server:receivefrom()
        if data then
            log_debug("收到UDP数据从 " .. ip .. ":" .. port .. ": " .. data)
        end
        socket.sleep(1)
    end
end

-- 主函数
local function main()
    parse_args(arg)
    
    log_info("NAT超时时间检测服务器启动")
    log_info("使用两阶段探测算法（支持断线重连）")
    log_info("TCP端口: " .. config.tcp_port .. ", UDP端口: " .. config.udp_port)
    log_info("初始探测间隔: " .. config.initial_interval .. "s")
    log_info("最大探测间隔: " .. config.max_interval .. "s")
    log_info("精细探测步长: " .. config.fine_step .. "s")
    
    print("\n选择协议:")
    print("1. TCP（推荐，支持完整两阶段）")
    print("2. UDP（简化实现）")
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