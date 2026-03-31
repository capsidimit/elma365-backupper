#!/bin/bash
# ELMA backupper version: 1.0.17
# This script is responsible for parsing arguments and setting up environment variables for the backupper script.


#region Logging functions
GLOBAL_LOG_LEVEL="INFO"
declare -r -A LOG_LEVEL_VAL=(
    ["ERROR"]=3
    ["WARNING"]=4
    ["INFO"]=6
    ["SUCCESS"]=7
    ["DEBUG"]=7
)
declare -r LOG_DEFAULT_COLOR="\033[0m"
declare -r LOG_ERROR_COLOR="\033[1;31m"
declare -r LOG_INFO_COLOR="\033[1m"
declare -r LOG_SUCCESS_COLOR="\033[1;32m"
declare -r LOG_WARN_COLOR="\033[1;33m"
declare -r LOG_DEBUG_COLOR="\033[1;34m"

log() {
    local log_text="$1"
    local log_level="$2"
    local log_color="$3"

    # Default level to "info"
    [[ -z ${log_level} ]] && log_level="INFO";
    [[ -z ${log_color} ]] && log_color="${LOG_INFO_COLOR}";

    if [[ ${LOG_LEVEL_VAL["$GLOBAL_LOG_LEVEL"]} -ge ${LOG_LEVEL_VAL["$log_level"]} ]]; then
        echo -e "${log_color}[$(date +"%Y-%m-%d %H:%M:%S %Z")] [${log_level}] ${log_text} ${LOG_DEFAULT_COLOR}";
    fi

    return 0;
}

log_info()      { log "$@"; }
log_success()   { log "$1" "SUCCESS" "${LOG_SUCCESS_COLOR}"; }
log_error()     { log "$1" "ERROR" "${LOG_ERROR_COLOR}"; }
log_warning()   { log "$1" "WARNING" "${LOG_WARN_COLOR}"; }
log_debug()     { log "$1" "DEBUG" "${LOG_DEBUG_COLOR}"; }
#endregion

#region VARIABLES

COMMAND="backup-list"
DB_TYPE="all"

IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-"hub.elma365.tech"}"
BACKUP_DST="${BACKUP_DST:-filesystem}"
BACKUP_LIFE="${BACKUP_LIFE:-7}"

# Filesystem backup settings
TMP_DIR="${TMP_DIR:-/opt/elma365/backupper/tmp}"
BACKUP_PATH="${BACKUP_PATH:-/opt/elma365/backupper/backup/}"
STORAGE_PATH="${STORAGE_PATH:-/opt/elma365/backupper/backup/}"

# Kubernetes settings
KUBECONFIG="${KUBECONFIG:-/home/elma/.kube/config}"
K8S_NS_APP="${K8S_NS_APP:-elma365}"
K8S_NS_DBS="${K8S_NS_DBS:-elma365-dbs}"

# S3 backup settings
S3_BUCKET_NAME="${S3_BUCKET_NAME:-}"
S3_HOST="${S3_HOST:-}"
S3_PORT="${S3_PORT:-}"
S3_ROOT_USER="${S3_ROOT_USER:-}"
S3_ROOT_PASSWORD="${S3_ROOT_PASSWORD:-}"
S3_SSL_ENABLED="${S3_SSL_ENABLED:-"false"}"
S3_IN_K8S="${S3_IN_K8S:-"false"}"

# Port connection settings
S3_SRC_PORT="${S3_SRC_PORT:-7000}"
SRC_S3_SRC_PORT="${SRC_S3_SRC_PORT:-7000}"
DST_S3_SRC_PORT="${DST_S3_SRC_PORT:-7001}"
PG_SRC_PORT="${PG_SRC_PORT:-7001}"
MONGO_SRC_PORT="${MONGO_SRC_PORT:-7002}"

#endregion

