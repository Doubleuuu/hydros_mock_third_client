#!/bin/bash
set -euo pipefail

###############################################################################
# 应用配置 - 每个项目需要修改的部分
###############################################################################

APP_NAME="hydros-account"              # 应用名称
APP_PORT=7071                      # 应用端口
CONTAINER_NAME="hydros-account"       # 容器名称
DEFAULT_HYDROS_CLUSTER_ID="default_cluster"   # 默认集群名称
DEFAULT_HYDROS_NODE_ID="default_data"      # 默认节点名称
PARENT_POM="pom.xml"               # 数据子系统父POM
APP_MODULE="hydros-data-app"       # 当前应用模块目录名

###############################################################################
# 环境配置 - 制定了部署在什么宿主机以及环境标签
###############################################################################

HEALTH_ENDPOINT="/actuator/health" # Spring Boot健康检查端点

# 环境配置
# 开发环境配置
DEV_HOST="192.168.1.24"
DEV_PORT="2375"
DEV_SPRING_PROFILE="dev"
DEV_ENV_TAG="dev"
DEV_CLUSTER_ID="default_cluster_24"

# 生产环境配置
PROD_HOST="192.168.1.25"
PROD_PORT="2375"
PROD_SPRING_PROFILE="prod"
PROD_ENV_TAG="prod"
PROD_CLUSTER_ID="default_cluster_25"

# MQTT Broker 配置
DEV_MQTT_BROKER="tcp://192.168.1.24:1883"
PROD_MQTT_BROKER="tcp://192.168.1.25:1883"
PROD_MQTT_USER="hydros_agent_user"
PROD_MQTT_TOKEN='HbGcDx125a'

# 部署参数配置
MAX_RETRIES=12                     # 最大重试次数
RETRY_INTERVAL=3                   # 重试间隔(秒)
INITIAL_WAIT=3                     # 初始等待时间(秒)

###############################################################################
# 颜色和样式定义
###############################################################################

# 文本颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 文本样式
BOLD='\033[1m'
UNDERLINE='\033[4m'

###############################################################################
# 日志函数
###############################################################################

log_header() {
    echo -e "\n${CYAN}${BOLD}================================================================================${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}================================================================================${NC}"
}

log_step() {
    echo -e "\n${BLUE}${BOLD}[$(printf "%02d" $1)]${NC} ${BLUE}$2${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${PURPLE}[DEBUG]${NC} $1"
    fi
}

###############################################################################
# 工具函数
###############################################################################

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 '$1' 未安装"
        return 1
    fi
}

# 显示进度条
show_progress() {
    local duration=${1:-3}
    local width=50
    local increment=$((100 / width))

    for ((i=0; i<=width; i++)); do
        printf "\r["
        for ((j=0; j<width; j++)); do
            if [ $j -lt $i ]; then
                printf "#"
            else
                printf " "
            fi
        done
        printf "] %3d%%" $((i * increment))
        sleep "$(echo "scale=2; $duration/$width" | bc)"
    done
    printf "\n"
}

# 显示使用说明
show_usage() {
    echo ""
    echo -e "${BOLD}${APP_NAME} 部署脚本${NC}"
    echo ""
    echo -e "${UNDERLINE}使用方法:${NC}"
    echo "  $0 [环境] [选项]"
    echo ""
    echo -e "${UNDERLINE}环境:${NC}"
    echo "  dev      - 开发环境 (${DEV_HOST})"
    echo "  prod     - 生产环境 (${PROD_HOST})"
    echo ""
    echo -e "${UNDERLINE}选项:${NC}"
    echo "  -h, --help          显示此帮助信息"
    echo "  -d, --debug         启用调试模式"
    echo "  -v, --version       显示版本信息"
    echo "  --skip-build        跳过Maven构建"
    echo "  --skip-tests        跳过测试"
    echo "  --tag [标签]        自定义镜像标签"
    echo "  --port [端口]       自定义应用端口"
    echo "  --health [端点]     自定义健康检查端点"
    echo "  --cluster [名称]    自定义集群名称 (默认: default)"
    echo "  --node [名称]       自定义节点名称 (默认: edge)"
    echo ""
    echo -e "${UNDERLINE}示例:${NC}"
    echo "  $0 dev                     # 部署到开发环境"
    echo "  $0 prod                    # 部署到生产环境"
    echo "  $0 prod --skip-tests       # 部署到生产环境，跳过测试"
    echo "  $0 dev --tag v1.2.3        # 部署到开发环境，使用自定义标签"
    echo "  $0 prod --port 8082        # 部署到生产环境，使用自定义端口"
    echo "  $0 dev --cluster prod-cluster --node data-01  # 自定义集群和节点名称"
    echo ""
    exit 0
}

