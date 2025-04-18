#!/bin/bash

# 颜色定义
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

# 目录设置
SWARM_DIR="$HOME/rl-swarm"
HOME_DIR="$HOME"

# 监控日志目录
MONITOR_LOG_DIR="$HOME/.gensyn_monitor"
MONITOR_LOG_FILE="$MONITOR_LOG_DIR/monitor.log"
MONITOR_PID_FILE="$MONITOR_LOG_DIR/monitor.pid"

# 修改运行脚本以禁用Hugging Face提问
modify_run_script() {
    local script_path="$1/run_rl_swarm.sh"
    if [ -f "$script_path" ]; then
        echo -e "${YELLOW}[!] 正在修改 ${script_path} 以禁用Hugging Face提问...${NC}"
        # 使用临时文件以确保兼容性
        local tmp_file=$(mktemp)
        # 删除if/else/fi块并用单行替换
        sed '/if \[ -n "${HF_TOKEN}" \]; then/,/fi/c\
HUGGINGFACE_ACCESS_TOKEN="None"
' "$script_path" > "$tmp_file" && mv "$tmp_file" "$script_path"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}${BOLD}[✓] 脚本 ${script_path} 修改成功。${NC}"
        else
            echo -e "${RED}${BOLD}[✗] 修改 ${script_path} 时出错。${NC}"
            # 出错时删除临时文件
            rm -f "$tmp_file"
            return 1
        fi
    else
        echo -e "${RED}${BOLD}[✗] 未找到脚本 ${script_path}。${NC}"
        return 1
    fi
}

# 延迟启动监控
delayed_monitoring_start() {
    # 检查是否已经有延迟启动计划
    if pgrep -f "sleep.*enable_monitoring" >/dev/null; then
        return 0
    fi
    
    echo -e "${YELLOW}[!] 计划在10分钟后自动启动监控...${NC}"
    
    # 通过nohup在后台启动延迟监控
    nohup bash -c "sleep 600 && cd $(pwd) && source $(pwd)/gen.sh && if ! [ -f '$MONITOR_PID_FILE' ] || ! kill -0 \$(cat '$MONITOR_PID_FILE') 2>/dev/null; then enable_monitoring; fi" > /dev/null 2>&1 &
    
    echo -e "${GREEN}[✓] 监控将在10分钟后自动启动（如果尚未运行）。${NC}"
}

