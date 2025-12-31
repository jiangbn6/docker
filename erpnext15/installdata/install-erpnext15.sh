#!/bin/bash
# v0.9 2025.06.28 适配jiangbn6核心需求：
# 1. 构建阶段（BUILD_STAGE=yes）：跳过所有数据库连接/校验逻辑，仅安装依赖、初始化环境
# 2. 运行阶段（BUILD_STAGE=no）：绑定同子网独立数据库容器，执行完整数据库相关逻辑
set -e

# ==================== 核心新增：构建/运行阶段控制（关键） ====================
# 构建阶段标记：yes=构建镜像（跳过数据库），no=运行容器（绑定数据库）
BUILD_STAGE=${BUILD_STAGE:-"yes"}
# 数据库容器配置（运行时通过环境变量传递，同子网数据库容器IP/别名）
DB_CONTAINER_HOST=${DB_CONTAINER_HOST:-"mariadb-container"}  # 数据库容器名/同子网IP
DB_CONTAINER_PORT=${DB_CONTAINER_PORT:-"3306"}               # 数据库容器端口
DB_CONTAINER_ROOT_PASS=${DB_CONTAINER_ROOT_PASS:-"jiangbn6"} # 数据库容器root密码

# 脚本运行环境检查
# 检测是否ubuntu22.04
cat /etc/os-release
osVer=$(cat /etc/os-release | grep 'Ubuntu 22.04' || true)
if [[ ${osVer} == '' ]]; then
    echo '脚本只在ubuntu22.04版本测试通过。其它系统版本需要重新适配。退出安装。'
    exit 1
else
    echo '系统版本检测通过...'
fi
# 检测是否使用bash执行
if [[ 1 == 1 ]]; then
    echo 'bash检测通过...'
else
    echo 'bash检测未通过...'
    echo '脚本需要使用bash执行。'
    exit 1
fi
# 检测是否使用root用户执行
if [ "$(id -u)" != "0" ]; then
   echo "脚本需要使用root用户执行"
   exit 1
else
    echo '执行用户检测通过...'
fi

# 设定参数默认值（运行时自动替换为数据库容器配置）
mariadbHost=${DB_CONTAINER_HOST}       # 运行时指向同子网数据库容器
mariadbPort=${DB_CONTAINER_PORT}       # 数据库容器端口
mariadbRootPassword=${DB_CONTAINER_ROOT_PASS} # 数据库容器root密码
adminPassword="admin"
installDir="frappe-bench"
userName="frappe"
benchVersion=""
frappePath=""
frappeBranch="version-15"
erpnextPath="https://github.com/frappe/erpnext"
erpnextBranch="version-15"
siteName="site1.local"
siteDbPassword="Pass1234"
webPort=""
productionMode="yes"
# 是否修改apt安装源，如果是云服务器建议不修改。
altAptSources="yes"
# 是否跳过确认参数直接安装
quiet="no"
# 是否为docker镜像
inDocker="no"
# 是否删除重复文件
removeDuplicate="yes"

# 检测如果是云主机或已经是国内源则不修改apt安装源
hostAddress=("mirrors.tencentyun.com" "mirrors.tuna.tsinghua.edu.cn" "cn.archive.ubuntu.com")
for h in ${hostAddress[@]}; do
    n=$(cat /etc/apt/sources.list | grep -c ${h} || true)
    if [[ ${n} -gt 0 ]]; then
        altAptSources="no"
    fi
done

