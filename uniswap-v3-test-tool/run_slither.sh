#!/bin/bash

# 颜色设置
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}===== Uniswap V3 Slither 静态分析工具 =====${NC}"

# Slither 完整路径
SLITHER_PATH="/Users/miaolinmao/Library/Python/3.9/bin/slither"

# 检查 Slither 是否可用
if [ ! -f "$SLITHER_PATH" ]; then
    echo -e "${RED}错误: Slither 未找到在路径 $SLITHER_PATH${NC}"
    echo -e "${YELLOW}请使用以下命令安装 Slither:${NC}"
    echo -e "pip3 install slither-analyzer"
    exit 1
fi

# 项目根目录和配置文件路径
CORE_SUITE_DIR=$(pwd)
PROJECT_ROOT="$(dirname "$CORE_SUITE_DIR")"
CONFIG_PATH="$CORE_SUITE_DIR/.slither.config.json"
echo -e "${YELLOW}项目根目录: $PROJECT_ROOT${NC}"
echo -e "${YELLOW}core_suite 目录: $CORE_SUITE_DIR${NC}"
echo -e "${YELLOW}配置文件路径: $CONFIG_PATH${NC}"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${RED}错误: 配置文件 $CONFIG_PATH 不存在${NC}"
    exit 1
else
    echo -e "${GREEN}配置文件已找到: $CONFIG_PATH${NC}"
    echo -e "${YELLOW}配置文件内容:${NC}"
    cat "$CONFIG_PATH"
fi

# 创建报告目录
mkdir -p reports/slither

# 运行 Slither 分析
echo -e "${YELLOW}运行 Slither 静态代码分析...${NC}"

# 处理命令行参数
if [ "$1" == "-c" ] || [ "$1" == "--core" ]; then
    # 只分析核心合约
    echo -e "${YELLOW}分析 Uniswap V3 核心合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/lib/v3-core/contracts"
elif [ "$1" == "-p" ] || [ "$1" == "--periphery" ]; then
    # 只分析外围合约
    echo -e "${YELLOW}分析 Uniswap V3 外围合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/lib/v3-periphery/contracts"
elif [ "$1" == "-o" ] || [ "$1" == "--our" ]; then
    # 分析我们自己的合约
    echo -e "${YELLOW}分析我们自己的核心合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/contracts"
elif [ "$1" == "-f" ] || [ "$1" == "--file" ]; then
    # 分析单个文件
    if [ -z "$2" ]; then
        echo -e "${RED}错误: 请提供要分析的文件路径${NC}"
        exit 1
    fi
    echo -e "${YELLOW}分析单个文件: $2${NC}"
    TARGETS="$2"
    SINGLE_FILE=true
elif [ "$1" == "-a" ] || [ "$1" == "--all" ]; then
    # 分析所有合约
    echo -e "${YELLOW}分析所有合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/contracts $CORE_SUITE_DIR/lib/v3-core/contracts $CORE_SUITE_DIR/lib/v3-periphery/contracts"
else
    # 默认分析我们自己的合约
    echo -e "${YELLOW}默认分析 UniswapV3Pool.sol 合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/lib/v3-core/contracts/UniswapV3Pool.sol"
    SINGLE_FILE=true
fi

# 检查目标是否存在
echo -e "${YELLOW}检查分析目标是否存在...${NC}"
if [ "$SINGLE_FILE" = true ]; then
    if [ ! -f "$TARGETS" ]; then
        echo -e "${RED}错误: 目标文件 $TARGETS 不存在${NC}"
        echo -e "${YELLOW}尝试搜索文件...${NC}"
        FOUND_FILES=$(find $CORE_SUITE_DIR -name "$(basename $TARGETS)" -type f)
        if [ -z "$FOUND_FILES" ]; then
            echo -e "${RED}未找到匹配的文件${NC}"
            exit 1
        else
            echo -e "${GREEN}找到了以下匹配文件:${NC}"
            echo "$FOUND_FILES"
            TARGETS=$(echo "$FOUND_FILES" | head -n 1)
            echo -e "${YELLOW}将使用第一个匹配文件: $TARGETS${NC}"
        fi
    else
        echo -e "${GREEN}目标文件存在: $TARGETS${NC}"
    fi
else
    for target in $TARGETS; do
        if [ ! -d "$target" ]; then
            echo -e "${RED}警告: 目标目录 $target 不存在，将尝试查找${NC}"
            BASE_DIR=$(basename "$target")
            FOUND_DIRS=$(find $CORE_SUITE_DIR -name "$BASE_DIR" -type d)
            if [ -z "$FOUND_DIRS" ]; then
                echo -e "${RED}未找到匹配的目录${NC}"
            else
                echo -e "${GREEN}找到了以下匹配目录:${NC}"
                echo "$FOUND_DIRS"
                # 更新目标路径
                for found in $FOUND_DIRS; do
                    if [[ "$found" == *"$BASE_DIR" ]]; then
                        TARGETS=${TARGETS/$target/$found}
                        echo -e "${YELLOW}已更新目标路径: $found${NC}"
                        break
                    fi
                done
            fi
        else
            echo -e "${GREEN}目标目录存在: $target${NC}"
            echo -e "${YELLOW}目录内容 (部分列表):${NC}"
            ls -la "$target" | head -n 5
        fi
    done