# 安装并运行节点
install_and_run() {
    echo -e "${BLUE}${BOLD}=== 安装依赖 ===${NC}"
    apt update && apt install -y sudo
    sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl wget screen git lsof nano unzip || { echo -e "${RED}${BOLD}[✗] 依赖安装失败。${NC}"; exit 1; }
    echo -e "${GREEN}${BOLD}[✓] 依赖安装完成。${NC}"

    echo -e "${BLUE}${BOLD}=== 运行安装脚本 ===${NC}"
    curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash || { echo -e "${RED}${BOLD}[✗] 执行第一个脚本 node.sh 失败。${NC}"; exit 1; }
    curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash || { echo -e "${RED}${BOLD}[✗] 执行第二个脚本 node.sh 失败。${NC}"; exit 1; }
    echo -e "${GREEN}${BOLD}[✓] 安装脚本执行完成。${NC}"

    echo -e "${BLUE}${BOLD}=== 准备仓库 ===${NC}"

    local use_existing_swarm="n"
    local existing_userData="n"
    local existing_userApi="n"

    # 检查$HOME目录下的swarm.pem
    if [ -f "$HOME_DIR/swarm.pem" ]; then
        echo -e "${BOLD}${YELLOW}发现文件 ${GREEN}$HOME_DIR/swarm.pem${YELLOW}。${NC}"
        read -p $'\e[1m是否用于此节点? (y/N): \e[0m' confirm_swarm
        if [[ "$confirm_swarm" =~ ^[Yy]$ ]]; then
            use_existing_swarm="y"
            echo -e "${GREEN}[✓] 将使用现有的swarm.pem。${NC}"
            # 检查相关文件
            if [ -f "$HOME_DIR/userData.json" ]; then
                echo -e "${YELLOW}[!] 发现文件 ${GREEN}$HOME_DIR/userData.json${YELLOW}。将被移动。${NC}"
                existing_userData="y"
            fi
             if [ -f "$HOME_DIR/userApiKey.json" ]; then
                echo -e "${YELLOW}[!] 发现文件 ${GREEN}$HOME_DIR/userApiKey.json${YELLOW}。将被移动。${NC}"
                existing_userApi="y"
            fi
        else
             echo -e "${YELLOW}[!] 现有的 $HOME_DIR/swarm.pem 将被忽略。${NC}"
        fi
    else
        echo -e "${YELLOW}[!] 未找到文件 $HOME_DIR/swarm.pem。首次运行时将生成新文件。${NC}"
    fi

    # 删除旧的rl-swarm目录并克隆新仓库
    echo -e "${BLUE}${BOLD}=== 克隆仓库 ===${NC}"
    cd "$HOME" || { echo -e "${RED}${BOLD}[✗] 无法进入目录 $HOME。${NC}"; exit 1; }

    if [ -d "$SWARM_DIR" ]; then
        echo -e "${YELLOW}[!] 发现已存在的目录 $SWARM_DIR。正在删除...${NC}"
        rm -rf "$SWARM_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}${BOLD}[✗] 无法删除目录 $SWARM_DIR。${NC}"
            exit 1
        fi
        echo -e "${GREEN}${BOLD}[✓] 已删除目录 $SWARM_DIR。${NC}"
    fi

    echo -e "${BOLD}${YELLOW}[✓] 正在从 https://github.com/node-trip/rl-swarm.git 克隆仓库...${NC}"
    git clone https://github.com/node-trip/rl-swarm.git "$SWARM_DIR"
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}[✗] 克隆仓库失败。${NC}"
        exit 1
    fi
    echo -e "${GREEN}${BOLD}[✓] 仓库已成功克隆到 $SWARM_DIR。${NC}"

    # 移动现有文件（如果用户同意）
    if [ "$use_existing_swarm" == "y" ]; then
        echo -e "${YELLOW}[!] 正在移动 $HOME_DIR/swarm.pem 到 $SWARM_DIR/...${NC}"
        mv "$HOME_DIR/swarm.pem" "$SWARM_DIR/swarm.pem" || { echo -e "${RED}[✗] 移动 swarm.pem 失败${NC}"; exit 1; }

        # 创建userData和userApi的目录
        mkdir -p "$SWARM_DIR/modal-login/temp-data"

        if [ "$existing_userData" == "y" ]; then
             echo -e "${YELLOW}[!] 正在移动 $HOME_DIR/userData.json...${NC}"
             mv "$HOME_DIR/userData.json" "$SWARM_DIR/modal-login/temp-data/" || echo -e "${RED}[!] 移动 userData.json 失败（可能已被删除）${NC}"
        fi
        if [ "$existing_userApi" == "y" ]; then
             echo -e "${YELLOW}[!] 正在移动 $HOME_DIR/userApiKey.json...${NC}"
             mv "$HOME_DIR/userApiKey.json" "$SWARM_DIR/modal-login/temp-data/" || echo -e "${RED}[!] 移动 userApiKey.json 失败（可能已被删除）${NC}"
        fi
         echo -e "${GREEN}${BOLD}[✓] 现有配置文件已移动。${NC}"
    fi

    # 修改run_rl_swarm.sh脚本
    modify_run_script "$SWARM_DIR" || exit 1

    # 添加执行权限
    echo -e "${YELLOW}[!] 正在为 run_rl_swarm.sh 添加执行权限...${NC}"
    chmod +x "$SWARM_DIR/run_rl_swarm.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}[✗] 无法为 run_rl_swarm.sh 添加执行权限。${NC}"
        exit 1
    fi
    echo -e "${GREEN}${BOLD}[✓] 执行权限已添加。${NC}"

    # 进入节点目录
    cd "$SWARM_DIR" || { echo -e "${BOLD}${RED}[✗] 无法进入目录 $SWARM_DIR。退出。${NC}"; exit 1; }

    # 配置并在screen中启动
    echo -e "${BLUE}${BOLD}=== 在screen中启动节点 ===${NC}"
    local run_script_cmd="
    if [ -n \\\"\$VIRTUAL_ENV\\\" ]; then
        echo -e '${BOLD}${YELLOW}[✓] 正在停用现有的虚拟环境...${NC}'
        deactivate
    fi
    echo -e '${BOLD}${YELLOW}[✓] 正在设置Python虚拟环境...${NC}'
    python3 -m venv .venv && source .venv/bin/activate || { echo -e '${RED}${BOLD}[✗] 虚拟环境设置失败。${NC}'; exit 1; }
    echo -e '${BOLD}${YELLOW}[✓] 正在启动rl-swarm...${NC}'
    ./run_rl_swarm.sh
    echo -e '${GREEN}${BOLD}rl-swarm脚本已完成。按Enter键退出screen。${NC}'
    read
    "

    # 创建并启动screen会话
    echo -e "${GREEN}${BOLD}[✓] 正在创建screen会话'gensyn'并启动节点...${NC}"
    screen -dmS gensyn bash -c "cd $SWARM_DIR && $run_script_cmd; exec bash"

    echo -e "${GREEN}${BOLD}[✓] 节点已在screen会话'gensyn'中启动。${NC}"
    echo -e "${YELLOW}要连接到此会话，请使用命令: ${NC}${BOLD}screen -r gensyn${NC}"
    echo -e "${YELLOW}要断开连接（保持节点运行），请按 ${NC}${BOLD}Ctrl+A，然后按 D${NC}"
    
    # 延迟启动监控
    delayed_monitoring_start
}