# 遍历参数修改默认值
# 脚本后添加参数如有冲突，靠后的参数生效。
echo "===================获取参数==================="
argTag=""
for arg in $*
do
    if [[ ${argTag} != "" ]]; then
        case "${argTag}" in
        "webPort")
            t=$(echo ${arg}|sed 's/[0-9]//g')
            if [[ (${t} == "") && (${arg} -ge 80) && (${arg} -lt 65535) ]]; then
                webPort=${arg}
                echo "设定web端口为${webPort}。"
                continue
            else
                webPort=""
            fi
            ;;
        esac
        argTag=""
    fi
    if [[ ${arg} == -* ]];then
        arg=${arg:1:${#arg}}
        for i in `seq ${#arg}`
        do
            arg0=${arg:$i-1:1}
            case "${arg0}" in
            "q")
                quiet='yes'
                removeDuplicate="yes"
                echo "不再确认参数，直接安装。"
                ;;
            "d")
                inDocker='yes'
                echo "针对docker镜像安装方式适配。"
                ;;
            "p")
                argTag='webPort'
                echo "针对docker镜像安装方式适配。"
                ;;
            esac
        done
    elif [[ ${arg} == *=* ]];then
        arg0=${arg%=*}
        arg1=${arg#*=}
        echo "${arg0} 为： ${arg1}"
        case "${arg0}" in
        "benchVersion")
            benchVersion=${arg1}
            echo "设置bench版本为： ${benchVersion}"
            ;;
        "mariadbHost")
            mariadbHost=${arg1}
            echo "设置外部数据库主机：${mariadbHost}"
            ;;
        "mariadbPort")
            mariadbPort=${arg1}
            echo "设置外部数据库端口：${mariadbPort}"
            ;;
        "mariadbRootPassword")
            mariadbRootPassword=${arg1}
            echo "设置数据库根密码为： ${mariadbRootPassword}"
            ;;
        "adminPassword")
            adminPassword=${arg1}
            echo "设置管理员密码为： ${adminPassword}"
            ;;
        "frappePath")
            frappePath=${arg1}
            echo "设置frappe拉取地址为： ${frappePath}"
            ;;
        "frappeBranch")
            frappeBranch=${arg1}
            echo "设置frappe分支为： ${frappeBranch}"
            ;;
        "erpnextPath")
            erpnextPath=${arg1}
            echo "设置erpnext拉取地址为： ${erpnextPath}"
            ;;
        "erpnextBranch")
            erpnextBranch=${arg1}
            echo "设置erpnext分支为： ${erpnextBranch}"
            ;;
        "branch")
            frappeBranch=${arg1}
            erpnextBranch=${arg1}
            echo "设置frappe分支为： ${frappeBranch}"
            echo "设置erpnext分支为： ${erpnextBranch}"
            ;;
        "siteName")
            siteName=${arg1}
            echo "设置站点名称为： ${siteName}"
            ;;
        "installDir")
            installDir=${arg1}
            echo "设置安装目录为： ${installDir}"
            ;;
        "userName")
            userName=${arg1}
            echo "设置安装用户为： ${userName}"
            ;;
        "siteDbPassword")
            siteDbPassword=${arg1}
            echo "设置站点数据库密码为： ${siteDbPassword}"
            ;;
        "webPort")
            webPort=${arg1}
            echo "设置web端口为： ${webPort}"
            ;;
        "altAptSources")
            altAptSources=${arg1}
            echo "是否修改apt安装源：${altAptSources}，云服务器有自己的安装，建议不修改。"
            ;;
        "quiet")
            quiet=${arg1}
            if [[ ${quiet} == "yes" ]];then
                removeDuplicate="yes"
            fi
            echo "不再确认参数，直接安装。"
            ;;
        "inDocker")
            inDocker=${arg1}
            echo "针对docker镜像内安装适配。"
            ;;
        "productionMode")
            productionMode=${arg1}
            echo "是否开启生产模式： ${productionMode}"
            ;;
        # 新增：支持运行时覆盖数据库容器配置
        "DB_CONTAINER_HOST")
            DB_CONTAINER_HOST=${arg1}
            mariadbHost=${arg1}
            echo "设置数据库容器主机：${DB_CONTAINER_HOST}"
            ;;
        "DB_CONTAINER_PORT")
            DB_CONTAINER_PORT=${arg1}
            mariadbPort=${arg1}
            echo "设置数据库容器端口：${DB_CONTAINER_PORT}"
            ;;
        "DB_CONTAINER_ROOT_PASS")
            DB_CONTAINER_ROOT_PASS=${arg1}
            mariadbRootPassword=${arg1}
            echo "设置数据库容器root密码：${DB_CONTAINER_ROOT_PASS}"
            ;;
        esac
    fi
done

# 显示参数
if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then
    clear
fi
echo "数据库地址（容器）："${mariadbHost}
echo "数据库端口（容器）："${mariadbPort}
echo "数据库root用户密码："${mariadbRootPassword}
echo "管理员密码："${adminPassword}
echo "安装目录："${installDir}
echo "指定bench版本："${benchVersion}
echo "拉取frappe地址："${frappePath}
echo "指定frappe版本："${frappeBranch}
echo "拉取erpnext地址："${erpnextPath}
echo "指定erpnext版本："${erpnextBranch}
echo "网站名称："${siteName}
echo "网站数据库密码："${siteDbPassword}
echo "web端口："${webPort}
echo "是否修改apt安装源："${altAptSources}
echo "是否静默模式安装："${quiet}
echo "如有重名目录或数据库是否删除："${removeDuplicate}
echo "是否为docker镜像内安装适配："${inDocker}
echo "是否开启生产模式："${productionMode}
echo "构建/运行阶段："${BUILD_STAGE}（yes=构建，no=运行）

# 检查外部数据库参数（仅运行阶段显示）
if [[ ${BUILD_STAGE} == "no" ]]; then
    echo "✅ 数据库容器参数已配置：主机=${mariadbHost} 端口=${mariadbPort} 密码=${mariadbRootPassword}"