# 显示版本信息
show_version() {
    echo -e "${BOLD}${APP_NAME} 部署脚本 v1.0.0${NC}"
    echo "最后更新: $(date +%Y-%m-%d)"
    exit 0
}

# 解析命令行参数
parse_arguments() {
    local skip_build=false
    local skip_tests=""
    local custom_tag=""
    local custom_port=""
    local custom_health=""
    local custom_cluster=""
    local custom_node=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                ;;
            -d|--debug)
                DEBUG=true
                log_debug "调试模式已启用"
                shift
                ;;
            -v|--version)
                show_version
                ;;
            dev|prod)
                ENV="$1"
                shift
                ;;
            --skip-build)
                skip_build=true
                log_info "跳过Maven构建"
                shift
                ;;
            --skip-tests)
                skip_tests="-DskipTests"
                log_info "跳过测试"
                shift
                ;;
            --tag)
                if [ -n "$2" ]; then
                    custom_tag="$2"
                    log_info "使用自定义镜像标签: $custom_tag"
                    shift 2
                else
                    log_error "--tag 需要一个参数"
                    exit 1
                fi
                ;;
            --port)
                if [ -n "$2" ]; then
                    custom_port="$2"
                    APP_PORT="$custom_port"
                    log_info "使用自定义端口: $APP_PORT"
                    shift 2
                else
                    log_error "--port 需要一个参数"
                    exit 1
                fi
                ;;
            --health)
                if [ -n "$2" ]; then
                    custom_health="$2"
                    HEALTH_ENDPOINT="$custom_health"
                    log_info "使用自定义健康检查端点: $HEALTH_ENDPOINT"
                    shift 2
                else
                    log_error "--health 需要一个参数"
                    exit 1
                fi
                ;;
            --cluster)
                if [ -n "$2" ]; then
                    custom_cluster="$2"
                    log_info "使用自定义集群名称: $custom_cluster"
                    shift 2
                else
                    log_error "--cluster 需要一个参数"
                    exit 1
                fi
                ;;
            --node)
                if [ -n "$2" ]; then
                    custom_node="$2"
                    log_info "使用自定义节点名称: $custom_node"
                    shift 2
                else
                    log_error "--node 需要一个参数"
                    exit 1
                fi
                ;;
            *)
                log_error "未知参数: $1"
                show_usage
                ;;
        esac
    done

    # 设置变量
    SKIP_BUILD="$skip_build"
    SKIP_TESTS="$skip_tests"
    CUSTOM_TAG="$custom_tag"
    HYDROS_CLUSTER_ID="${custom_cluster:-$DEFAULT_HYDROS_CLUSTER_ID}"
    HYDROS_NODE_ID="${custom_node:-$DEFAULT_HYDROS_NODE_ID}"
}