# 重启节点
restart_node() {
    echo -e "${BLUE}${BOLD}=== 重启节点 ===${NC}"

    # 检查screen会话是否存在
    if screen -list | grep -q "gensyn"; then
        echo -e "${YELLOW}[!] 正在停止当前screen会话'gensyn'中的节点...${NC}"
        # 向screen发送Ctrl+C
        screen -S gensyn -p 0 -X stuff $'\003'
        sleep 2 # 给Ctrl+C处理时间
        # 完全终止会话
        screen -S gensyn -X quit 2>/dev/null
    else
        echo -e "${YELLOW}[!] 未找到screen会话'gensyn'。${NC}"
    fi

    echo -e "${YELLOW}[!] 正在停止剩余进程...${NC}"
    pkill -f hivemind_exp.gsm8k.train_single_gpu
    pkill -f hivemind/hivemind_cli/p2pd
    pkill -f run_rl_swarm.sh
    sleep 2

    # 检查节点目录是否存在
    if [ ! -d "$SWARM_DIR" ]; then
        echo -e "${RED}${BOLD}[✗] 未找到目录 ${SWARM_DIR}。可能节点尚未安装？${NC}"
        return 1
    fi

    # 确保脚本已修改（Hugging Face）
    modify_run_script "$SWARM_DIR" || return 1

    # 添加执行权限（在modify_run_script之后很重要）
    echo -e "${YELLOW}[!] 正在为 run_rl_swarm.sh 添加执行权限...${NC}"
    chmod +x "$SWARM_DIR/run_rl_swarm.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}[✗] 无法为 run_rl_swarm.sh 添加执行权限。${NC}"
        return 1
    fi
    echo -e "${GREEN}${BOLD}[✓] 执行权限已添加。${NC}"

     # screen内部启动命令
     local restart_script_cmd="
     cd $SWARM_DIR || { echo -e '${RED}${BOLD}[✗] 无法进入目录 ${SWARM_DIR}。退出。'; exit 1; }
     echo -e '${BOLD}${YELLOW}[✓] 正在激活虚拟环境...${NC}'
     source .venv/bin/activate || { echo -e '${RED}${BOLD}[✗] 虚拟环境激活失败。${NC}'; exit 1; }
     echo -e '${BOLD}${YELLOW}[✓] 正在启动rl-swarm...${NC}'
     ./run_rl_swarm.sh
     echo -e '${GREEN}${BOLD}rl-swarm脚本已完成。按Enter键退出screen。${NC}'
     read
     "

    # 在screen中启动新节点
    echo -e "${GREEN}${BOLD}[✓] 正在screen会话'gensyn'中启动新节点...${NC}"
    screen -dmS gensyn bash -c "$restart_script_cmd; exec bash"

    echo -e "${GREEN}${BOLD}[✓] 节点已在screen会话'gensyn'中重启。${NC}"
    echo -e "${YELLOW}要连接到此会话，请使用命令: ${NC}${BOLD}screen -r gensyn${NC}"
    
    # 延迟启动监控
    delayed_monitoring_start
}