function usage {
    echo -e "This is an example script with ready to use logging";
    echo -e ""
    echo -e "Usage: $0 [OPTIONS...] COMMAND DB_TYPE"
    echo -e ""
    echo -e "Commands:"
    echo -e "  backup                                      Создать резервную копию"
    echo -e "  restore                                     Восстановить из резервной копии"
    echo -e "  backup-list                                 Показать список существующих резервных копий" 
    echo -e ""
    echo -e "Database types:"
    echo -e "  postgres                                     PostgreSQL"
    echo -e "  mongo                                        MongoDB"
    echo -e "  s3                                           S3 хранилище"
    echo -e "  all                                          Все поддерживаемые типы баз данных и хранилищ"
    echo -e ""
    echo -e "Options:";
    echo -e "  Backup common settings:"
    echo -e "    -r,--image-repository    REPOSITORY       Адрес репозитория для загрузки образов контейнеров (default: $IMAGE_REPOSITORY)"
    echo -e "    -d,--backup-dest         s3|filesystem    Место сохранения резервной копии (default: $BACKUP_DST)"
    echo -e "                                              Доступные значения:"
    echo -e "                                                s3 — резервная копия будет сохранена в S3 хранилище"
    echo -e "                                                filesystem — резервная копия будет сохранена на локальную файловую систему по пути указанному в параметре BACKUP_PATH"
    echo -e "    -l,--backup-life         DAYS             Период хранения резервных копий в днях (default: $BACKUP_LIFE)"
    echo -e ""
    echo -e "  Filesystem settings:"
    echo -e "    -t,--tmp-dir             DIR              Директория для хранения временных резервных копий (default: $TMP_DIR)"
    echo -e "    -b,--backup-path         DIR              Директория, из которой будут извлекаться резервные копии (default: $BACKUP_PATH)"
    echo -e "    -s,--storage-path        DIR              Директория, в которую будут сохраняться резервные копии (default: $STORAGE_PATH)"
    echo -e ""
    echo -e "  Kubernetes settings:"
    echo -e "    -k,--kubeconfig          FILE             Путь до файла kubeconfig, используется для подключения к Kubernetes-кластеру (default: $KUBECONFIG)"
    echo -e "    --k8s-ns-app             NAMESPACE        Kubernetes namespace, в который установлено приложение ELMA365 (default: $K8S_NS_APP)"
    echo -e "    --k8s-ns-dbs             NAMESPACE        Kubernetes namespace, в который установлены встроенные базы данных (default: $K8S_NS_DBS)"
    echo -e ""
    echo -e "  S3 settings:"
    echo -e "    --s3-bucket-name         BUCKET_NAME      Имя S3 бакета для хранения резервных копий.  Зарезервированные (недоступные) наименования бакетов имеют формат (маска) "s3elma365\*" (default: $S3_BUCKET_NAME)"
    echo -e "    --s3-host                HOST             URL-адрес S3 хранилища (default: $S3_HOST)"
    echo -e "    --s3-port                PORT             Порт для подключения к S3 хранилищу (default: $S3_PORT)"
    echo -e "    --s3-root-user           USER             Имя пользователя для доступа к S3 бакету (default: $S3_ROOT_USER)"
    echo -e "    --s3-root-password       PASSWORD         Пароль для пользователя S3 (default: $S3_ROOT_PASSWORD)"
    echo -e "    --s3-ssl-enabled         BOOLEAN          Использовать SSL для подключения к S3 хранилищу (default: $S3_SSL_ENABLED)"
    echo -e "    --s3-in-k8s              BOOLEAN          Находится ли S3 хранилище в Kubernetes кластере (default: $S3_IN_K8S)"
    echo -e ""
    echo -e "  Source port settings:"
    echo -e "    --s3-src-port            PORT             Локальный порт для подключения к S3 хранилищу (default: $S3_SRC_PORT)"
    echo -e "    --src-s3-src-port        PORT             Локальный порт для подключения к S3 хранилищу источника (default: $SRC_S3_SRC_PORT)"
    echo -e "    --dst-s3-src-port        PORT             Локальный порт для подключения к S3 хранилищу назначения (default: $DST_S3_SRC_PORT)"
    echo -e "    --pg-src-port            PORT             Локальный порт для подключения к PostgreSQL (default: $PG_SRC_PORT)"
    echo -e "    --mongo-src-port         PORT             Локальный порт для подключения к MongoDB (default: $MONGO_SRC_PORT)"
    echo -e ""
    echo -e "  Other Options:"
    echo -e "    --log-level              LOGLEVEL         Уровень логирования (default: $GLOBAL_LOG_LEVEL)"
    echo -e "    -h, --help                                Отобразить справку"
    echo -e ""
    echo -e "Example:"
    echo -e "    $0 --log-level LOGLEVEL"
    echo -e ""
    echo -e "    $0 --help"
    echo -e ""
}


