# NAT超时时间检测工具

一个用Lua编写的工具，用于检测NAT（网络地址转换）设备的连接超时时间。支持TCP和UDP协议。

## 功能特点

- **双协议支持**：同时支持TCP和UDP协议检测
- **两阶段探测**：先指数级快速定位，再线性精细测量
- **可配置参数**：可指定起始间隔、最大间隔等
- **彩色日志**：清晰的彩色日志输出，便于观察
- **简单易用**：只需Lua和luasocket库

## 工作原理

1. **第一阶段（快速定位）**：
   - 指数级增加探测间隔（1s → 2s → 4s → 8s ...）
   - 快速找到NAT超时的大致范围

2. **第二阶段（精细测量）**：
   - 在找到的范围内线性搜索（如4s → 5s → 6s → 7s）
   - 精确测量NAT超时时间

3. **客户端**连接到服务器
4. **服务器**定期发送探测包
5. 当连接断开时，记录精确的超时时间

## 安装依赖

```bash
# Ubuntu/Debian
sudo apt-get install lua-socket

# 或使用LuaRocks
luarocks install luasocket
```

## 使用方法

### 1. 服务器端

```bash
# 运行服务器
lua server.lua

# 选择协议
# 1. TCP (端口 12345)
# 2. UDP (端口 12346)

# 指定起始间隔
lua server.lua --start 10  # 从10秒开始探测
```

### 2. 客户端

```bash
# 连接服务器（默认TCP）
lua client.lua

# 指定协议
lua client.lua --protocol udp

# 指定服务器地址
lua client.lua --host 192.168.1.100 --protocol tcp
```

## 命令行参数

### 服务器端
```
--port <number>     指定端口（TCP/UDP使用相同端口）
--start <seconds>   起始探测间隔（默认：1）
--max <seconds>     最大探测间隔（默认：300）
--fine-step <seconds> 精细探测步长（默认：1）
```

### 客户端
```
--host <address>    服务器地址（默认：127.0.0.1）
--port <number>     服务器端口（默认：12345）
--protocol <proto>  协议：tcp 或 udp（默认：tcp）
```

## 输出示例

```
26-02-22 10:30:15 [INFO] NAT超时时间检测服务器启动
26-02-22 10:30:15 [INFO] 使用两阶段探测策略
26-02-22 10:30:15 [INFO] 第一阶段：快速定位（指数级）
26-02-22 10:30:20 [INFO] TCP探测间隔: 1.0s, 状态: 连接正常
26-02-22 10:30:22 [INFO] TCP探测间隔: 2.0s, 状态: 连接正常
26-02-22 10:30:26 [INFO] TCP探测间隔: 4.0s, 状态: 连接正常
26-02-22 10:30:34 [INFO] TCP探测间隔: 8.0s, 状态: 连接丢失
26-02-22 10:30:34 [INFO] 找到大致范围: 4s - 8s
26-02-22 10:30:34 [INFO] 第二阶段：精细测量（线性）
26-02-22 10:30:39 [INFO] TCP探测间隔: 5.0s, 状态: 连接正常
26-02-22 10:30:45 [INFO] TCP探测间隔: 6.0s, 状态: 连接正常
26-02-22 10:30:52 [INFO] TCP探测间隔: 7.0s, 状态: 连接丢失
26-02-22 10:30:52 [INFO] 精确NAT超时时间: 6.0s - 7.0s
26-02-22 10:30:52 [INFO] 建议设置心跳间隔: 5.0s
```

## 配置说明

### 服务器配置 (server.lua)

```lua
local config = {
    tcp_port = 12345,      -- TCP端口
    udp_port = 12346,      -- UDP端口
    magic_string = "NAT_PROBE_v1",  -- 探测包标识
    initial_interval = 1,  -- 初始探测间隔(秒)
    max_interval = 300,    -- 最大探测间隔(秒)
    fine_step = 1,         -- 精细探测步长(秒)
    log_level = "INFO"     -- 日志级别
}
```

### 客户端配置 (client.lua)

```lua
local config = {
    server_host = "127.0.0.1",  -- 服务器地址
    tcp_port = 12345,
    udp_port = 12346,
    magic_string = "NAT_PROBE_v1",
    log_level = "INFO"
}
```

## 算法说明

### 两阶段探测算法
1. **阶段一（指数搜索）**：
   ```
   interval = start_interval
   while interval <= max_interval:
       发送探测包(interval)
       if 连接正常:
           interval = interval * 2
       else:
           lower_bound = interval / 2
           upper_bound = interval
           break
   ```

2. **阶段二（线性搜索）**：
   ```
   for interval = lower_bound to upper_bound step fine_step:
       发送探测包(interval)
       if 连接正常:
           继续
       else:
           return interval - fine_step  -- 最后一个成功的间隔
   ```

## 应用场景

1. **网络调试**：精确了解NAT设备的连接保持时间
2. **VPN配置**：设置合适的心跳间隔，避免频繁重连
3. **游戏服务器**：优化TCP/UDP连接策略，减少延迟
4. **IoT设备**：配置合理的重连机制，节省电量
5. **移动网络**：测试蜂窝网络的NAT超时特性

## 注意事项

1. 需要在有NAT的设备后运行客户端
2. 服务器需要公网IP或端口转发
3. 不同网络环境结果可能不同
4. 建议多次测试取平均值
5. 实际使用时建议设置比测得值稍小的心跳间隔

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request！

## 作者

Lunia (with ❤️ from 月饼)