# 根据环境设置变量
setup_environment() {
    case "$ENV" in
        dev)
            DOCKER_HOST_IP="$DEV_HOST"
            DOCKER_HOST_PORT="$DEV_PORT"
            SPRING_PROFILE="$DEV_SPRING_PROFILE"
            HYDROS_ENV="$DEV_ENV_TAG"
            DEFAULT_HYDROS_CLUSTER_ID="$DEV_CLUSTER_ID"
            HYDROS_MQTT_BROKER="$DEV_MQTT_BROKER"
            HYDROS_MQTT_USER=""
            HYDROS_MQTT_TOKEN=""
            ;;
        prod)
            DOCKER_HOST_IP="$PROD_HOST"
            DOCKER_HOST_PORT="$PROD_PORT"
            SPRING_PROFILE="$PROD_SPRING_PROFILE"
            HYDROS_ENV="$PROD_ENV_TAG"
            DEFAULT_HYDROS_CLUSTER_ID="$PROD_CLUSTER_ID"
            HYDROS_MQTT_BROKER="$PROD_MQTT_BROKER"
            HYDROS_MQTT_USER="$PROD_MQTT_USER"
            HYDROS_MQTT_TOKEN="$PROD_MQTT_TOKEN"
            ;;
        *)
            log_error "未知环境: $ENV"
            show_usage
            ;;
    esac

    # 如果用户没有通过 --cluster 参数自定义集群名称，则使用环境对应的集群ID
    if [ "$HYDROS_CLUSTER_ID" = "default_cluster" ]; then
        HYDROS_CLUSTER_ID="$DEFAULT_HYDROS_CLUSTER_ID"
    fi

    DOCKER_HOST="tcp://${DOCKER_HOST_IP}:${DOCKER_HOST_PORT}"
    APP_URL="http://${DOCKER_HOST_IP}:${APP_PORT}"

    log_info "目标环境: ${ENV}"
    log_info "Docker主机: ${DOCKER_HOST_IP}:${DOCKER_HOST_PORT}"
    log_info "应用地址: ${APP_URL}"
    log_info "Spring Profile: ${SPRING_PROFILE}"
    log_info "环境标签: ${HYDROS_ENV}"
    log_info "MQTT Broker: ${HYDROS_MQTT_BROKER}"
    if [ -n "$HYDROS_MQTT_USER" ]; then
        log_info "MQTT认证: 已启用 (用户: ${HYDROS_MQTT_USER})"
    else
        log_info "MQTT认证: 未启用"
    fi
}

# 前置检查
preflight_check() {
    log_step 1 "前置检查"

    # 检查必需命令
    check_command "mvn" || exit 1
    check_command "docker" || exit 1
    check_command "curl" || exit 1

    # 检查项目文件
    if [ "$SKIP_BUILD" = false ]; then
        if [ ! -f "pom.xml" ]; then
            log_error "当前目录未找到pom.xml文件"
            log_info "请在项目根目录运行此脚本"
            exit 1
        fi
    fi

    # 检查Dockerfile
    if [ ! -f "Dockerfile" ]; then
        log_error "当前目录未找到Dockerfile"
        exit 1
    fi

    # 检查网络连接
    log_info "检查网络连接..."
    if ! ping -c 1 -W 2 "${DOCKER_HOST_IP}" &> /dev/null; then
        log_warning "无法ping通 ${DOCKER_HOST_IP}，继续尝试..."
    fi

    # 检查Docker连接
    export DOCKER_HOST="${DOCKER_HOST}"
    log_info "连接Docker守护进程 (${DOCKER_HOST})..."
    if docker info &> /dev/null; then
        DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "未知")
        log_success "Docker连接成功 (版本: ${DOCKER_VERSION})"
    else
        log_error "无法连接Docker守护进程"
        log_info "请检查:"
        log_info "  1. Docker服务是否运行在 ${DOCKER_HOST_IP}"
        log_info "  2. 端口 ${DOCKER_HOST_PORT} 是否开放"
        log_info "  3. 防火墙设置"
        exit 1
    fi
}