# Функция для обработки секретов, переданных в виде строки "secret:SECRET_NAME" или "base64:BASE64_ENCODED_VALUE".
# Если секрет передан в виде "secret:SECRET_PATH_OR_NAME", функция пытается прочитать значение секрета из файла по пути "/run/secrets/SECRET_PATH_OR_NAME", либо по пути "SECRET_PATH_OR_NAME".
# Секрет извлекается и возвращается в виде строки. Если секрет передан в виде "base64:BASE64_ENCODED_VALUE", функция декодирует его из base64 и возвращает результат.
# При этом если секрет является файлом, то функция сохраняет его во временную директорию и возвращает путь до сохраненного файла.
function process_secret {
    local secret_path_or_name="$1"
    local secret_value="$secret_path_or_name"
    local is_file="$2"

    if [[ "$secret_path_or_name" == "secret:"* ]]; then
        secret_path_or_name="${secret_path_or_name#secret:}"
        if ! [[ -f "/run/secrets/${secret_path_or_name}" ]]; then
            error_exit "Секрет \"$secret_path_or_name\" не найден по пути \"/run/secrets/${secret_path_or_name}\""
        fi

        if [[ -f "$secret_path_or_name" ]]; then
            secret_value=$(cat "${secret_path_or_name}" 2>/dev/null)
        else
            secret_value=$(cat "/run/secrets/${secret_path_or_name}" 2>/dev/null)
        fi
    fi

    if [[ "$secret_value" == "base64:"* ]]; then
        secret_value=$(echo -n "${secret_value#base64:}" | base64 -d 2>/dev/null)
    fi
    if [[ -z "$secret_value" ]]; then
        error_exit "Значение секрета \"$secret_value\" не может быть пустым"
    fi

    if [[ "$is_file" == "true" ]]; then
        local secret_file_path="/opt/elma365/backupper/secrets/$(echo $RANDOM | md5sum | head -c 6)"
        echo -n "$secret_value" > "$secret_file_path"
        echo "$secret_file_path"
    else
        echo "$secret_value"
    fi
}

function error_exit {
    log_error "$1"
    rm -rf "/opt/elma365/backupper/secrets" 
    exit 1
}

#region Prestart
mkdir -p "/opt/elma365/backupper/secrets" 2>/dev/null
#endregion

#region Process arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        backup|restore|backup-list)
            COMMMAND="$1"
            ;;
        postgres|mongo|s3|all)
            DB_TYPE="$1"
            ;;
        -d|--backup-dest)
            if ! [[ " $valid_backup_dests " =~ " $2 " ]] ; then
                error_exit "Некорректное место сохранения резервной копии. Ожидается одно из [s3, filesystem], текущее значение: \"$2\""
            fi
            BACKUP_DST="$2"
            shift
            ;;
        -l|--backup-life)
            if ! [[ "$2" =~ ^[0-9]+$ ]] ; then
                error_exit "Некорректное значение периода хранения резервных копий. Ожидается целое число, текущее значение: \"$2\""
            fi
            BACKUP_LIFE="$2"
            shift
            ;;
        -t|--tmp-dir)
            TMP_DIR="$2"
            shift
            ;;
        -b|--backup-path)
            if ! [[ -d "$2" ]] ; then
                error_exit "Некорректное значение пути для резервных копий. Директория должна существовать, текущее значение: \"$2\""
            fi
            BACKUP_PATH="$2"
            shift
            ;;
        -s|--storage-path)
            STORAGE_PATH="$2"
            shift
            ;;
        -k|--kubeconfig)
            local kubeconfig_value=$(process_secret "$2" "true")
            KUBECONFIG="$kubeconfig_value"
            shift
            ;;
        --k8s-ns-app)
            K8S_NS_APP="$2"
            shift
            ;;
        --k8s-ns-dbs)
            K8S_NS_DBS="$2"
            shift
            ;;
        --s3-bucket-name)
            S3_BUCKET_NAME="$2"
            shift
            ;;
        --s3-host)
            S3_HOST="$2"
            shift
            ;;
        --s3-port)
            if ! [[ "$2" =~ ^[0-9]+$ ]] ; then  
                error_exit "Некорректное значение порта для S3 хранилища. Ожидается целое число, текущее значение: \"$2\""
            fi
            S3_PORT="$2"
            shift
            ;;
        --s3-root-user)
            S3_ROOT_USER="$2"
            shift
            ;;
        --s3-root-password)
            local s3_root_password_value=$(process_secret "$2" "false")
            S3_ROOT_PASSWORD="$s3_root_password_value"
            shift
            ;;
        --s3-ssl-enabled)
            S3_SSL_ENABLED="true"
            ;;
        --s3-in-k8s)
            S3_IN_K8S="true"
            ;;
        --s3-src-port)
            if ! [[ "$2" =~ ^[0-9]+$ ]] ; then  
                error_exit "Некорректное значение порта для подключения к S3 хранилищу. Ожидается целое число, текущее значение: \"$2\""
            fi
            S3_SRC_PORT="$2"
            shift
            ;;
        --src-s3-src-port)
            if ! [[ "$2" =~ ^[0-9]+$ ]] ; then  
                error_exit "Некорректное значение порта для подключения к S3 хранилищу источника. Ожидается целое число, текущее значение: \"$2\""
            fi
            SRC_S3_SRC_PORT="$2"
            shift
            ;;
        --dst-s3-src-port)
            if ! [[ "$2" =~ ^[0-9]+$ ]] ; then  
                error_exit "Некорректное значение порта для подключения к S3 хранилищу назначения. Ожидается целое число, текущее значение: \"$2\""
            fi
            DST_S3_SRC_PORT="$2"
            shift
            ;;
        --pg-src-port)
            if ! [[ "$2" =~ ^[0-9]+$ ]] ; then  
                error_exit "Некорректное значение порта для подключения к PostgreSQL. Ожидается целое число, текущее значение: \"$2\""
            fi
            PG_SRC_PORT="$2"
            shift
            ;;
        --mongo-src-port)
            if ! [[ "$2" =~ ^[0-9]+$ ]] ; then  
                error_exit "Некорректное значение порта для подключения к MongoDB. Ожидается целое число, текущее значение: \"$2\""
            fi
            MONGO_SRC_PORT="$2"
            shift
            ;;
        --log-level)
            if ! [[ " ${!LOG_LEVEL_VAL[@]} " =~ " $2 " ]] ; then
                error_exit "Некорректное значение уровня логирования. Ожидается одно из [${!LOG_LEVEL_VAL[*]}], текущее значение: \"$2\""
            fi
            GLOBAL_LOG_LEVEL="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) 
            log_error "Неизвестный аргумент \"$1\""
            exit 1
            ;;
    esac
    shift
