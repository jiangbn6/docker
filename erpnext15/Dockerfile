# 基础镜像：指定Ubuntu 22.04（与脚本适配版本一致）
FROM ubuntu:22.04

# 核心配置1：构建阶段标记（默认yes，构建时跳过数据库逻辑）
ARG BUILD_STAGE=yes
ENV BUILD_STAGE=${BUILD_STAGE}

# 核心配置2：数据库容器参数（运行时可通过-e覆盖，同子网数据库容器）
ENV DB_CONTAINER_HOST=mariadb-container \
    DB_CONTAINER_PORT=3306 \
    DB_CONTAINER_ROOT_PASS=jiangbn6

# 安装脚本依赖（基础工具）
RUN apt update && apt install -y bash curl sudo locales tzdata && \
    # 设置语言和时区（与脚本保持一致）
    locale-gen en_US.UTF-8 && \
    ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# 复制修改后的安装脚本到镜像内（适配实际路径：installdata）
COPY installdata/install-erpnext15.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/install-erpnext15.sh

# 执行安装脚本（构建阶段：仅安装依赖，跳过数据库）
RUN /usr/local/bin/install-erpnext15.sh

# 暴露ERPNext默认端口
EXPOSE 80 8000

# 容器启动命令（运行阶段：切换为BUILD_STAGE=no，绑定数据库容器）
CMD ["bash", "-c", "BUILD_STAGE=no /usr/local/bin/install-erpnext15.sh && supervisord -n -c /etc/supervisor/supervisord.conf"]
