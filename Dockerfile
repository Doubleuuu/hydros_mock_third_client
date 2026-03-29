# 使用 OpenJDK 25 的官方镜像
FROM eclipse-temurin:25

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone


# 安装 curl 并处理 admin 用户 (UID 1000)
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    # 如果存在 UID 为 1000 的用户 先将其删除 确保我们可以占用 1000
    if getent passwd 1000; then userdel -r $(getent passwd 1000 | cut -d: -f1); fi; \
    # 如果存在 GID 为 1000 的组，先将其删除
    if getent group 1000; then groupdel $(getent group 1000 | cut -d: -f1); fi; \
    # 创建我们要的 admin 用户和组
    groupadd -g 1000 admin && \
    useradd -u 1000 -g admin -m admin && \
    rm -rf /var/lib/apt/lists/*
# ----------------------

# 设置工作目录
WORKDIR /app

# 复制构建好的 JAR 文件
COPY hydros-data-app/target/hydros-data-0.0.1-SNAPSHOT.jar hydros-data.jar

# 关键：修改目录所有者为 admin
RUN chown -R admin:admin /app

# 暴露应用端口
EXPOSE 8081

# 暴露调试端口（可选）
EXPOSE 5005

# 设置默认环境变量（可通过docker run覆盖）
ENV SPRING_PROFILES_ACTIVE=local
ENV HYDROS_ENV=local
ENV HYDROS_CLUSTER_ID=default_cluster
ENV JAVA_OPTS=""

# 切换到 admin 用户运行
USER admin

# 健康检查端点
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8081/actuator/health || exit 1

# 为了liteflow兼容jdk21版本，在容器启动时，使用带有 --add-opens 参数的 java 命令运行应用
# 使用JSON数组形式以确保正确的信号处理
ENTRYPOINT ["sh", "-c", "exec java \
    --add-opens=java.base/sun.reflect.annotation=ALL-UNNAMED \
    --sun-misc-unsafe-memory-access=allow \
    -Xmx1024m -Xms512m -XX:+UseG1GC \
    -XX:+ExitOnOutOfMemoryError \
    -Djava.security.egd=file:/dev/./urandom \
    -Duser.timezone=Asia/Shanghai \
    ${JAVA_OPTS} -jar hydros-data.jar"]
