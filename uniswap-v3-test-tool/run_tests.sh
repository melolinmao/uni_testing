#!/bin/bash

# 颜色设置
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== Uniswap V3测试工具 =====${NC}"

# 启动Anvil节点
function start_anvil() {
    echo -e "${YELLOW}尝试启动Anvil节点...${NC}"
    
    # 检查Anvil是否已在运行
    if curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 > /dev/null 2>&1; then
        echo -e "${GREEN}Anvil节点已经在运行中${NC}"
        return 0
    fi
    
    # 检查start_anvil.sh是否存在
    if [ -f "../start_anvil.sh" ]; then
        echo -e "${YELLOW}启动Anvil节点...${NC}"
        # 在后台运行
        bash ../start_anvil.sh &
        ANVIL_PID=$!
        
        # 等待节点启动
        echo -e "${YELLOW}等待Anvil节点启动...${NC}"
        for i in {1..5}; do
            sleep 2
            if curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 > /dev/null 2>&1; then
                echo -e "${GREEN}Anvil节点已成功启动${NC}"
                # 注册退出时清理
                trap 'echo -e "${YELLOW}清理Anvil进程...${NC}"; kill $ANVIL_PID; echo -e "${GREEN}已清理!${NC}"' EXIT
                return 0
            fi
            echo -e "${YELLOW}尝试 $i/5 ...${NC}"
        done
        echo -e "${RED}无法启动Anvil节点${NC}"
        kill $ANVIL_PID
        return 1
    else
        echo -e "${RED}错误: 找不到start_anvil.sh脚本${NC}"
        return 1
    fi
}

# 检查Anvil节点状态
function check_anvil() {
    echo -e "${YELLOW}检查Anvil节点状态...${NC}"
    if curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 > /dev/null 2>&1; then
        echo -e "${GREEN}Anvil节点正在运行，继续执行测试...${NC}"
        return 0
    else
        echo -e "${RED}警告: Anvil节点未启动${NC}"
        
        # 尝试启动节点
        read -p "是否要尝试启动Anvil节点? (y/n): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if start_anvil; then
                return 0
            else
                echo -e "${RED}无法继续执行测试，请先启动Anvil节点${NC}"
                return 1
            fi
        else
            echo -e "${RED}请手动启动Anvil节点后再尝试${NC}"
            echo -e "${YELLOW}命令: ./start_anvil.sh${NC}"
            return 1
        fi
    fi
}

# 确认Anvil节点可用
check_anvil || exit 1

# 设置测试目录和日志文件
TEST_DIR="tests"
LOG_DIR="logs"
mkdir -p $LOG_DIR

# 列出可用的测试
function list_tests() {
    echo -e "${YELLOW}可用的测试:${NC}"
    find $TEST_DIR -name "*.t.sol" | while read test; do
        echo "  - $(basename $test)"
    done
}

# 编译测试
function compile_tests() {
    echo -e "${YELLOW}编译测试合约...${NC}"
    forge build --silent
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}编译成功!${NC}"
        return 0
    else
        echo -e "${RED}编译失败!${NC}"
        return 1
    fi
}

# 执行特定测试
function run_specific_test() {
    local test_name=$1
    local verbosity=$2
    local log_file="${LOG_DIR}/${test_name%.t.sol}.log"
    
    echo -e "${YELLOW}运行测试: ${test_name}${NC}"
    
    if [ "$verbosity" = "verbose" ]; then
        forge test --match-path "*${test_name}" -vvv | tee $log_file
    else
        forge test --match-path "*${test_name}" | tee $log_file
    fi
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}测试通过!${NC}"
        return 0
    else
        echo -e "${RED}测试失败!${NC}"
        echo -e "${YELLOW}详细日志保存在: ${log_file}${NC}"
        return 1
    fi
}

# 执行所有测试
function run_all_tests() {
    echo -e "${YELLOW}运行所有测试...${NC}"
    local log_file="${LOG_DIR}/all_tests.log"
    
    forge test | tee $log_file
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "${GREEN}所有测试通过!${NC}"
        return 0
    else
        echo -e "${RED}测试执行失败${NC}"
        echo -e "${YELLOW}详细日志保存在: ${log_file}${NC}"
        return 1
    fi
}

# 显示帮助信息
function show_help() {
    echo -e "使用方法: $0 [选项] [测试名称]"
    echo -e ""
    echo -e "选项:"
    echo -e "  -h, --help      显示帮助信息"
    echo -e "  -l, --list      列出所有可用测试"
    echo -e "  -a, --all       运行所有测试"
    echo -e "  -v, --verbose   运行测试时显示详细输出"
    echo -e "  -c, --compile   仅编译测试"
    echo -e ""
    echo -e "示例:"
    echo -e "  $0 --all                   运行所有测试"
    echo -e "  $0 SwapTest.t.sol          运行单个测试"
    echo -e "  $0 -v SwapTest.t.sol       运行单个测试(详细输出)"
}

# 主函数
function main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    local verbose=false
    local compile_only=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_tests
                exit 0
                ;;
            -a|--all)
                compile_tests && run_all_tests
                exit $?
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -c|--compile)
                compile_only=true
                shift
                ;;
            *)
                if [ "$compile_only" = true ]; then
                    compile_tests
                    exit $?
                elif [ -f "${TEST_DIR}/$1" ]; then
                    compile_tests
                    if [ $? -eq 0 ]; then
                        if [ "$verbose" = true ]; then
                            run_specific_test "$1" "verbose"
                        else
                            run_specific_test "$1"
                        fi
                    fi
                    exit $?
                else
                    echo -e "${RED}错误: 测试文件 '${TEST_DIR}/$1' 不存在${NC}"
                    list_tests
                    exit 1
                fi
                ;;
        esac
    done
}

# 执行主函数
main "$@" 