# Maven构建
maven_build() {
    log_step 2 "Maven构建"

    if [ "$SKIP_BUILD" = true ]; then
        log_info "跳过构建"
        return 0
    fi

    local mvn_cmd="mvn -f ${PARENT_POM} -pl ${APP_MODULE} -am clean package ${SKIP_TESTS:--DskipTests}"
    log_info "执行: $mvn_cmd"

    if eval "$mvn_cmd"; then
        log_success "项目构建成功"

        # 获取构建信息
        if [ -f "pom.xml" ]; then
            local version=$(grep -oPm1 '(?<=<version>)[^<]+' pom.xml 2>/dev/null || echo "unknown")
            local artifact=$(grep -oPm1 '(?<=<artifactId>)[^<]+' pom.xml 2>/dev/null || echo "unknown")
            log_info "项目: ${artifact}:${version}"
        fi
        if [ ! -f "${APP_MODULE}/target/${APP_NAME}-0.0.1-SNAPSHOT.jar" ]; then
            log_error "未找到构建产物: ${APP_MODULE}/target/${APP_NAME}-0.0.1-SNAPSHOT.jar"
            exit 1
        fi
    else
        log_error "Maven构建失败"
        exit 1
    fi
}

# Docker镜像构建
docker_build() {
    log_step 3 "Docker镜像构建"

    # 生成镜像标签
    if [ -n "$CUSTOM_TAG" ]; then
        IMAGE_TAG="$CUSTOM_TAG"
    else
        IMAGE_TAG="$(date +%Y%m%d-%H%M%S)"
    fi

    IMAGE_NAME="${APP_NAME}:${IMAGE_TAG}"

    log_info "构建镜像: ${IMAGE_NAME}"
    log_info "Dockerfile: $(ls -la Dockerfile)"

    if docker build -t "${IMAGE_NAME}" .; then
        log_success "镜像构建成功"

        # 显示镜像信息
        local image_size=$(docker images --format "{{.Repository}}:{{.Tag}} {{.Size}}" | grep "${IMAGE_NAME}" | awk '{print $2}' || echo "未知")
        log_info "镜像大小: ${image_size}"
    else
        log_error "Docker镜像构建失败"
        exit 1
    fi
}