done
#endregion

# Using template to prepare config
cat << EOF > /opt/elma365/backupper/etc/config
# Elma365 Backupper Configuration
# Параметр KUBECONFIG задаёт расположение конфигурационного файла подключения к Kubernetes
# при пустой переменной происходит попытка обращения к конфигурационному файлу по пути ~/.kube/config
KUBECONFIG="${KUBECONFIG}"
# Параметр BACKUP_DST задает куда будет осуществляться резервное копирование
# Доступные варианты: s3, filesystem
# s3 - резервная копия будет сохранена на S3 хранилище
# filesystem - резервная копия будет сохранена на локальную файловую систему по пути указанному в параметре BACKUP_PATH
BACKUP_DST="${BACKUP_DST}"

# namespace, в который установлено приложение ELMA365
K8S_NS_APP="${K8S_NS_APP}"
# namespace, в который установлены встроенные базы данных
K8S_NS_DBS="${K8S_NS_DBS}"

# период хранения резервной копии в днях
BACKUP_LIFE=${BACKUP_LIFE}

# Директория для хранения временных резервных копий
TMP_DIR="${TMP_DIR}"
# Директория, из которой будут браться резервные копии
BACKUP_PATH="${BACKUP_PATH}"
# Директория в которую будут сохраняться резервные копии
STORAGE_PATH="${STORAGE_PATH}"

# Параметры для настройки подключения к S3 хранилищу, в которое будут сохраняться резервные копии
# S3_BUCKET_NAME - наименование бакета в который будут сохраняться резервные копии. Зарезервированные (недоступные) наименования бакетов имеют формат (маска) "s3elma365*"
# S3_HOST - URL адрес S3 хранилища
# S3_PORT - порт для подключения к S3 хранилищу
# S3_ROOT_USER - наименование пользователя, имеющего права на чтение/запись в бакет указанный в параметре S3_BUCKET_NAME
# S3_ROOT_PASSWORD - пароль для пользователя S3_ROOT_USER
# S3_SSL_ENABLED - используется ли шифрование при подключении к внешнему S3 хранилищу (true/false)
# S3_IN_K8S - находится ли указанное выше хранилище в кластере K8S (true/false)
S3_BUCKET_NAME="${S3_BUCKET_NAME}"
S3_HOST="${S3_HOST}"
S3_PORT=${S3_PORT}
S3_ROOT_USER="${S3_ROOT_USER}"
S3_ROOT_PASSWORD="${S3_ROOT_PASSWORD}"
S3_SSL_ENABLED=${S3_SSL_ENABLED}
S3_IN_K8S=${S3_IN_K8S}

# Параметры переадресации портов для доступа к базам данных в кластере Kubernetes
# В Kubernetes кластер будут переадресованы локальные порты, указанные в параметрах:
# S3_SRC_PORT — порт для подключения к S3 хранилищу
#   SRC_S3_SRC_PORT - порт для подключения к S3 хранилищу источника
#   DST_S3_SRC_PORT - порт для подключения к S3 хранилищу назначения
# PG_SRC_PORT — порт для подключения к PostgreSQL
# MONGO_SRC_PORT — порт для подключения к MongoDB
S3_SRC_PORT=${S3_SRC_PORT}
DST_S3_SRC_PORT=${DST_S3_SRC_PORT}
PG_SRC_PORT=${PG_SRC_PORT}
MONGO_SRC_PORT=${MONGO_SRC_PORT}

# Адрес приватного репозитория
IMAGE_REPOSITORY="${IMAGE_REPOSITORY}"
EOF

if [[ -z "$COMMAND" ]]; then
    error_exit "Command not sepcified!"
fi
if [[ -z "$DB_TYPE" ]]; then
    error_exit "Database type not sepcified!"
fi

exec "/usr/local/bin/elma365-backupper $COMMAND $DB_TYPE"