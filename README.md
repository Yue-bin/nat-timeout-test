# NAT超时时间检测工具

一个用Lua编写的工具，用于检测NAT（网络地址转换）设备的连接超时时间。支持TCP和UDP协议。

## 功能特点

- **双协议支持**：同时支持TCP和UDP协议检测
- **渐进式探测**：逐渐增加探测间隔，直到连接断开
- **彩色日志**：清晰的彩色日志输出，便于观察
- **简单易用**：只需Lua和luasocket库

## 工作原理

1. **客户端**连接到服务器
2. **服务器**定期发送探测包
3. 探测间隔逐渐增加（1s → 2s → 4s → 8s ...）
4. 当连接断开时，记录当前的探测间隔
5. NAT超时时间 ≈ 最后成功的探测间隔

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
```

### 2. 客户端

```bash
# 连接服务器（默认TCP）
lua client.lua

# 指定协议
lua client.lua tcp
lua client.lua udp

# 指定服务器地址
lua client.lua tcp 192.168.1.100
lua client.lua udp example.com
```

## 输出示例

```
26-02-22 10:30:15 [INFO] NAT超时时间检测服务器启动
26-02-22 10:30:15 [INFO] TCP端口: 12345, UDP端口: 12346
26-02-22 10:30:15 [INFO] 初始探测间隔: 1s
26-02-22 10:30:15 [INFO] 最大探测间隔: 300s
26-02-22 10:30:20 [INFO] TCP探测间隔: 1.0s, 状态: 连接正常
26-02-22 10:30:22 [INFO] TCP探测间隔: 2.0s, 状态: 连接正常
26-02-22 10:30:26 [INFO] TCP探测间隔: 4.0s, 状态: 连接正常
26-02-22 10:30:34 [INFO] TCP探测间隔: 8.0s, 状态: 连接丢失
26-02-22 10:30:34 [WARN] TCP连接超时，估计NAT超时时间: ~4s
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

## 应用场景

1. **网络调试**：了解NAT设备的连接保持时间
2. **VPN配置**：设置合适的心跳间隔
3. **游戏服务器**：优化TCP/UDP连接策略
4. **IoT设备**：配置合理的重连机制

## 注意事项

1. 需要在有NAT的设备后运行客户端
2. 服务器需要公网IP或端口转发
3. 不同网络环境结果可能不同
4. 建议多次测试取平均值

## 许可证

MIT License

## 贡献

欢迎提交Issue和Pull Request！

## 作者

[Yue-bin](https://github.com/Yue-bin)