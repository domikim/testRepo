#!/bin/bash

# 使用date命令检测时区
TIMEZONE=$(date +%Z 2>/dev/null)
if [ -z "$TIMEZONE" ]; then
    echo "警告：无法获取系统时区信息，将跳过时区检查。"
    # exit 1 已移除
fi

# 检查时区是否为上海
if [ "$TIMEZONE" != "CST" ]; then
    TZ_FILE=$(readlink /etc/localtime 2>/dev/null | grep -o 'zoneinfo/.*' | cut -d/ -f2-)
    
    if [ "$TZ_FILE" != "Asia/Shanghai" ]; then
        echo "警告：时区不是上海时间，当前时区为 $TIMEZONE，请手动设置为 Asia/Shanghai。"
        # exit 1 已移除
    fi
fi

# 定义 NTP 服务器地址
NTP_SERVER="ntp1.aliyun.com"

# 尝试获取 NTP 服务器时间
echo "正在连接NTP服务器 $NTP_SERVER 获取时间..."
NTP_TIME=$(ntpdate -q $NTP_SERVER 2>&1)
NTP_STATUS=$?

if [ $NTP_STATUS -eq 0 ]; then
    # 从ntpdate输出中提取参考时间戳（格式: 2025-07-03 10:04:04.504632）
    REF_TIME=$(echo "$NTP_TIME" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+')
    
    if [ -z "$REF_TIME" ]; then
        echo "警告：无法从ntpdate输出中提取参考时间。"
        echo "ntpdate完整输出信息:"
        echo "$NTP_TIME"
        # exit 1 已移除
    else
        # 移除微秒部分，只保留整数秒
        REF_TIME_SEC=$(echo "$REF_TIME" | awk -F'.' '{print $1}')
        
        # 将参考时间转换为上海时区时间戳（已包含时区偏移）
        REMOTE_SHANGHAI_TIMESTAMP=$(date -d "$REF_TIME_SEC" +%s 2>/dev/null)
        
        # 获取本地时间戳
        LOCAL_TIMESTAMP=$(date +%s 2>/dev/null)

        # 验证时间戳是否为有效的整数值
        if [[ -z "$LOCAL_TIMESTAMP" || ! "$LOCAL_TIMESTAMP" =~ ^[0-9]+$ ]]; then
            echo "警告：无法获取有效的本地时间戳，将跳过时间比对。"
            # exit 1 已移除
        elif [[ -z "$REMOTE_SHANGHAI_TIMESTAMP" || ! "$REMOTE_SHANGHAI_TIMESTAMP" =~ ^[0-9]+$ ]]; then
            echo "警告：无法获取有效的远程时间戳，将跳过时间比对。"
            # exit 1 已移除
        else
            # 计算时间差（绝对值）
            TIME_DIFF=$((REMOTE_SHANGHAI_TIMESTAMP - LOCAL_TIMESTAMP))
            ABS_TIME_DIFF=${TIME_DIFF#-}  # 取绝对值

            # 设定可接受的时间误差（单位：秒）
            MAX_OFFSET=5

            if [ $ABS_TIME_DIFF -gt $MAX_OFFSET ]; then
                if [ $TIME_DIFF -gt 0 ]; then
                    echo "警告：本地时间比网上上海时区时间晚 $ABS_TIME_DIFF 秒，允许最大误差为 $MAX_OFFSET 秒，请手动校准。"
                else
                    echo "警告：本地时间比网上上海时区时间早 $ABS_TIME_DIFF 秒，允许最大误差为 $MAX_OFFSET 秒，请手动校准。"
                fi
                # exit 1 已移除
            else
                if [ $TIME_DIFF -eq 0 ]; then
                    echo "本地时间与网上上海时区时间完全一致。"
                elif [ $TIME_DIFF -gt 0 ]; then
                    echo "本地时间准确，比网上上海时区时间晚 $TIME_DIFF 秒，在允许的 $MAX_OFFSET 秒范围内。"
                else
                    echo "本地时间准确，比网上上海时区时间早 $((-TIME_DIFF)) 秒，在允许的 $MAX_OFFSET 秒范围内。"
                fi
            fi
        fi
    fi
else
    echo "警告：无法连接到 NTP 服务器 $NTP_SERVER，可能网络不可用，跳过时间比对。"
    echo "NTP服务器返回的错误信息:"
    echo "$NTP_TIME"
    # exit 1 已移除
fi

# 脚本继续执行后续内容（如果有）
echo "时间检查完成，脚本继续运行..."

# 获取本机的所有网卡地址
ipaddr=$(ifconfig -a | grep inet | grep -v 127.0.0.1 | grep -v inet6 | awk '{print $2}' | tr -d "addr:")
# 打印出所有网卡地址
echo "你的网卡地址有：$ipaddr"

myip="10.17.8.19"
# 判断输入的 ip 地址是否在网卡地址中
if [[ ! $ipaddr =~ $myip ]]; then
  echo "ip地址错误，$myip 不是你的一个网卡地址。"
  exit 0
fi

GATEWAY_HTTP_PORT="8081"
GATEWAY_RPC_PORT="8081"

res=`docker ps -a | grep -w testagentgateway | wc -l`
echo $res
if [ $res -gt 0 ];then
        echo "stop  testagentgateway..."

        docker stop testagentgateway
        # 删除旧容器
        docker rm -f testagentgateway
fi

res=`docker ps -a | grep -w taskrunner | wc -l`
echo $res
if [ $res -gt 0 ];then
        echo "stop  taskrunner..."

        docker stop  taskrunner
        # 删除旧容器
        docker rm -f taskrunner
fi


# 启动testagentgateway
echo "starting agentgateway..."
docker run --name testagentgateway -d -v /etc/hosts:/etc/hosts -p $GATEWAY_HTTP_PORT:8080 -p $GATEWAY_RPC_PORT:8081 -e SRD_SERVER="www.srdcloud.cn" -e SOFT_VERSION="v3.6.2" -e AGENT_ID="xxxx" -e MY_HOST="10.17.8.19" -e DEPLOY_TYPE="host" -e secword="xxxxxxxxx" gz01-srdart.srdcloud.cn/public/public-devops-release-docker-local/taas/testagentgateway:v3.6.1



#启动taskrunner
docker run --name taskrunner -p 28181:8081 -v /var/run/docker.sock:/var/run/docker.sock -v /var/taas:/var/taas -v /etc/hosts:/etc/hosts -d -e GATEWAY_RPC_PORT=$GATEWAY_RPC_PORT -e GATEWAY_HTTP_PORT=$GATEWAY_HTTP_PORT -e GATEWAY_HOST="10.17.8.19" -e AGENT_ID="xxxx" -e secword="xxxxxxxxx" -e MY_HOST="10.17.8.19:28181" -e ENGINE_TYPE="jmeter,python,java"  -e DEPLOY_TYPE="host"  gz01-srdart.srdcloud.cn/public/public-devops-release-docker-local/taas/taskrunner:v3.6.1


res=`docker ps -a | grep -w taasjavaengine | wc -l`
echo $res
if [ $res -gt 0 ];then
        echo "stop  taasjavaengine..."

        docker stop  taasjavaengine
        # 删除旧容器
        docker rm -f taasjavaengine
fi
res=`docker ps -a | grep -w taasjmeterengine | wc -l`
echo $res
if [ $res -gt 0 ];then
        echo "stop  taasjmeterengine..."

        docker stop  taasjmeterengine
        # 删除旧容器
        docker rm -f taasjmeterengine
fi
res=`docker ps -a | grep -w taaspyengine | wc -l`
echo $res
if [ $res -gt 0 ];then
        echo "stop  taaspyengine..."

        docker stop  taaspyengine
        # 删除旧容器
        docker rm -f taaspyengine
fi



docker run -d --name taasjavaengine --entrypoint="sh"  -v /var/taas:/var/taas -v /etc/hosts:/etc/hosts -v /etc/localtime:/etc/localtime:ro -e ArtifactPreURL="https://gz01-srdart.srdcloud.cn" -e ArtifactType="srdart"  gz01-srdart.srdcloud.cn/public/public-devops-release-docker-local/taas/apline-jdk:8-srd1.5.1 -c " /opt/source_change.sh; while true; do sleep 10; done"










docker run -d --name taasjmeterengine --entrypoint="sh" -p 1099:1099 -v /etc/hosts:/etc/vhosts  -v /var/taas:/var/taas -e ArtifactPreURL="https://gz01-srdart.srdcloud.cn" -e ArtifactType="srdart"  gz01-srdart.srdcloud.cn/public/public-devops-release-docker-local/taas/jmeter:5.6.3-srd1.5.1 -c "grep -v localhost /etc/vhosts >> /etc/hosts; /opt/source_change.sh; jmeter-server;while true; do sleep 10; done"





docker run -d --name taaspyengine --entrypoint="sh" -v /etc/hosts:/etc/hosts  -v /var/taas:/var/taas -e ArtifactPreURL="https://gz01-srdart.srdcloud.cn" -e ArtifactType="srdart" gz01-srdart.srdcloud.cn/public/public-devops-release-docker-local/taas/python:3.9-srd1.4.1 -c " /opt/source_change.sh; while true; do sleep 10; done"



