#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Prometheus指标导出器
用于收集Uniswap V3交互指标并导出为Prometheus格式
"""

import os
import time
import yaml
import logging
from flask import Flask, Response
from prometheus_client import Counter, Gauge, Histogram, generate_latest, REGISTRY
from web3 import Web3
from dotenv import load_dotenv

# 加载环境变量
load_dotenv()

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 加载配置
def load_config():
    config_path = os.getenv('CONFIG_PATH', '../config/default.yaml')
    try:
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        # 检查本地覆盖配置
        local_config_path = os.getenv('LOCAL_CONFIG_PATH', '../config/local.yaml')
        if os.path.exists(local_config_path):
            with open(local_config_path, 'r') as f:
                local_config = yaml.safe_load(f)
                # 递归合并配置
                def merge_config(d1, d2):
                    for k, v in d2.items():
                        if k in d1 and isinstance(d1[k], dict) and isinstance(v, dict):
                            merge_config(d1[k], v)
                        else:
                            d1[k] = v
                if local_config:
                    merge_config(config, local_config)
        
        return config
    except Exception as e:
        logger.error(f"加载配置失败: {e}")
        return {}

config = load_config()

# 初始化Web3
def init_web3():
    rpc_url = os.getenv('NODE_URL', config.get('ethereum', {}).get('rpc_url', 'http://localhost:8545'))
    try:
        w3 = Web3(Web3.HTTPProvider(rpc_url))
        if not w3.is_connected():
            logger.error(f"无法连接到以太坊节点: {rpc_url}")
            return None
        logger.info(f"已连接到以太坊节点: {rpc_url}, 当前区块: {w3.eth.block_number}")
        return w3
    except Exception as e:
        logger.error(f"初始化Web3失败: {e}")
        return None

w3 = init_web3()

# 定义Prometheus指标
swap_count = Counter('uniswap_swap_count', 'Uniswap V3 Swap交易次数')
tvl_gauge = Gauge('uniswap_tvl', 'Uniswap V3总锁定价值', ['pool'])
volume_gauge = Gauge('uniswap_volume_24h', 'Uniswap V3 24小时交易量', ['pool'])
swap_latency = Histogram('uniswap_swap_latency_seconds', 'Uniswap V3 Swap交易延迟', buckets=[0.1, 0.5, 1, 2, 5, 10, 30, 60])

# 初始化Flask应用
app = Flask(__name__)

@app.route('/metrics')
def metrics():
    """导出当前收集的指标"""
    return Response(generate_latest(REGISTRY), mimetype='text/plain')

@app.route('/health')
def health():
    """健康检查接口"""
    if w3 and w3.is_connected():
        return {"status": "ok", "blockNumber": w3.eth.block_number}
    return {"status": "error", "message": "无法连接到以太坊节点"}, 500

def update_metrics():
    """定期更新指标"""
    while True:
        try:
            if w3 and w3.is_connected():
                # 模拟更新TVL数据
                # 实际实现中需要调用Uniswap V3合约获取真实数据
                pool_addresses = [pool['address'] for pool in config.get('uniswap', {}).get('test_pools', [])]
                for i, addr in enumerate(pool_addresses):
                    # 模拟数据，实际应该从合约获取
                    tvl_gauge.labels(pool=addr).set(100_000_000 + i * 10_000_000)
                    volume_gauge.labels(pool=addr).set(5_000_000 + i * 1_000_000)
        except Exception as e:
            logger.error(f"更新指标失败: {e}")
        
        time.sleep(15)  # 每15秒更新一次

def record_swap(tx_hash, latency):
    """记录交易指标"""
    swap_count.inc()
    swap_latency.observe(latency)
    logger.info(f"记录交易: {tx_hash}, 延迟: {latency}秒")

if __name__ == '__main__':
    # 启动后台线程更新指标
    import threading
    metrics_thread = threading.Thread(target=update_metrics, daemon=True)
    metrics_thread.start()
    
    # 启动Flask应用
    host = config.get('monitoring', {}).get('exporter', {}).get('host', '0.0.0.0')
    port = int(config.get('monitoring', {}).get('exporter', {}).get('port', 8000))
    logger.info(f"启动指标导出器: http://{host}:{port}/metrics")
    app.run(host=host, port=port)