# 查看日志（连接到screen）
view_logs() {
    echo -e "${BLUE}${BOLD}=== 查看日志（连接到screen'gensyn'） ===${NC}"
    if screen -list | grep -q "gensyn"; then
        echo -e "${YELLOW}正在连接到screen'gensyn'... 按Ctrl+A，然后按D断开连接。${NC}"
        screen -r gensyn
    else
        echo -e "${RED}${BOLD}[✗] 未找到screen会话'gensyn'。无日志可查看。${NC}"
    fi
}

# 删除节点
delete_node() {
    echo -e "${BLUE}${BOLD}=== 删除节点 ===${NC}"
    read -p $'\e[1m\e[31m确定要删除节点及所有相关数据吗？ (y/N): \e[0m' confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] 正在停止screen会话'gensyn'...${NC}"
        screen -S gensyn -X quit 2>/dev/null

        echo -e "${YELLOW}[!] 正在停止剩余进程...${NC}"
        pkill -f hivemind_exp.gsm8k.train_single_gpu
        pkill -f hivemind/hivemind_cli/p2pd
        pkill -f run_rl_swarm.sh
        sleep 2

        echo -e "${YELLOW}[!] 正在删除目录 ${SWARM_DIR}...${NC}"
        rm -rf "$SWARM_DIR"

        echo -e "${GREEN}${BOLD}[✓] 节点已成功删除。${NC}"
    else
        echo -e "${YELLOW}删除操作已取消。${NC}"
    fi
}

# 启用监控
enable_monitoring() {
    # 检查监控是否已运行
    if [ -f "$MONITOR_PID_FILE" ] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
        echo -e "${YELLOW}监控已在运行 (PID: $(cat "$MONITOR_PID_FILE"))。${NC}"
        return 0
    fi
    
    # 创建日志目录（如果不存在）
    mkdir -p "$MONITOR_LOG_DIR"
    
    # 创建将通过nohup启动的监控脚本
    local monitor_script="$MONITOR_LOG_DIR/monitor_script.sh"
    cat > "$monitor_script" << 'EOF'
#!/bin/bash
MONITOR_LOG_FILE="$1"
SWARM_DIR="$2"

# 检查内存使用情况
check_memory_usage() {
    # 从free命令获取内存统计
    local mem_stats=$(free | grep Mem)
    local total_mem=$(echo $mem_stats | awk '{print $2}')
    local used_mem=$(echo $mem_stats | awk '{print $3}')
    local mem_usage_percent=$(( (used_mem * 100) / total_mem ))
    
    # 记录到日志
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] 内存使用率: $mem_usage_percent%" >> "$MONITOR_LOG_FILE"
    
    # 如果内存使用率低于20%，重启节点
    if [ $mem_usage_percent -lt 20 ]; then
        echo "[$timestamp] 警告: 内存使用率过低 ($mem_usage_percent%)。正在重启节点..." >> "$MONITOR_LOG_FILE"
        # 调用重启函数
        "$SWARM_DIR/../restart_gensyn_node.sh"
        echo "[$timestamp] 重启完成。" >> "$MONITOR_LOG_FILE"
    fi
}