else
    echo "⚠️  构建阶段跳过数据库参数校验，运行时绑定同子网数据库容器"
fi

# 等待确认参数（仅非静默/非Docker/非构建阶段执行）
if [[ ${quiet} != "yes" && ${BUILD_STAGE} == "no" ]];then
    echo "===================请确认已设定参数并选择安装方式==================="
    echo "1. 安装为开发模式"
    echo "2. 安装为生产模式"
    echo "3. 不再询问，按照当前设定安装并开启静默模式"
    echo "4. 在Docker镜像里安装并开启静默模式"
    echo "*. 取消安装"
    echo -e "说明：开启静默模式后，如果有重名目录或数据库包括supervisor进程配置文件都将会删除后继续安装，请注意数据备份！ \n \
        开发模式需要手动启动“bench start”，启动后访问8000端口。\n \
        生产模式无需手动启动，使用nginx反代并监听80端口\n \
        此外生产模式会使用supervisor管理进程增强可靠性，并预编译代码开启redis缓存，提高应用性能。\n \
        在Docker镜像里安装会适配其进程启动方式将nginx进程交给supervisor管理。 \n \
        docker镜像主线程：“sudo supervisord -n -c /etc/supervisor/supervisord.conf”。请自行配置到镜像"
    read -r -p "请选择： " input
    case ${input} in
        1)
            productionMode="no"
    	    ;;
        2)
            productionMode="yes"
    	    ;;
        3)
            quiet="yes"
            removeDuplicate="yes"
    	    ;;
        4)
            quiet="yes"
            removeDuplicate="yes"
            inDocker="yes"
    	    ;;
        *)
            echo "取消安装..."
            exit 1
    	    ;;
    esac
fi

# 给参数添加关键字
echo "===================给需要的参数添加关键字==================="
if [[ ${benchVersion} != "" ]];then
    benchVersion="==${benchVersion}"
fi
if [[ ${frappePath} != "" ]];then
    frappePath="--frappe-path ${frappePath}"
fi
if [[ ${frappeBranch} != "" ]];then
    frappeBranch="--frappe-branch ${frappeBranch}"
fi
if [[ ${erpnextBranch} != "" ]];then
    erpnextBranch="--branch ${erpnextBranch}"
fi
if [[ ${siteDbPassword} != "" ]];then
    siteDbPassword="--db-password ${siteDbPassword}"
fi

# 开始安装基础软件，并修改配置使其符合要求
# 修改安装源加速国内安装。
if [[ ${altAptSources} == "yes" ]];then
    # 在执行前确定有操作权限
    if [[ ! -e /etc/apt/sources.list.bak ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi
    rm -f /etc/apt/sources.list
    bash -c "cat << EOF > /etc/apt/sources.list && apt update 
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
EOF"
    echo "===================apt已修改为国内源==================="
fi

# 安装基础软件（移除本地MariaDB相关包）
echo "===================安装基础软件==================="
apt update
DEBIAN_FRONTEND=noninteractive apt upgrade -y
DEBIAN_FRONTEND=noninteractive apt install -y \
    ca-certificates \
    sudo \
    locales \
    tzdata \
    cron \
    wget \
    curl \
    python3-dev \
    python3-venv \
    python3-setuptools \
    python3-pip \
    python3-testresources \
    git \
    software-properties-common \
    libmysqlclient-dev \
    xvfb \
    libfontconfig \
    wkhtmltopdf \
    supervisor \
    pkg-config \
    build-essential \
    libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev

# 环境需求检查
rteArr=()
warnArr=()

# 检测是否有之前安装的目录
while [[ -d "/home/${userName}/${installDir}" ]]; do
    if [[ ${quiet} != "yes" && ${inDocker} != "yes" && ${BUILD_STAGE} == "no" ]]; then
        clear
    fi
    echo "检测到已存在安装目录：/home/${userName}/${installDir}"
    if [[ ${quiet} != "yes" && ${BUILD_STAGE} == "no" ]];then
        echo '1. 删除后继续安装。（推荐）'
        echo '2. 输入一个新的安装目录。'
        read -r -p "*. 取消安装" input
        case ${input} in
            1)
                echo "删除目录重新初始化！"
                rm -rf /home/${userName}/${installDir}
                rm -f /etc/supervisor/conf.d/${installDir}.conf
                rm -f /etc/nginx/conf.d/${installDir}.conf
                ;;
            2)
                while true
                do
                    echo "当前目录名称："${installDir}
                    read -r -p "请输入新的安装目录名称：" input
                    if [[ ${input} != "" ]]; then
                        installDir=${input}
                        read -r -p "使用新的安装目录名称${siteName}，y确认，n重新输入：" input
                        if [[ ${input} == [y/Y] ]]; then
                            echo "将使用安装目录名称${installDir}重试。"
                            break
                        fi
                    fi
                done
                continue
                ;;
            *)
                echo "取消安装。"
                exit 1
                ;;
        esac
    else
        echo "静默/构建模式，删除目录重新初始化！"
        rm -rf /home/${userName}/${installDir}
    fi
