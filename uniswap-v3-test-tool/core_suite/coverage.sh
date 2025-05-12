#!/bin/bash

# 设置颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

# 创建报告目录
mkdir -p reports/coverage

echo -e "${YELLOW}开始生成覆盖率报告...${NC}"

# 运行Forge测试并生成覆盖率报告
forge coverage --report lcov

# 检查是否生成了lcov.info文件
if [ ! -f lcov.info ]; then
    echo -e "${RED}错误: 未能生成lcov.info文件${NC}"
    exit 1
fi

# 移动lcov文件到报告目录
mv lcov.info reports/coverage/

# 使用lcov生成HTML报告
lcov --summary reports/coverage/lcov.info
genhtml reports/coverage/lcov.info -o reports/coverage/html

# 检查HTML报告是否生成成功
if [ -d "reports/coverage/html" ]; then
    echo -e "${GREEN}覆盖率报告生成成功!${NC}"
    echo -e "${GREEN}报告位置: $(pwd)/reports/coverage/html/index.html${NC}"

    # 显示覆盖率统计信息
    COVERAGE=$(lcov --summary reports/coverage/lcov.info | grep "lines" | awk '{print $4}')
    echo -e "${GREEN}代码行覆盖率: $COVERAGE${NC}"
else
    echo -e "${RED}错误: 未能生成HTML覆盖率报告${NC}"
    exit 1
fi

echo -e "${YELLOW}覆盖率分析完成!${NC}"
exit 0 