# 检查screen日志中的错误
check_screen_logs() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # 检查screen会话是否存在
    if ! screen -list | grep -q "gensyn"; then
        echo "[$timestamp] 未找到screen会话'gensyn'。跳过日志检查。" >> "$MONITOR_LOG_FILE"
        return 0
    fi
    
    # 将screen内容保存到临时文件
    local tmp_log_file=$(mktemp)
    # 使用hardcopy获取screen内容
    screen -S gensyn -X hardcopy "$tmp_log_file"
    
    # 检查错误
    if grep -q -E "timed out|KeyError: 'question'|Killed|AttributeError: 'NoneType' object has no attribute 'split'" "$tmp_log_file"; then
        local error_type="unknown"
        if grep -q "timed out" "$tmp_log_file"; then
            error_type="timed out"
        elif grep -q "KeyError: 'question'" "$tmp_log_file"; then
            error_type="KeyError: 'question'"
        elif grep -q "Killed" "$tmp_log_file"; then
            error_type="Killed"
        elif grep -q "AttributeError: 'NoneType' object has no attribute 'split'" "$tmp_log_file"; then
            error_type="AttributeError: NoneType split"
        fi
        
        echo "[$timestamp] 警告: 在日志中发现错误 '$error_type'。正在重启节点..." >> "$MONITOR_LOG_FILE"
        # 删除临时文件
        rm -f "$tmp_log_file"
        # 调用重启函数
        "$SWARM_DIR/../restart_gensyn_node.sh"
        echo "[$timestamp] 由于错误 '$error_type' 重启完成。" >> "$MONITOR_LOG_FILE"
    else
        echo "[$timestamp] 未在日志中发现错误。" >> "$MONITOR_LOG_FILE"
        # 删除临时文件
        rm -f "$tmp_log_file"
    fi
}

# 主检查循环
while true; do
    check_memory_usage
    check_screen_logs
    sleep 1800 # 30分钟
done
EOF

    # 创建节点重启脚本
    local restart_script="$HOME/restart_gensyn_node.sh"
    cat > "$restart_script" << EOF
#!/bin/bash

# 重启节点函数
restart_node() {
    # 检查screen会话是否存在
    if screen -list | grep -q "gensyn"; then
        # 向screen发送Ctrl+C
        screen -S gensyn -p 0 -X stuff $'\003'
        sleep 2 # 给Ctrl+C处理时间
        # 完全终止会话
        screen -S gensyn -X quit 2>/dev/null
    fi

    # 停止剩余进程
    pkill -f hivemind_exp.gsm8k.train_single_gpu
    pkill -f hivemind/hivemind_cli/p2pd
    pkill -f run_rl_swarm.sh
    sleep 2

    # 检查节点目录是否存在
    if [ ! -d "$SWARM_DIR" ]; then
        exit 1
    fi

    # 添加执行权限
    chmod +x "$SWARM_DIR/run_rl_swarm.sh"

    # screen内部启动命令
    local restart_script_cmd="
    cd $SWARM_DIR || exit 1
    echo -e '正在激活虚拟环境...'
    source .venv/bin/activate || exit 1
    echo -e '正在启动rl-swarm...'
    ./run_rl_swarm.sh
    "

    # 在screen中启动新节点
    screen -dmS gensyn bash -c "\$restart_script_cmd; exec bash"
}

# 执行重启函数
restart_node
EOF

    # 使脚本可执行
    chmod +x "$monitor_script"
    chmod +x "$restart_script"

    # 通过nohup启动监控，使其在终端关闭后仍运行
    echo -e "${YELLOW}[!] 正在启动独立于终端的监控...${NC}"
    nohup "$monitor_script" "$MONITOR_LOG_FILE" "$SWARM_DIR" > "$MONITOR_LOG_DIR/nohup.out" 2>&1 &
    
    # 保存后台进程PID
    echo $! > "$MONITOR_PID_FILE"
    echo -e "${GREEN}${BOLD}[✓] 监控已启动 (PID: $(cat "$MONITOR_PID_FILE")) 并将在终端关闭后继续运行。${NC}"
    echo -e "${YELLOW}每30分钟将检查内存使用情况和错误。${NC}"
    echo -e "${YELLOW}节点将在以下情况下自动重启:${NC}"
    echo -e "${YELLOW} - 内存使用率低于20%${NC}"
    echo -e "${YELLOW} - 在日志中发现以下错误:${NC}"
    echo -e "${YELLOW}   * 'timed out'${NC}"
    echo -e "${YELLOW}   * 'KeyError: question'${NC}"
    echo -e "${YELLOW}   * 'Killed'${NC}"
    echo -e "${YELLOW}   * 'AttributeError: NoneType object has no attribute split'${NC}"
    echo -e "${YELLOW}日志保存在: ${MONITOR_LOG_FILE}${NC}"
}