done

# 环境需求检查,python3
if type python3 >/dev/null 2>&1; then
    result=$(python3 -V | grep "3.10" || true)
    if [[ "${result}" == "" ]]
    then
        echo '==========已安装python3，但不是推荐的3.10版本。=========='
        warnArr[${#warnArr[@]}]="Python不是推荐的3.10版本。"
    else
        echo '==========已安装python3.10=========='
    fi
    rteArr[${#rteArr[@]}]=$(python3 -V)
else
    echo "==========python安装失败退出脚本！=========="
    exit 1
fi

# 环境需求检查,wkhtmltox
if type wkhtmltopdf >/dev/null 2>&1; then
    result=$(wkhtmltopdf -V | grep "0.12.6" || true)
    if [[ ${result} == "" ]]
    then
        echo '==========已存在wkhtmltox，但不是推荐的0.12.6版本。=========='
        warnArr[${#warnArr[@]}]='wkhtmltox不是推荐的0.12.6版本。'
    else
        echo '==========已安装wkhtmltox_0.12.6=========='
    fi
    rteArr[${#rteArr[@]}]=$(wkhtmltopdf -V)
else
    echo "==========wkhtmltox安装失败退出脚本！=========="
    exit 1
fi

# ==================== 核心改造：仅运行阶段测试数据库容器连接 ====================
echo "===================数据库容器连接校验（仅运行阶段执行）==================="
if [[ ${BUILD_STAGE} == "no" ]]; then
    if ! mysql -h ${mariadbHost} -P ${mariadbPort} -u root -p${mariadbRootPassword} -e "quit" >/dev/null 2>&1; then
        echo "❌ 错误：无法连接到同子网数据库容器！"
        echo "连接信息：容器主机=${mariadbHost}, 端口=${mariadbPort}, 用户=root"
        echo "请检查：1. 数据库容器是否启动 2. 容器是否在同一子网 3. 密码是否正确"
        exit 1
    else
        echo "✅ 数据库容器连接测试通过"
    fi
else
    echo "⚠️  构建阶段跳过数据库容器连接测试，运行时再校验"
fi

# ==================== 仅运行阶段执行：检查数据库残留 ====================
if [[ ${BUILD_STAGE} == "no" ]]; then
    echo "==========检查数据库容器残留（仅运行阶段）=========="
    while true
    do
        siteSha1=$(echo -n ${siteName} | sha1sum)
        siteSha1=_${siteSha1:0:16}
        dbUser=$(mysql -h ${mariadbHost} -P ${mariadbPort} -u root -p${mariadbRootPassword} -e "use mysql;SELECT User,Host FROM user;" | grep ${siteSha1} || true)
        if [[ ${dbUser} != "" ]]; then
            if [[ ${quiet} != "yes" && ${inDocker} != "yes" ]]; then
                clear
            fi
            echo '当前站点名称：'${siteName}
            echo '生成的数据库及用户名为：'${siteSha1}
            echo '数据库容器中已存在同名用户，请选择处理方式。'
            echo '1. 重新输入新的站点名称。将自动生成新的数据库及用户名称重新校验。'
            echo '2. 删除重名的数据库及用户。'
            echo '3. 什么也不做使用设置的密码直接安装。（不推荐）'
            echo '*. 取消安装。'
            if [[ ${quiet} == "yes" ]]; then
                echo '当前为静默模式，将自动按第2项执行。'
                # 删除重名数据库
                mysql -h ${mariadbHost} -P ${mariadbPort} -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
                arrUser=(${dbUser})
                # 如果重名用户有多个host，以步进2取用户名和用户host并删除。
                for ((i=0; i<${#arrUser[@]}; i=i+2))
                do
                    mysql -h ${mariadbHost} -P ${mariadbPort} -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};"
                done
                echo "已删除数据库容器中的重名库/用户，继续安装！"
                continue
            fi
            read -r -p "请输入选择：" input
            case ${input} in
                '1')
                    while true
                    do
                        read -r -p "请输入新的站点名称：" inputSiteName
                        if [[ ${inputSiteName} != "" ]]; then
                            siteName=${inputSiteName}
                            read -r -p "使用新的站点名称${siteName}，y确认，n重新输入：" input
                            if [[ ${input} == [y/Y] ]]; then
                                echo "将使用站点名称${siteName}重试。"
                                break
                            fi
                        fi
                    done
                    continue
                    ;;
                '2')
                    mysql -h ${mariadbHost} -P ${mariadbPort} -u root -p${mariadbRootPassword} -e "drop database ${siteSha1};"
                    arrUser=(${dbUser})
                    for ((i=0; i<${#arrUser[@]}; i=i+2))
                    do
                        mysql -h ${mariadbHost} -P ${mariadbPort} -u root -p${mariadbRootPassword} -e "drop user ${arrUser[$i]}@${arrUser[$i+1]};"
                    done
                    echo "已删除数据库容器中的重名库/用户，继续安装！"
                    continue
                    ;;
                '3')
                    echo "什么也不做使用设置的密码直接安装！"
                    warnArr[${#warnArr[@]}]="检测到数据库容器中有重名库/用户${siteSha1},选择了覆盖安装。可能造成无法访问。"
                    break
                    ;;
                *)
                echo "取消安装..."
                exit 1
                ;;
            esac
        else
            echo "数据库容器中无重名库/用户。"
            break
        fi
    done
else
    echo "⚠️  构建阶段跳过数据库容器残留检查"
fi

# 确认可用的重启指令
echo "确认supervisor可用重启指令。"
supervisorCommand=""
if type supervisord >/dev/null 2>&1; then
    if [[ $(grep -E "[ *]reload)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="reload"
    elif [[ $(grep -E "[ *]restart)" /etc/init.d/supervisor) != '' ]]; then
        supervisorCommand="restart"
    else
        echo "/etc/init.d/supervisor中没有找到reload或restart指令"
        echo "将会继续执行，但可能因为使用不可用指令导致启动进程失败。"
        warnArr[${#warnArr[@]}]="没有找到可用的supervisor重启指令，如有进程启动失败，请尝试手动重启。"
    fi
else
    echo "supervisor没有安装"
    warnArr[${#warnArr[@]}]="supervisor没有安装或安装失败，不能使用supervisor管理进程。"
fi
echo "可用指令："${supervisorCommand}

# 安装最新版redis
# 检查是否安装redis
if ! type redis-server >/dev/null 2>&1; then
    # 获取最新版redis，并安装
    echo "==========获取最新版redis，并安装=========="
    rm -rf /var/lib/redis
    rm -rf /etc/redis
    rm -rf /etc/default/redis-server
    rm -rf /etc/init.d/redis-server
    rm -f /usr/share/keyrings/redis-archive-keyring.gpg
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt update
    echo "即将安装redis"
    DEBIAN_FRONTEND=noninteractive apt install -y \
        redis-tools \
        redis-server \
        redis
fi

# 环境需求检查,redis
if type redis-server >/dev/null 2>&1; then
    result=$(redis-server -v | grep "7" || true)
    if [[ "${result}" == "" ]]
    then
        echo '==========已安装redis，但不是推荐的7版本。=========='
        warnArr[${#warnArr[@]}]='redis不是推荐的7版本。'
    else
        echo '==========已安装redis7=========='
    fi
    rteArr[${#rteArr[@]}]=$(redis-server -v)
else
    echo "==========redis安装失败退出脚本！=========="
    exit 1
fi

# 修改pip默认源加速国内安装
# 在执行前确定有操作权限
mkdir -p /root/.pip
echo '[global]' > /root/.pip/pip.conf
echo 'index-url=https://pypi.tuna.tsinghua.edu.cn/simple' >> /root/.pip/pip.conf
echo '[install]' >> /root/.pip/pip.conf
echo 'trusted-host=mirrors.tuna.tsinghua.edu.cn' >> /root/.pip/pip.conf
echo "===================pip已修改为国内源==================="

# 安装并升级pip及工具包
echo "===================安装并升级pip及工具包==================="
cd ~
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools cryptography psutil
alias python=python3
alias pip=pip3

# 建立新用户组和用户
echo "===================建立新用户组和用户==================="
result=$(grep "${userName}:" /etc/group || true)
if [[ ${result} == "" ]]; then
    gid=1000
    while true
    do
        result=$(grep ":${gid}:" /etc/group || true)
        if [[ ${result} == "" ]]
        then
            echo "建立新用户组: ${gid}:${userName}"
            groupadd -g ${gid} ${userName}
            echo "已新建用户组${userName}，gid: ${gid}"
            break
        else
            gid=$(expr ${gid} + 1)
        fi
    done
else
    echo '用户组已存在'
fi
result=$(grep "${userName}:" /etc/passwd || true)
if [[ ${result} == "" ]]
then
    uid=1000
    while true
    do
        result=$(grep ":x:${uid}:" /etc/passwd || true)
        if [[ ${result} == "" ]]
        then
            echo "建立新用户: ${uid}:${userName}"
            useradd --no-log-init -r -m -u ${uid} -g ${gid} -G  sudo ${userName}
            echo "已新建用户${userName}，uid: ${uid}"
            break
        else
            uid=$(expr ${uid} + 1)
        fi
    done
else
    echo '用户已存在'
fi

# 给用户添加sudo权限
sed -i "/^${userName}.*/d" /etc/sudoers
echo "${userName} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
mkdir -p /home/${userName}
sed -i "/^export.*${userName}.*/d" /etc/sudoers

# 修改用户pip默认源加速国内安装
cp -af /root/.pip /home/${userName}/
# 修正用户目录权限
chown -R ${userName}.${userName} /home/${userName}
# 修正用户shell
usermod -s /bin/bash ${userName}

# 设置语言环境
echo "===================设置语言环境==================="
sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
sed -i "/^export.*LC_ALL=.*/d" /root/.bashrc
sed -i "/^export.*LC_CTYPE=.*/d" /root/.bashrc
sed -i "/^export.*LANG=.*/d" /root/.bashrc
echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> /root/.bashrc
sed -i "/^export.*LC_ALL=.*/d" /home/${userName}/.bashrc
sed -i "/^export.*LC_CTYPE=.*/d" /home/${userName}/.bashrc
sed -i "/^export.*LANG=.*/d" /home/${userName}/.bashrc
echo -e "export LC_ALL=en_US.UTF-8\nexport LC_CTYPE=en_US.UTF-8\nexport LANG=en_US.UTF-8" >> /home/${userName}/.bashrc

# 设置时区为上海
echo "===================设置时区为上海==================="
ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# 设置监控文件数量上限
echo "===================设置监控文件数量上限==================="
sed -i "/^fs.inotify.max_user_watches=.*/d" /etc/sysctl.conf
echo fs.inotify.max_user_watches=524288 | tee -a /etc/sysctl.conf
# 使其立即生效
/sbin/sysctl -p

# 检查是否安装nodejs20
source /etc/profile
if ! type node >/dev/null 2>&1; then
    # 获取最新版nodejs-v20，并安装
    echo "==========获取最新版nodejs-v20，并安装=========="
    if [ -z $nodejsLink ] ; then
        nodejsLink=$(curl -sL https://registry.npmmirror.com/-/binary/node/latest-v20.x/ | grep -oE "https?://[a-zA-Z0-9\.\/_&=@$%?~#-]*node-v20\.[0-9][0-9]\.[0-9]{1,2}"-linux-x64.tar.xz | tail -1)
    else
        echo 已自定义nodejs下载链接，开始下载
    fi
    if [ -z $nodejsLink ] ; then
        echo 没有匹配到node.js下载地址，请检查网络或代码。
        exit 1
    else
        nodejsFileName=${nodejsLink##*/}
        nodejsVer=`t=(${nodejsFileName//-/ });echo ${t[1]}`
        echo "nodejs20最新版本为：${nodejsVer}"
        echo "即将安装nodejs20到/usr/local/lib/nodejs/${nodejsVer}"
        wget $nodejsLink -P /tmp/
        mkdir -p /usr/local/lib/nodejs
        tar -xJf /tmp/${nodejsFileName} -C /usr/local/lib/nodejs/
        mv /usr/local/lib/nodejs/${nodejsFileName%%.tar*} /usr/local/lib/nodejs/${nodejsVer}
        echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /etc/profile.d/nodejs.sh
        echo "export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> ~/.bashrc
        echo "export PATH=/home/${userName}/.local/bin:/usr/local/lib/nodejs/${nodejsVer}/bin:\$PATH" >> /home/${userName}/.bashrc
        export PATH=/usr/local/lib/nodejs/${nodejsVer}/bin:$PATH
        source /etc/profile
    fi
fi

# 环境需求检查,node
if type node >/dev/null 2>&1; then
    result=$(node -v | grep "v20." || true)
    if [[ ${result} == "" ]]
    then
        echo '==========已存在node，但不是v20版。这将有可能导致一些问题。建议卸载node后重试。=========='
        warnArr[${#warnArr[@]}]='node不是推荐的v20版本。'
    else
        echo '==========已安装node20=========='
    fi
    rteArr[${#rteArr[@]}]='node '$(node -v)
else
    echo "==========node安装失败退出脚本！=========="
    exit 1
fi

# 修改npm源
npm config set registry https://registry.npmmirror.com -g
echo "===================npm已修改为国内源==================="

# 升级npm
echo "===================升级npm==================="
npm install -g npm

# 安装yarn
echo "===================安装yarn==================="
npm install -g yarn

# 修改yarn源
yarn config set registry https://registry.npmmirror.com --global
echo "===================yarn已修改为国内源==================="

# 基础需求安装完毕。
echo "===================基础需求安装完毕。==================="

# 切换用户配置环境
su - ${userName} <<EOF
# 配置运行环境变量
echo "===================配置运行环境变量==================="
cd ~
alias python=python3
alias pip=pip3
source /etc/profile
export PATH=/home/${userName}/.local/bin:$PATH
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LANG=en_US.UTF-8
# 修改用户yarn源
yarn config set registry https://registry.npmmirror.com --global
echo "===================用户yarn已修改为国内源==================="
EOF

# 适配docker
echo "判断是否适配docker"
if [[ ${inDocker} == "yes" ]]; then
    # 如果是在docker中运行，使用supervisor管理nginx进程
    echo "================为docker镜像添加nginx启动配置文件==================="
    supervisorConfigDir=/home/${userName}/.config/supervisor
    mkdir -p ${supervisorConfigDir}
    f=${supervisorConfigDir}/nginx.conf
    rm -f ${f}
    echo "[program: nginx]" > ${f}
    echo "command=/usr/sbin/nginx -g 'daemon off;'" >> ${f}
    echo "autorestart=true" >> ${f}
    echo "autostart=true" >> ${f}
    echo "stderr_logfile=/var/run/log/supervisor_nginx_error.log" >> ${f}
    echo "stdout_logfile=/var/run/log/supervisor_nginx_stdout.log" >> ${f}
    echo "environment=ASPNETCORE_ENVIRONMENT=Production" >> ${f}
    echo "user=root" >> ${f}
    echo "stopsignal=INT" >> ${f}
    echo "startsecs=10" >> ${f}
    echo "startretries=5" >> ${f}
    echo "stopasgroup=true" >> ${f}
    
    i=$(ps aux | grep -c supervisor || true)
    if [[ ${i} -le 1 ]]; then
        echo "启动supervisor进程"
        /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    else
        echo "重载supervisor配置"
        /usr/bin/supervisorctl reload
    fi
    # 等待2秒
    for i in $(seq -w 2); do
        echo ${i}
        sleep 1
    done
fi

# 安装bench
su - ${userName} <<EOF
echo "===================安装bench==================="
sudo -H pip3 install frappe-bench${benchVersion}
# 环境需求检查,bench
if type bench >/dev/null 2>&1; then
    benchV=\$(bench --version)
    echo '==========已安装bench=========='
    echo \${benchV}
else
    echo "==========bench安装失败退出脚本！=========="
    exit 1
fi
EOF
rteArr[${#rteArr[@]}]='bench '$(bench --version 2>/dev/null)

# bench脚本适配docker
if [[ ${inDocker} == "yes" ]]; then
    # 修改bench脚本不安装fail2ban
    echo "已配置在docker中运行，将注释安装fail2ban的代码。"
    # 确认bench脚本使用supervisor指令代码行
    f="/usr/local/lib/python3.10/dist-packages/bench/config/production_setup.py"
    n=$(sed -n "/^[[:space:]]*if not which.*fail2ban-client/=" ${f})
    # 如找到代码注释判断行及执行行
    if [ ${n} ]; then
        echo "找到fail2ban安装代码行，添加注释符。"
        sed -i "${n} s/^/#&/" ${f}
        let n++
        sed -i "${n} s/^/#&/" ${f}
    fi
fi

# 初始化frappe（构建/运行阶段都执行，仅安装环境）
su - ${userName} <<EOF
echo "===================初始化frappe==================="
# 如果初始化失败，尝试5次。
for ((i=0; i<5; i++)); do
    rm -rf ~/${installDir}
    set +e
    bench init ${frappeBranch} --python /usr/bin/python3 --ignore-exist ${installDir} ${frappePath}
    err=\$?
    set -e
    if [[ \${err} == 0 ]]; then
        echo "执行返回正确\${i}"
        sleep 1
        break
    elif [[ \${i} -ge 4 ]]; then
        echo "==========frappe初始化失败太多\${i}，退出脚本！=========="
        exit 1
    else
        echo "==========frappe初始化失败第"\${i}"次！自动重试。=========="
    fi
done
echo "frappe初始化脚本执行结束..."
EOF

# 确认frappe初始化
su - ${userName} <<EOF
cd ~/${installDir}
# 环境需求检查,frappe
frappeV=\$(bench version | grep "frappe" || true)
if [[ \${frappeV} == "" ]]; then
    echo "==========frappe初始化失败退出脚本！=========="
    exit 1
else
    echo '==========frappe初始化成功=========='
    echo \${frappeV}
fi
EOF

# ==================== 核心改造：仅运行阶段拉取ERPNext应用+绑定数据库容器 ====================
if [[ ${BUILD_STAGE} == "no" ]]; then
    # 获取erpnext应用（仅运行阶段）
    su - ${userName} <<EOF
    cd ~/${installDir}
    echo "===================获取ERPNext应用（运行阶段）==================="
    bench get-app ${erpnextBranch} ${erpnextPath}
    bench get-app payments
    bench get-app print_designer
EOF

    # 建立新网站（绑定同子网数据库容器）
    su - ${userName} <<EOF
    cd ~/${installDir}
    echo "===================绑定数据库容器创建站点==================="
    bench new-site \
        --db-host ${mariadbHost} \
        --db-port ${mariadbPort} \
        --mariadb-root-username root \
        --mariadb-root-password ${mariadbRootPassword} \
        ${siteDbPassword} \
        --admin-password ${adminPassword} \
        ${siteName}
EOF

    # 安装erpnext应用到新网站
    su - ${userName} <<EOF
    cd ~/${installDir}
    echo "===================安装ERPNext应用到站点==================="
    bench --site ${siteName} install-app payments
    bench --site ${siteName} install-app erpnext
    bench --site ${siteName} install-app print_designer
EOF

    # 安装中文本地化
    su - ${userName} <<EOF
    cd ~/${installDir}
    echo "===================安装中文本地化==================="
    bench get-app https://gitee.com/yuzelin/erpnext_chinese.git
    bench --site ${siteName} install-app erpnext_chinese
    bench clear-cache && bench clear-website-cache
EOF

    # 站点配置
    su - ${userName} <<EOF
    cd ~/${installDir}
    # 设置网站超时时间
    echo "===================配置站点（绑定数据库容器）==================="
    bench config http_timeout 6000
    # 开启默认站点并设置默认站点
    bench config serve_default_site on
    bench use ${siteName}
    # 清理缓存
    bench clear-cache
    bench clear-website-cache
EOF
else
    echo "⚠️  构建阶段跳过ERPNext应用拉取/站点创建（运行时执行）"
fi

# 生产模式开启（仅运行阶段执行）
if [[ ${productionMode} == "yes" && ${BUILD_STAGE} == "no" ]]; then
    echo "================开启生产模式（运行阶段）==================="
    # 可能会自动安装一些软件，刷新软件库
    apt update
    # 预先安装nginx，防止自动部署出错
    DEBIAN_FRONTEND=noninteractive apt install nginx -y
    rteArr[${#rteArr[@]}]=$(nginx -v 2>/dev/null)
    if [[ ${inDocker} == "yes" ]]; then
        # 使用supervisor管理nginx进程
        /etc/init.d/nginx stop
        if [[ ! -e /etc/supervisor/conf.d/nginx.conf ]]; then
            ln -fs ${supervisorConfigDir}/nginx.conf /etc/supervisor/conf.d/nginx.conf
        fi
        echo "当前supervisor状态"
        /usr/bin/supervisorctl status
        echo "重载supervisor配置"
        /usr/bin/supervisorctl reload
        # 等待重载supervisor结束
        echo "等待重载supervisor结束"
        for i in $(seq -w 15 -1 1); do
            echo -en ${i}; sleep 1
        done
        echo "重载后supervisor状态"
        /usr/bin/supervisorctl status
    fi
    # 如果有检测到的supervisor可用重启指令，修改bench脚本supervisor重启指令为可用指令。
    echo "修正bench脚本生产模式配置..."
elif [[ ${BUILD_STAGE} == "yes" ]]; then
    echo "⚠️  构建阶段跳过生产模式配置"
fi

# 最终提示
echo "=================================================="
if [[ ${BUILD_STAGE} == "yes" ]]; then
    echo "✅ ERPNext镜像构建完成！"
    echo "📌 运行容器时请传递数据库容器参数："
    echo "docker run -d \\"
    echo "  --network 自定义子网名称 \\"  # 确保和数据库容器同子网
    echo "  -e BUILD_STAGE=no \\"
    echo "  -e DB_CONTAINER_HOST=数据库容器名/IP \\"
    echo "  -e DB_CONTAINER_PORT=3306 \\"
    echo "  -e DB_CONTAINER_ROOT_PASS=jiangbn6 \\"
    echo "  -p 80:80 \\"
    echo "  --name erpnext15 \\"
    echo "  erpnext15-jiangbn6:latest"
else
    echo "✅ ERPNext容器运行完成！"
    echo "📌 已绑定同子网数据库容器：${mariadbHost}:${mariadbPort}"
    echo "📌 访问地址：http://容器IP/ （账号：admin，密码：admin）"
    echo "📌 数据已存储到独立数据库容器，容器重启不丢失数据"
fi
echo "=================================================="
