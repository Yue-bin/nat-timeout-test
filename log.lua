-- 日志

local log = {}

local level_colors = {
    DEBUG = "\27[36m", -- 青色
    INFO = "\27[37m",  -- 白色
    WARN = "\27[33m",  -- 黄色
    ERROR = "\27[31m", -- 红色
    RESET = "\27[0m"
}

local function log_msg(level, msg)
    local ts = os.date("%y-%m-%d %H:%M:%S")
    local color = level_colors[level] or level_colors.INFO
    print(string.format("%s%s [%s] %s%s", color, ts, level, msg, level_colors.RESET))
end

--- @param msg string
function log.info(msg)
    log_msg("INFO", msg)
end

--- @param msg string
function log.debug(msg)
    log_msg("DEBUG", msg)
end

--- @param msg string
function log.warn(msg)
    log_msg("WARN", msg)
end

--- @param msg string
function log.error(msg)
    log_msg("ERROR", msg)
end

return log
