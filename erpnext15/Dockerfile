# ERPNext 15 应用镜像（不含数据库）
FROM ubuntu:22.04
LABEL author="jiangbn6"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y \
        sudo curl wget git locales tzdata cron \
        python3-dev python3-venv python3-pip \
        mariadb-client libmysqlclient-dev \
        xvfb libfontconfig wkhtmltopdf \
        supervisor build-essential \
        libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev \
        redis-server \
        && rm -rf /var/lib/apt/lists/*

# 配置 locale
RUN localedef -i en_US -f UTF-8 en_US.UTF-8 && \
    echo 'LANG=en_US.UTF-8' > /etc/default/locale

# 安装 Node.js 18
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    npm install -g yarn

# 创建 frappe 用户
RUN useradd -m -s /bin/bash -G sudo frappe && \
    echo "frappe ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# 复制安装脚本
COPY ./installdata/install-erpnext15-external-db.sh /tmp/
RUN chmod +x /tmp/install-erpnext15-external-db.sh

# 执行静默安装
RUN /tmp/install-erpnext15-external-db.sh -qd

# 切换用户
USER frappe
WORKDIR /home/frappe/frappe-bench

# 暴露端口（nginx 默认 80）
EXPOSE 80

# 挂载站点数据
VOLUME /home/frappe/frappe-bench/sites

# 启动 supervisord（管理 nginx, gunicorn, redis 等）
CMD ["sudo", "/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
