#!/usr/bin/env lua
-- NAT超时时间检测 - 客户端
-- 支持TCP和UDP协议

local socket = require("socket")

-- 配置
local config = {
    server_host = "127.0.0.1",  -- 服务器地址
    tcp_port = 12345,
    udp_port = 12346,
    magic_string = "NAT_PROBE_v1",
    log_level = "INFO"
}

-- 命令行参数解析
local function parse_args()
    local args = {...}
    local parsed = {
        protocol = "tcp",
        host = config.server_host,
        port = nil
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

-- TCP客户端
local function run_tcp_client()
    local host = config.server_host
    local port = config.tcp_port
    
    log_info("连接TCP服务器: " .. host .. ":" .. port)
    
    local client = socket.connect(host, port)
    if not client then
        log_error("连接TCP服务器失败")
        return false
    end
    
    client:settimeout(0)  -- 非阻塞
    log_info("TCP连接建立成功")
    log_info("等待服务器探测...")
    
    local last_probe_time = 0
    local connected = true
    local probe_count = 0
    
    while connected do
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
                
                if #parts >= 3 then
                    local probe_interval = tonumber(parts[3]) or 0
                    log_info(string.format("收到第%d个探测包，间隔: %.1fs", probe_count, probe_interval))
                else
                    log_debug("收到探测包: " .. data)
                end
                
                -- 回应服务器
                local response = "PROBE_ACK|" .. socket.gettime() .. "|" .. probe_count
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
            log_info("总共收到 " .. probe_count .. " 个探测包")
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
    local host = config.server_host
    local port = config.udp_port
    
    log_info("连接UDP服务器: " .. host .. ":" .. port)
    
    local client = assert(socket.udp())
    assert(client:setpeername(host, port))
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
                
                if #parts >= 3 then
                    local probe_interval = tonumber(parts[3]) or 0
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
            log_info("总共收到 " .. probe_count .. " 个UDP探测包")
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
    print("  --help            显示此帮助信息")
    print()
    print("示例:")
    print("  lua client.lua --host 192.168.1.100 --protocol tcp")
    print("  lua client.lua --host example.com --port 54321 --protocol udp")
end

-- 主函数
local function main()
    local args = parse_args()
    
    -- 检查是否需要显示帮助
    for _, arg in ipairs({...}) do
        if arg == "--help" or arg == "-h" then
            show_help()
            return
        end
    end
    
    log_info("NAT超时时间检测客户端启动")
    log_info("服务器地址: " .. config.server_host)
    
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
end