fi

# 运行 Slither 分析并生成报告
echo -e "${YELLOW}正在分析...${NC}"

# 显示调试信息
echo -e "${YELLOW}Slither路径: $SLITHER_PATH${NC}"
echo -e "${YELLOW}分析目标: $TARGETS${NC}"
echo -e "${YELLOW}配置文件: $CONFIG_PATH${NC}"

# 使用 --solc-solcs-select 参数来避免版本问题
echo -e "${YELLOW}运行命令: $SLITHER_PATH $TARGETS --config-file $CONFIG_PATH --solc-solcs-select 0.7.6${NC}"

# 生成文本报告，添加详细输出
$SLITHER_PATH $TARGETS --config-file "$CONFIG_PATH" --solc-solcs-select 0.7.6 --debug > reports/slither/report.txt 2>&1
RESULT=$?

if [ $RESULT -eq 0 ]; then
    echo -e "${GREEN}Slither 分析完成，报告已保存到 reports/slither/report.txt${NC}"
else
    echo -e "${RED}Slither 分析出现错误 (退出码: $RESULT)${NC}"
    echo -e "${YELLOW}请查看错误信息：${NC}"
    tail -n 20 reports/slither/report.txt
    
    # 根据错误类型提供更多信息
    if grep -q "solc not found" reports/slither/report.txt; then
        echo -e "${YELLOW}Solidity 编译器未找到，请安装 solc:${NC}"
        echo -e "pip3 install solc-select && solc-select install 0.7.6 && solc-select use 0.7.6"
    fi
    
    if grep -q "No contract was found" reports/slither/report.txt; then
        echo -e "${YELLOW}没有找到合约，请检查目标路径是否正确${NC}"
    fi
    
    echo -e "${YELLOW}完整错误日志已保存在: reports/slither/report.txt${NC}"
    exit 1
fi

# 生成 JSON 报告
$SLITHER_PATH $TARGETS --config-file "$CONFIG_PATH" --solc-solcs-select 0.7.6 --json reports/slither/report.json > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}JSON 格式报告已保存到 reports/slither/report.json${NC}"
fi

# 生成 Markdown 格式的摘要报告
echo -e "${YELLOW}生成 Markdown 摘要报告...${NC}"
{
    echo "# Slither 静态分析报告"
    echo ""
    echo "## 分析范围"
    echo ""
    echo "分析目标: \`$TARGETS\`"
    echo ""
    echo "分析时间: $(date)"
    echo ""
    
    # 提取检测到的问题
    echo "## 检测到的问题"
    echo ""
    
    # 尝试从报告中提取发现的漏洞
    ISSUES=$(grep -A 2 "detected:" reports/slither/report.txt | grep -v "Use" | grep -v "\-\-" || echo "未找到问题")
    
    if [ "$ISSUES" == "未找到问题" ]; then
        echo "未检测到任何问题，代码符合安全最佳实践。"
    else
        echo "以下是 Slither 检测到的主要问题："
        echo ""
        echo '```'
        echo "$ISSUES"
        echo '```'
        echo ""
    fi
    
    # 提取统计信息
    echo "## 统计信息"
    echo ""
    
    # 尝试提取统计信息
    STATS=$(grep "analyzed" reports/slither/report.txt || echo "无法提取统计信息")
    
    if [ "$STATS" == "无法提取统计信息" ]; then
        echo "无法从报告中提取统计信息。"
    else
        echo '```'
        echo "$STATS"
        echo '```'
    fi
    
    echo ""
    echo "## 安全建议"
    echo ""
    echo "1. 审查上述报告中的所有发现，并修复高危和中危问题。"
    echo "2. 对于低危和信息性问题，根据项目需求进行评估和处理。"
    echo "3. 针对特定问题，可以查看 [Slither Wiki](https://github.com/crytic/slither/wiki/Detector-Documentation) 获取详细解释和修复建议。"
    echo "4. 定期运行 Slither 分析，确保新代码不会引入新的安全问题。"
    echo ""
    echo "## 完整报告"
    echo ""
    echo "完整的分析报告可在以下文件中找到："
    echo "- 文本报告: `reports/slither/report.txt`"
    echo "- JSON 报告: `reports/slither/report.json`"
} > reports/slither/summary.md

echo -e "${GREEN}分析完成！Markdown 摘要报告已保存到 reports/slither/summary.md${NC}"
echo -e "${YELLOW}使用方法:${NC}"
echo -e "  ./run_slither.sh        # 默认分析 UniswapV3Pool.sol 合约"
echo -e "  ./run_slither.sh -c     # 分析 Uniswap V3 核心合约"
echo -e "  ./run_slither.sh -p     # 分析 Uniswap V3 外围合约"
echo -e "  ./run_slither.sh -o     # 分析我们自己的核心合约"
echo -e "  ./run_slither.sh -f 文件路径  # 分析单个文件"
echo -e "  ./run_slither.sh -a     # 分析所有合约" 