# 禁用监控
disable_monitoring() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        local pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}[!] 正在停止监控 (PID: $pid)...${NC}"
            kill "$pid"
            rm -f "$MONITOR_PID_FILE"
            echo -e "${GREEN}${BOLD}[✓] 监控已停止。${NC}"
        else
            echo -e "${YELLOW}[!] 未找到监控进程 ($pid)。正在清理...${NC}"
            rm -f "$MONITOR_PID_FILE"
            echo -e "${GREEN}[✓] 监控数据已清理。${NC}"
        fi
    else
        echo -e "${YELLOW}[!] 监控未运行。${NC}"
    fi
}

# 查看监控历史
view_monitoring_history() {
    if [ ! -f "$MONITOR_LOG_FILE" ]; then
        echo -e "${YELLOW}[!] 未找到监控历史文件。${NC}"
        return 1
    fi
    
    echo -e "${BLUE}${BOLD}=== 监控历史 ===${NC}"
    echo -e "${YELLOW}文件 ${MONITOR_LOG_FILE} 内容:${NC}"
    echo ""
    
    # 使用tail显示最后100行日志
    tail -n 100 "$MONITOR_LOG_FILE"
    
    echo ""
    echo -e "${YELLOW}显示最后100条记录。${NC}"
}

# 显示监控子菜单
show_monitoring_menu() {
    while true; do
        echo -e "\n${BLUE}${BOLD}======= 监控子菜单 ========${NC}"
        echo -e "${GREEN}1)${NC} 启用监控"
        echo -e "${RED}2)${NC} 禁用监控"
        echo -e "${BLUE}3)${NC} 查看监控历史"
        echo -e "--------------------------------------------------"
        echo -e "${BOLD}0)${NC} 返回主菜单"
        echo -e "=================================================="
        
        # 显示监控状态
        if [ -f "$MONITOR_PID_FILE" ] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
            echo -e "${GREEN}监控状态: 运行中 (PID: $(cat "$MONITOR_PID_FILE"))${NC}"
        else
            echo -e "${RED}监控状态: 已停止${NC}"
        fi
        
        read -p $'\e[1m请输入子菜单选项: \e[0m' choice
        echo "" # 空行提高可读性
        
        case $choice in
            1)
                enable_monitoring
                ;;
            2)
                disable_monitoring
                ;;
            3)
                view_monitoring_history
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}${BOLD}[✗] 无效选择。请重试。${NC}"
                ;;
        esac
        
        # 显示子菜单前暂停
        echo -e "\n${YELLOW}按Enter键继续...${NC}"
        read -r
    done
}

# 显示主菜单
show_menu() {
    echo -e "\n${BLUE}${BOLD}========= Gensyn节点管理菜单 ==========${NC}"
    echo -e "${GREEN}1)${NC} 安装并运行节点"
    echo -e "${YELLOW}2)${NC} 重启节点"
    echo -e "${BLUE}3)${NC} 查看日志（连接到screen）"
    echo -e "${RED}4)${NC} 删除节点"
    echo -e "${GREEN}5)${NC} 节点监控"
    echo -e "--------------------------------------------------"
    echo -e "${BOLD}0)${NC} 退出"
    echo -e "=================================================="
}

# 主循环
while true; do
    show_menu
    read -p $'\e[1m请输入菜单选项: \e[0m' choice
    echo "" # 空行提高可读性

    case $choice in
        1)
            install_and_run
            ;;
        2)
            restart_node
            ;;
        3)
            view_logs
            ;;
        4)
            delete_node
            ;;
        5)
            show_monitoring_menu
            ;;
        0)
            # 退出时检查监控是否运行
            if [ -f "$MONITOR_PID_FILE" ] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
                echo -e "${YELLOW}[!] 监控将继续在后台运行。${NC}"
                echo -e "${YELLOW}    如需停止，请使用菜单选项'5 -> 2'。${NC}"
            fi
            echo -e "${GREEN}正在退出脚本。${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}${BOLD}[✗] 无效选择。请重试。${NC}"
            ;;
    esac

    # 如果不是退出选项，显示菜单前暂停
    if [ "$choice" != "0" ]; then
      echo -e "\n${YELLOW}按Enter键返回菜单...${NC}"
      read -r
    fi
done
