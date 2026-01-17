#!/bin/bash
# ERPNext 15 安装脚本（外部数据库模式）
# 作者: lvxj11 (modified for external DB)
# 修改: jiangbn6 - 使用外部 MariaDB, admin/jiangbn6, 端口 8080

set -e

# ========== 系统检查 ==========
cat /etc/os-release
osVer=$(cat /etc/os-release | grep 'Ubuntu 22.04' || true)
if [[ ${osVer} == '' ]]; then 
  echo '脚本只在 Ubuntu 22.04 版本测试通过。其它系统版本需要重新适配。退出安装。'
  exit 1
else 
  echo '系统版本检测通过...'
fi

if [ "$(id -u)" != "0" ]; then
  echo "脚本需要使用 root 用户执行"
  exit 1
else
  echo '执行用户检测通过...'
fi

# ========== 参数设定 ==========
mariadbHost="mariadb"               # Docker 服务名
mariadbPort="3306"
mariadbRootPassword="jiangbn6"      # ← 外部 DB 的 root 密码
adminPassword="jiangbn6"            # ← ERPNext 管理员密码
installDir="frappe-bench"
userName="frappe"
frappeBranch="version-15"
erpnextPath="https://github.com/frappe/erpnext"
erpnextBranch="version-15"
siteName="erp.example.com"          # 可自定义，但需与生产配置一致
siteDbPassword="jiangbn6"           # 站点数据库密码（bench 会创建此用户）
productionMode="yes"
altAptSources="yes"

# 解析命令行参数（保持静默安装支持）
while getopts "qda:" opt; do
  case $opt in
    q) quietMode="yes" ;;
    d) productionMode="no" ;;
    a) altAptSources="no" ;;
    \?) echo "无效选项: -$OPTARG" >&2; exit 1 ;;
  esac
done

# ========== 安装基础软件（不含 MariaDB 服务端）==========
echo "=================== 安装基础依赖 ==================="
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y \
 ca-certificates sudo locales tzdata cron wget curl \
 python3-dev python3-venv python3-setuptools python3-pip python3-testresources \
 git software-properties-common \
 mariadb-client libmysqlclient-dev \          # 仅客户端
 xvfb libfontconfig wkhtmltopdf \
 supervisor pkg-config build-essential \
 libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev

# ========== 配置 locale ==========
localedef -i en_US -f UTF-8 en_US.UTF-8
echo 'LANG=en_US.UTF-8' > /etc/default/locale

# ========== 安装 Redis ==========
echo "=================== 安装 Redis ==================="
DEBIAN_FRONTEND=noninteractive apt install -y redis-server
sed -i 's/supervised no/supervised systemd/g' /etc/redis/redis.conf
systemctl enable redis-server
systemctl start redis-server

# ========== 安装 Node.js 和 Yarn ==========
echo "=================== 安装 Node.js 18 & Yarn ==================="
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
DEBIAN_FRONTEND=noninteractive apt install -y nodejs
npm install -g yarn

# ========== 创建 frappe 用户 ==========
if id "${userName}" &>/dev/null; then
  echo "用户 ${userName} 已存在"
else
  useradd -m -s /bin/bash -G sudo ${userName}
  echo "${userName} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# ========== 安装 Bench ==========
su - ${userName} <<EOF
pip3 install --upgrade pip setuptools
pip3 install frappe-bench
EOF

# ========== 初始化 Frappe Bench ==========
su - ${userName} <<EOF
echo "=================== 初始化 Frappe Bench ==================="
cd ～
for i in {1..5}; do
  rm -rf ～/${installDir}
  set +e
  bench init --frappe-branch ${frappeBranch} --python /usr/bin/python3 ${installDir}
  err=\$?
  set -e
  if [[ \$err -eq 0 ]]; then
    break
  elif [[ \$i -ge 5 ]]; then
    echo "Frappe 初始化失败超过 5 次，退出！"
    exit 1
  else
    echo "Frappe 初始化第 \$i 次失败，重试..."
    sleep 10
  fi
done
EOF

# ========== 获取 ERPNext 应用 ==========
su - ${userName} <<EOF
cd ～/${installDir}
bench get-app --branch ${erpnextBranch} erpnext ${erpnextPath}
bench get-app payments
bench get-app print_designer
EOF

# ========== 创建站点（关键：指定外部 DB host）==========
su - ${userName} <<EOF
cd ～/${installDir}
echo "=================== 创建站点（连接外部数据库）==================="
bench new-site \
  --mariadb-root-password "${mariadbRootPassword}" \
  --db-host "${mariadbHost}" \
  --db-port "${mariadbPort}" \
  --admin-password "${adminPassword}" \
  --verbose \
  "${siteName}"
EOF

# ========== 安装应用到站点 ==========
su - ${userName} <<EOF
cd ～/${installDir}
bench --site "${siteName}" install-app erpnext
bench --site "${siteName}" install-app payments
bench --site "${siteName}" install-app print_designer
EOF

# ========== 设置中文（可选）==========
su - ${userName} <<EOF
cd ～/${installDir}
bench --site "${siteName}" set-config lang zh
EOF

# ========== 启用生产模式 ==========
if [[ "${productionMode}" == "yes" ]]; then
  su - ${userName} <<EOF
cd ～/${installDir}
sudo bench setup production ${userName}
EOF
fi

echo "✅ ERPNext 15 安装完成！"
echo "   - 管理员账号: admin / jiangbn6"
echo "   - 数据库主机: ${mariadbHost}:${mariadbPort}"
echo "   - 站点名称: ${siteName}"
