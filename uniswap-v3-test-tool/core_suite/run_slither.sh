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
    TARGETS="$PROJECT_ROOT/lib/v3-core/contracts"
elif [ "$1" == "-t" ] || [ "$1" == "--tests" ]; then
    # 只分析测试合约
    echo -e "${YELLOW}分析测试合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/tests"
elif [ "$1" == "-a" ] || [ "$1" == "--all" ]; then
    # 分析所有合约
    echo -e "${YELLOW}分析所有合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/tests $PROJECT_ROOT/lib/v3-core/contracts"
else
    # 默认分析测试合约
    echo -e "${YELLOW}默认分析测试合约...${NC}"
    TARGETS="$CORE_SUITE_DIR/tests"
fi

# 检查目标目录是否存在
echo -e "${YELLOW}检查目标目录是否存在...${NC}"
for target in $TARGETS; do
    if [ ! -d "$target" ]; then
        echo -e "${RED}错误: 目标目录 $target 不存在${NC}"
        echo -e "${YELLOW}请检查目录结构或修改脚本中的路径${NC}"
        exit 1
    else
        echo -e "${GREEN}目标目录 $target 存在${NC}"
        echo -e "${YELLOW}目录内容:${NC}"
        ls -la "$target" | head -n 10
    fi
done

# 运行 Slither 分析并生成报告
echo -e "${YELLOW}正在分析 $TARGETS...${NC}"

# 生成文本报告
echo -e "${YELLOW}运行命令: $SLITHER_PATH $TARGETS --config-file $CONFIG_PATH${NC}"
$SLITHER_PATH $TARGETS --config-file "$CONFIG_PATH" > reports/slither/report.txt 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Slither 分析完成，报告已保存到 reports/slither/report.txt${NC}"
else
    echo -e "${RED}Slither 分析出现错误${NC}"
    echo -e "${YELLOW}请查看错误信息：${NC}"
    cat reports/slither/report.txt
fi

# 生成 JSON 报告
$SLITHER_PATH $TARGETS --config-file "$CONFIG_PATH" --json reports/slither/report.json > /dev/null 2>&1
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
echo -e "  ./run_slither.sh        # 分析测试合约"
echo -e "  ./run_slither.sh -c     # 分析核心合约"
echo -e "  ./run_slither.sh -t     # 分析测试合约"
echo -e "  ./run_slither.sh -a     # 分析所有合约" 