# 清理旧容器
cleanup_container() {
    log_step 4 "清理旧容器"

    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_info "找到旧容器: ${CONTAINER_NAME}"

        # 获取容器状态
        local container_state=$(docker inspect -f '{{.State.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "unknown")
        log_info "容器状态: ${container_state}"

        # 停止容器
        log_info "停止容器..."
        if docker stop "${CONTAINER_NAME}" &> /dev/null; then
            log_success "容器已停止"
        else
            log_warning "停止容器失败，尝试强制停止"
            docker kill "${CONTAINER_NAME}" 2>/dev/null || true
        fi

        # 删除容器
        log_info "删除容器..."
        if docker rm "${CONTAINER_NAME}" &> /dev/null; then
            log_success "容器已删除"
        else
            log_warning "删除容器失败，尝试强制删除"
            docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
        fi
    else
        log_info "没有找到运行的容器"
    fi
}

# 健康检查函数
health_check() {
    local host=$1
    local port=$2
    local health_endpoint=$3
    local max_retries=$4
    local interval=$5

    local primary_url="http://${host}:${port}${health_endpoint}"
    local fallback_url="http://${host}:${port}"
    local retry_count=0

    log_info "开始健康检查轮询..."
    log_info "目标地址: ${primary_url}"
    log_info "最大重试: ${max_retries}次，间隔: ${interval}秒"

    while [ $retry_count -lt $max_retries ]; do
        retry_count=$((retry_count + 1))

        echo -ne "\r[检查中] 尝试 ${retry_count}/${max_retries}..."

        # 尝试主健康端点
        if curl -s -f --max-time 5 "${primary_url}" &> /dev/null; then
            echo -e "\r[健康检查通过] 尝试 ${retry_count}/${max_retries} (${health_endpoint})"
            return 0
        fi

        # 尝试备用端点
        if curl -s -f --max-time 5 "${fallback_url}" &> /dev/null; then
            echo -e "\r[应用响应正常] 尝试 ${retry_count}/${max_retries} (根路径)"
            return 0
        fi

        # 显示进度
        if [ $retry_count -lt $max_retries ]; then
            echo -ne "\r[等待中] 尝试 ${retry_count}/${max_retries}，${interval}秒后重试..."
            sleep $interval
        fi
    done

    echo -e "\r[健康检查失败] 共尝试 ${max_retries} 次"

    # 提供诊断信息
    log_warning "诊断建议:"
    log_warning "  1. 检查容器日志: docker logs ${CONTAINER_NAME}"
    log_warning "  2. 检查容器状态: docker ps -a | grep ${CONTAINER_NAME}"
    log_warning "  3. 手动测试连接: curl -v ${primary_url}"

    return 1
}

# 启动新容器
start_container() {
    log_step 5 "启动新容器"

    log_info "容器配置:"
    log_info "  镜像: ${IMAGE_NAME}"
    log_info "  名称: ${CONTAINER_NAME}"
    log_info "  端口: ${APP_PORT}:${APP_PORT}"
    log_info "  环境: SPRING_PROFILES_ACTIVE=${SPRING_PROFILE}"
    log_info "  标签: HYDROS_ENV=${HYDROS_ENV}"
    log_info "  集群: HYDROS_CLUSTER_ID=${HYDROS_CLUSTER_ID}"
    log_info "  节点: HYDROS_NODE_ID=${HYDROS_NODE_ID}"
    log_info "  MQTT: HYDROS_MQTT_BROKER=${HYDROS_MQTT_BROKER}"
    if [ -n "$HYDROS_MQTT_USER" ]; then
        log_info "  MQTT认证: 已启用 (用户: ${HYDROS_MQTT_USER})"
    else
        log_info "  MQTT认证: 未启用"
    fi


    # 1. 定义基地址变量 (根据你的要求拼接 Cluster ID 和 Node ID)
    local host_volume_base_dir="/opt/hydros/clusters/${HYDROS_CLUSTER_ID}/${HYDROS_NODE_ID}"

    # ==========================================================
    # 远程初始化步骤：启动一个临时容器来创建目录并修改权限
    # ==========================================================
    log_info "正在远程初始化目录和权限..."
    log_info "目标路径: ${host_volume_base_dir}"

    ## 利用 Docker 本身的能力，运行一个临时的"工兵容器" (Helper Container) 来完成远程目录的初始化工作。
    # 解释：
    # --rm: 任务做完后立即删除这个临时容器
    # -v "${host_volume_base_dir}:/temp_mount": 把远程宿主机的目录挂载到临时容器内部
    # alpine: 使用最小的 Linux 镜像 (如果远程没有会自动下载，仅几MB)
    # sh -c "...": 执行 Shell 命令
    # 这里的 1000:1000 对应容器内的 USER ID

    ## 优化：先检查本地是否存在 alpine 镜像，避免重复拉取
    log_info "检查辅助镜像 (alpine)..."

    # 使用 image inspect 检查镜像是否存在 (重定向输出以保持整洁)
    if docker image inspect alpine:latest >/dev/null 2>&1; then
        log_info "检测到本地已有 alpine 镜像，跳过拉取"
    else
        log_info "本地未找到 alpine 镜像，正在拉取..."
        if docker pull alpine &> /dev/null; then
            log_success "alpine 镜像拉取成功"
        else
            log_error "alpine 镜像拉取失败"
            # 这里可以选择退出，或者让它尝试往下跑（可能会报错）
        fi
    fi

    log_info "创建目录并设置权限..."
    if docker run --rm \
        -v "${host_volume_base_dir}:/temp_mount" \
        alpine \
        sh -c "mkdir -p /temp_mount/data /temp_mount/logs && chown -R 1000:1000 /temp_mount && ls -la /temp_mount"; then
        log_success "远程目录初始化成功"
    else
        log_error "远程目录初始化失败"
        log_warning "将尝试继续启动容器，Docker 会自动创建目录（但权限可能不正确）"
    fi

    # 构建docker run命令
    local docker_run_args=(
        "docker" "run" "-d"
        "-p" "${APP_PORT}:${APP_PORT}"
        "-v" "${host_volume_base_dir}/data:/app/data"
        "-v" "${host_volume_base_dir}/logs:/app/logs"
        "--name" "${CONTAINER_NAME}"
        "-e" "SPRING_PROFILES_ACTIVE=${SPRING_PROFILE}"
        "-e" "HYDROS_ENV=${HYDROS_ENV}"
        "-e" "HYDROS_CLUSTER_ID=${HYDROS_CLUSTER_ID}"
        "-e" "HYDROS_NODE_ID=${HYDROS_NODE_ID}"
        "-e" "HYDROS_MQTT_BROKER=${HYDROS_MQTT_BROKER}"
    )
    if [ -n "$HYDROS_MQTT_USER" ]; then
        docker_run_args+=("-e" "HYDROS_MQTT_USER=${HYDROS_MQTT_USER}")
        docker_run_args+=("-e" "HYDROS_MQTT_TOKEN=${HYDROS_MQTT_TOKEN}")
    fi
    docker_run_args+=("--restart=always" "${IMAGE_NAME}")

    if "${docker_run_args[@]}"; then
        log_success "容器启动成功"

        # 获取容器ID
        CONTAINER_ID=$(docker ps -q --filter "name=${CONTAINER_NAME}")
        log_info "容器ID: ${CONTAINER_ID}"

        # 等待初始启动
        log_info "等待应用初始化 (${INITIAL_WAIT}秒)..."
        show_progress $INITIAL_WAIT
    else
        log_error "容器启动失败"
        exit 1
    fi
}

# 验证部署
verify_deployment() {
    log_step 6 "验证部署"

    # 检查容器状态
    log_info "检查容器运行状态..."
    CONTAINER_STATUS=$(docker ps --filter "name=${CONTAINER_NAME}" --format "{{.Status}}")

    if [ -n "${CONTAINER_STATUS}" ]; then
        log_success "容器运行中: ${CONTAINER_STATUS}"
    else
        log_error "容器未运行"
        log_info "尝试查看容器日志..."
        docker logs "${CONTAINER_NAME}" 2>/dev/null | tail -20 || true
        exit 1
    fi

    # 执行健康检查
    if health_check "${DOCKER_HOST_IP}" "${APP_PORT}" "${HEALTH_ENDPOINT}" "${MAX_RETRIES}" "${RETRY_INTERVAL}"; then
        HEALTH_STATUS="通过"
    else
        HEALTH_STATUS="失败"
    fi

    # 检查端口监听
    log_info "检查端口监听状态..."
    if timeout 2 bash -c "cat < /dev/null > /dev/tcp/${DOCKER_HOST_IP}/${APP_PORT}" 2>/dev/null; then
        log_success "端口 ${APP_PORT} 监听正常"
    else
        log_warning "端口 ${APP_PORT} 可能未正确监听"
    fi
}

# 代码更新函数 (新增)
update_code() {
    log_step 2 "更新代码 (Git)" # 注意：后续步骤编号可能需要您手动顺延（如Maven构建改为3）

    # 检查是否有git环境
    if ! command -v git &> /dev/null; then
        log_warning "未检测到git命令，跳过代码更新"
        return 0
    fi

    # 1. 检查本地是否有未提交的修改 (Safety Check)
    # 使用 --porcelain 获取纯净的状态输出
    if [ -n "$(git status --porcelain)" ]; then
        log_error "检测到本地有未提交的代码修改！"
        log_warning "为了防止代码覆盖或合并混乱，自动化脚本已停止。"
        log_info "请执行以下操作之一后重试："
        log_info "  1. 提交代码: git commit -m '...'"
        log_info "  2. 暂存修改: git stash"
        exit 1
    fi

    # 获取当前分支名称
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    log_info "当前分支: ${current_branch}"

    # 2. 拉取代码并处理潜在冲突
    log_info "正在执行 git pull origin ${current_branch} ..."

    # 捕获 git pull 的执行状态
    if git pull origin "${current_branch}"; then
        log_success "代码已更新至最新版本"
    else
        # 如果 exit code 不为 0，通常意味着有冲突或网络问题
        echo ""
        log_error "代码拉取失败！"
        log_info "可能原因："
        log_info "  1. 存在 Git 合并冲突 (Merge Conflicts)"
        log_info "  2. 网络连接问题"
        log_warning "请手动解决冲突后再次运行部署脚本。"
        exit 1
    fi
}

# 显示部署摘要
show_summary() {
    log_header "部署完成"

    # 获取详细信息
    local container_id=$(docker ps -q --filter "name=${CONTAINER_NAME}")
    local image_id=$(docker inspect -f '{{.Image}}' "${CONTAINER_NAME}" 2>/dev/null | cut -c 1-12)
    local created=$(docker inspect -f '{{.Created}}' "${CONTAINER_NAME}" 2>/dev/null)
    local ip_address=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null)

    echo ""
    echo "========================================================"
    echo "  部署成功!"
    echo "========================================================"
    echo ""
    echo "应用信息:"
    echo "  应用名称: ${APP_NAME}"
    echo "  运行环境: ${HYDROS_ENV} (${HYDROS_ENV})"
    echo "  Spring Profile: ${SPRING_PROFILE}"
    echo "  集群名称: ${HYDROS_CLUSTER_ID}"
    echo "  节点名称: ${HYDROS_NODE_ID}"
    echo "  MQTT Broker: ${HYDROS_MQTT_BROKER}"
    if [ -n "$HYDROS_MQTT_USER" ]; then
        echo "  MQTT认证: 已启用 (用户: ${HYDROS_MQTT_USER})"
    else
        echo "  MQTT认证: 未启用"
    fi
    echo "  部署时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "容器信息:"
    echo "  容器名称: ${CONTAINER_NAME}"
    echo "  容器ID: ${container_id:-N/A}"
    echo "  镜像版本: ${IMAGE_NAME}"
    echo "  镜像ID: ${image_id:-N/A}"
    echo "  内部IP: ${ip_address:-N/A}"
    echo "  状态: ${CONTAINER_STATUS}"
    echo ""
    echo "网络信息:"
    echo "  访问地址: ${APP_URL}"
    echo "  Docker主机: ${DOCKER_HOST_IP}:${DOCKER_HOST_PORT}"
    echo "  映射端口: ${APP_PORT} → ${APP_PORT}"
    echo "  健康检查: ${HEALTH_STATUS}"
    echo ""
    echo "常用命令:"
    echo "  查看日志:    docker logs -f ${CONTAINER_NAME}"
    echo "  进入容器:    docker exec -it ${CONTAINER_NAME} /bin/bash"
    echo "  停止容器:    docker stop ${CONTAINER_NAME}"
    echo "  重启容器:    docker restart ${CONTAINER_NAME}"
    echo ""

    if [ "$HEALTH_STATUS" = "通过" ]; then
        log_success "应用已成功部署并正常运行！"
    else
        log_warning "应用已部署但健康检查失败，请检查日志"
    fi
}

###############################################################################
# 主函数
###############################################################################

main() {
    log_header "${APP_NAME} 自动化部署脚本"

    # 解析参数
    parse_arguments "$@"

    # 检查环境参数
    if [ -z "${ENV:-}" ]; then
        log_error "必须指定部署环境 (dev 或 prod)"
        show_usage
    fi

    # 根据环境设置变量
    setup_environment

    # 执行部署流程
    preflight_check

    # --- 新增调用开始 ---
    # 如果设置了跳过构建，通常也意味着不需要拉新代码（视需求而定，这里默认不跳过）
    if [ "$SKIP_BUILD" = false ]; then
        update_code
    fi
    # --- 新增调用结束 ---

    maven_build
    docker_build
    cleanup_container
    start_container
    verify_deployment

    # 显示结果
    show_summary

    # 退出码
    if [ "$HEALTH_STATUS" = "通过" ]; then
        exit 0
    else
        exit 1
    fi
}

###############################################################################
# 脚本入口
###############################################################################

# 如果没有参数，显示帮助
if [ $# -eq 0 ]; then
    show_usage
fi

# 执行主函数
main "$@"
