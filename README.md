# Контейнеризированный ELMA365 Backupper

**Elma365-Backupper** — контейнеризированная утилита для автоматического резервного копирования данных платформы ELMA365.

## Описание

Elma365-Backupper — это инструмент, предназначенный для создания полного резервного копирования приложения ELMA365, включая данные приложения, компоненты, конфигурации и встроенные базы данных (PostgreSQL, MongoDB, S3-хранилище). Утилита работает в контейнере Docker и может быть развёрнута в Kubernetes кластере для прямого доступа к компонентам ELMA365.

## Возможности

- **Многоцелевое резервное копирование** — поддержка резервного копирования на локальную файловую систему или S3-совместимое хранилище
- **Интеграция с Kubernetes** — встроенная поддержка для доступа к компонентам ELMA365, развёрнутым в K8s кластере
- **Гибкая конфигурация** — параметризация через переменные окружения и аргументы командной строки
- **Управление жизненным циклом резервных копий** — автоматическая очистка старых резервных копий на основе политики хранения
- **Гибкое развёртывание** — поддержка запуска как однократного задания (Job), периодического задания (CronJob) или отдельного Pod
- **Безопасность** — контейнер работает от непривилегированного пользователя с минимальными правами доступа
- **Логирование** — подробное логирование со множеством уровней детализации (DEBUG, INFO, WARNING, ERROR)

## Требования

### Для локального запуска
- Docker/Podman или другой совместимый container runtime
- Доступ к ELMA365 компонентам (сетевая доступность)
- Достаточное дисковое пространство для резервных копий

### Для развёртывания в Kubernetes
- Kubernetes кластер версии 1.19 или выше
- kubectl для применения конфигураций
- ServiceAccount с правами доступа к необходимым ресурсам (опционально, для доступа к K8s API)
- Достаточное дисковое пространство через PersistentVolume (если используется локальное хранилище)

## Установка и подготовка

### Сборка Docker образа

```bash
# Клонируйте репозиторий
git clone <repository-url>
cd elma365-backupper

# Соберите Docker образ
docker build -t elma365-backupper:1.0.17 .
```

**Особенности сборки:**
- Двухэтапная сборка (builder + final) для минимизации размера образа
- Базовый образ: `debian:latest` (reproducible hash в Dockerfile)
- Версия утилиты: 1.0.17
- Контейнер работает от пользователя `elma` (UID: 10001)
- Все бинарные файлы установлены с минимальными правами доступа (SUID/SGID удалены)

### Публичные образы

Если предподготовленные образы доступны в реестре, используйте:

```bash
docker pull <registry>/elma365-backupper:1.0.17
```

Замените `<registry>` на адрес вашего реестра образов.

## Быстрый старт

### Вариант 1: Локальное резервное копирование

Резервное копирование на локальную файловую систему:

```bash
docker run --rm \
  -e BACKUP_DST=filesystem \
  -e BACKUP_PATH=/backups/data \
  -e STORAGE_PATH=/backups/storage \
  -v /path/to/backups:/backups \
  elma365-backupper:1.0.17
```

### Вариант 2: В Kubernetes как однократное задание (Job)

Создайте файл `backup-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: elma-backup-once
  namespace: elma365
spec:
  template:
    spec:
      serviceAccountName: elma-backupper
      containers:
      - name: backupper
        image: elma365-backupper:1.0.17
        imagePullPolicy: IfNotPresent
        env:
        - name: BACKUP_DST
          value: "filesystem"
        - name: K8S_NS_APP
          value: "elma365"
        - name: K8S_NS_DBS
          value: "elma365-dbs"
        volumeMounts:
        - name: kubeconfig
          mountPath: /home/elma/.kube
          readOnly: true
        - name: backup-storage
          mountPath: /opt/elma365/backupper/backup
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 2
            memory: 2Gi
      restartPolicy: Never
      volumes:
      - name: kubeconfig
        secret:
          secretName: kubeconfig
      - name: backup-storage
        persistentVolumeClaim:
          claimName: backup-pvc
  backoffLimit: 3
```

Применить:
```bash
kubectl apply -f backup-job.yaml
kubectl logs -f job/elma-backup-once -n elma365
```

### Вариант 3: В Kubernetes как периодическое задание (CronJob)

Создайте файл `backup-cronjob.yaml`:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: elma-backup-daily
  namespace: elma365
spec:
  schedule: "0 2 * * *"  # Каждый день в 02:00
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: elma-backupper
          containers:
          - name: backupper
            image: elma365-backupper:1.0.17
            imagePullPolicy: IfNotPresent
            env:
            - name: BACKUP_DST
              value: "filesystem"
            - name: BACKUP_LIFE
              value: "7"  # Хранить 7 дней
            - name: K8S_NS_APP
              value: "elma365"
            - name: K8S_NS_DBS
              value: "elma365-dbs"
            volumeMounts:
            - name: kubeconfig
              mountPath: /home/elma/.kube
              readOnly: true
            - name: backup-storage
              mountPath: /opt/elma365/backupper/backup
            resources:
              requests:
                cpu: 500m
                memory: 512Mi
              limits:
                cpu: 2
                memory: 2Gi
          restartPolicy: OnFailure
          volumes:
          - name: kubeconfig
            secret:
              secretName: kubeconfig
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
```

Применить:
```bash
kubectl apply -f backup-cronjob.yaml
```

## Справка по конфигурации

### Переменные окружения и аргументы

Утилита настраивается через переменные окружения или аргументы командной строки. При запуске в контейнере используются переменные окружения; при прямом запуске скрипта — аргументы командной строки.

#### Общие параметры резервной копии

| Переменная окружения | Аргумент | Значение по умолчанию | Описание |
|---|---|---|---|
| `BACKUP_DST` | `-d`, `--backup-dest` | `filesystem` | Место сохранения: `filesystem` или `s3` |
| `BACKUP_LIFE` | `-l`, `--backup-life` | `7` | Период хранения резервных копий в днях |

**Примеры:**
```yaml
env:
- name: BACKUP_DST
  value: "s3"
- name: BACKUP_LIFE
  value: "30"  # Хранить 30 дней
```

#### Параметры локального резервного копирования (Filesystem)

| Переменная окружения | Аргумент | Значение по умолчанию | Описание |
|---|---|---|---|
| `TMP_DIR` | `-t`, `--tmp-dir` | `/opt/elma365/backupper/tmp` | Директория для временных файлов резервной копии |
| `BACKUP_PATH` | `-b`, `--backup-path` | `/opt/elma365/backupper/backup/` | Директория источника для извлечения резервных копий |
| `STORAGE_PATH` | `-s`, `--storage-path` | `/opt/elma365/backupper/storage/` | Директория назначения для сохранения резервных копий |

**Примеры:**
```yaml
env:
- name: TMP_DIR
  value: "/tmp/elma365-backup"
- name: STORAGE_PATH
  value: "/mnt/backup-storage"
```

#### Параметры Kubernetes

| Переменная окружения | Значение по умолчанию | Описание |
|---|---|---|
| `KUBECONFIG` | `/home/elma/.kube/config` | Путь к файлу kubeconfig для подключения к K8s кластеру |
| `K8S_NS_APP` | `elma365` | Kubernetes namespace, где установлено приложение ELMA365 |
| `K8S_NS_DBS` | `elma365-dbs` | Kubernetes namespace, где установлены встроенные базы данных |

**Примеры:**
```yaml
env:
- name: KUBECONFIG
  value: "/etc/kubernetes/kubeconfig.yaml"
- name: K8S_NS_APP
  value: "my-elma-app"
- name: K8S_NS_DBS
  value: "my-elma-dbs"
```

#### Параметры S3 хранилища

| Переменная окружения | Значение по умолчанию | Описание |
|---|---|---|
| `S3_BUCKET_NAME` | — | Имя S3 бакета для сохранения резервных копий. **Зарезервированные имена**: `s3elma365*` (недоступны) |
| `S3_HOST` | — | URL-адрес или имя хоста S3 хранилища (например: `minio.example.com` или `s3.amazonaws.com`) |
| `S3_PORT` | — | Порт для подключения к S3 (по умолчанию: 443 для HTTPS, 80 для HTTP) |
| `S3_ROOT_USER` | — | Учётное имя (Access Key ID) для аутентификации в S3 |
| `S3_ROOT_PASSWORD` | — | Пароль (Secret Access Key) для аутентификации в S3 |
| `S3_SSL_ENABLED` | `true` | Использовать SSL/TLS для подключения (`true` или `false`) |
| `S3_IN_K8S` | `false` | S3 хранилище находится в кластере Kubernetes (`true` или `false`) |

**Пример конфигурации для MinIO:**
```yaml
env:
- name: BACKUP_DST
  value: "s3"
- name: S3_BUCKET_NAME
  value: "elma-backups"
- name: S3_HOST
  value: "minio.storage"
- name: S3_PORT
  value: "9000"
- name: S3_ROOT_USER
  valueFrom:
    secretKeyRef:
      name: s3-credentials
      key: access-key
- name: S3_ROOT_PASSWORD
  valueFrom:
    secretKeyRef:
      name: s3-credentials
      key: secret-key
- name: S3_SSL_ENABLED
  value: "false"
```

#### Параметры портов переадресации

| Переменная окружения | Значение по умолчанию | Описание |
|---|---|---|
| `S3_SRC_PORT` | `7000` | Локальный порт для S3 хранилища источника (при использовании K8s port-forward) |
| `DST_S3_SRC_PORT` | `7001` | Локальный порт для S3 хранилища назначения |
| `PG_SRC_PORT` | `7001` | Локальный порт для PostgreSQL |
| `MONGO_SRC_PORT` | `7002` | Локальный порт для MongoDB |

#### Прочие параметры

| Переменная окружения | Аргумент | Значение по умолчанию | Описание |
|---|---|---|---|
| `GLOBAL_LOG_LEVEL` | `--log-level` | `INFO` | Уровень логирования: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `SUCCESS` |

**Примеры:**
```yaml
env:
- name: GLOBAL_LOG_LEVEL
  value: "DEBUG"
```

### Примеры конфигурации

#### Пример 1: Простое локальное резервное копирование

```bash
docker run --rm \
  -e BACKUP_DST=filesystem \
  -e BACKUP_LIFE=7 \
  -v /mnt/backups:/opt/elma365/backupper/backup \
  elma365-backupper:1.0.17
```

#### Пример 2: Резервное копирование в S3

```bash
docker run --rm \
  -e BACKUP_DST=s3 \
  -e S3_HOST=minio.example.com \
  -e S3_PORT=9000 \
  -e S3_BUCKET_NAME=elma-backups \
  -e S3_ROOT_USER=minioadmin \
  -e S3_ROOT_PASSWORD=minioadmin \
  -e S3_SSL_ENABLED=false \
  elma365-backupper:1.0.17
```

## S3 интеграция

### Подготовка S3 хранилища

1. **Создание бакета:**
   ```bash
   # Для MinIO
   mc mb minio/elma-backups
   
   # Или через AWS CLI
   aws s3 mb s3://elma-backups
   ```

2. **Создание пользователя S3:**
   - Убедитесь, что учётные данные (Access Key ID и Secret Access Key) имеют права на чтение и запись в бакет
   - Для MinIO используйте команду: `mc admin user add <alias> <access-key> <secret-key>`

3. **Проверка подключения:**
   ```bash
   # Из контейнера можно проверить доступность хранилища
   docker run --rm \
     -e S3_HOST=minio.example.com \
     -e S3_PORT=9000 \
     -e S3_ROOT_USER=backup-user \
     -e S3_ROOT_PASSWORD=backup-password \
     elma365-backupper:1.0.17 \
     /bin/bash -c "nc -zv minio.example.com 9000"
   ```

### Ограничения S3

- **Зарезервированные имена бакетов:** Имена, начинающиеся с `s3elma365`, зарезервированы и недоступны
- **IAM политики:** Убедитесь, что пользователь S3 имеет достаточные права для работы с объектами в бакете

### Мониторинг S3 хранилища

Размер резервных копий можно проверить через:

```bash
# Для MinIO
mc du minio/elma-backups

# Для AWS S3
aws s3 ls s3://elma-backups --recursive --summarize
```

## Развёртывание в Kubernetes

### RBAC и ServiceAccount

Для использования kubeconfig и доступа к K8s API создайте ServiceAccount и необходимые роли:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: elma-backupper
  namespace: elma365
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: elma-backupper
  namespace: elma365
rules:
- apiGroups: [""]
  resources: ["pods", "pods/portforward"]
  verbs: ["get", "list", "create", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: elma-backupper
  namespace: elma365
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: elma-backupper
subjects:
- kind: ServiceAccount
  name: elma-backupper
  namespace: elma365
```

### PersistentVolume и PersistentVolumeClaim

Для хранилища резервных копий:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: elma365
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard  # Замените на доступный в вашем кластере
  resources:
    requests:
      storage: 100Gi  # Размер в зависимости от данных ELMA365
```

### Дополнительная конфигурация Kubernetes

Если требуется передать kubeconfig в контейнер, создайте Secret:

```bash
kubectl create secret generic kubeconfig \
  --from-file=config=/path/to/kubeconfig \
  -n elma365
```

## Устранение проблем

### Проблема 1: "kubeconfig not found"

**Симптомы:**
```
Error reading kubeconfig: no such file or directory
```

**Причины:**
- KUBECONFIG переменная указывает на неправильный путь
- Secret с kubeconfig не создан или не смонтирован в контейнер
- Путь к kubeconfig некорректен в PodSpec

**Решение:**
1. Проверьте путь KUBECONFIG:
   ```bash
   kubectl get secret kubeconfig -o jsonpath='{.data.config}' | base64 -d > /tmp/test.config
   ```

2. Убедитесь, что volumeMount корректен:
   ```yaml
   volumeMounts:
   - name: kubeconfig
     mountPath: /home/elma/.kube
     readOnly: true
   ```

3. Пересоздайте Secret:
   ```bash
   kubectl delete secret kubeconfig -n elma365
   kubectl create secret generic kubeconfig --from-file=config=kubeconfig -n elma365
   ```

### Проблема 2: Ошибки подключения к S3

**Симптомы:**
```
Failed to connect to S3: connection refused / timeout
```

**Причины:**
- S3_HOST или S3_PORT некорректны
- S3 хранилище недоступно по сети
- Учётные данные (S3_ROOT_USER, S3_ROOT_PASSWORD) неправильны
- SSL_ENABLED не соответствует конфигурации хранилища

**Решение:**
1. Проверьте доступность хоста и порта:
   ```bash
   nc -zv minio.example.com 9000
   # или через контейнер
   kubectl run -it --rm debug --image=busybox -- nc -zv minio.example.com 9000
   ```

2. Проверьте учётные данные:
   ```bash
   # Используйте mc (MinIO client) для проверки
   mc alias set minio https://minio.example.com:9000 ACCESS_KEY SECRET_KEY
   mc ls minio/
   ```

3. Убедитесь в корректности SSL_ENABLED:
   - Если используется HTTPS: `S3_SSL_ENABLED=true`
   - Если используется HTTP: `S3_SSL_ENABLED=false`

### Проблема 3: Недостаточно дискового пространства

**Симптомы:**
```
No space left on device / ENOSPC
```

**Причины:**
- PersistentVolume полон
- Политика удаления старых резервных копий (BACKUP_LIFE) не работает
- Размер резервной копии больше доступного пространства

**Решение:**
1. Проверьте использование дискового пространства:
   ```bash
   kubectl exec -it <pod-name> -- df -h
   ```

2. Увеличьте размер PVC:
   ```bash
   kubectl patch pvc backup-pvc -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'
   ```

3. Проверьте параметр BACKUP_LIFE:
   ```yaml
   env:
   - name: BACKUP_LIFE
     value: "7"  # Хранить не более 7 дней
   ```

### Проблема 4: Ошибки разрешений (Permission denied)

**Симптомы:**
```
Permission denied: /opt/elma365/backupper/backup
```

**Причины:**
- Контейнер работает от пользователя `elma` (UID: 10001), но директория принадлежит другому пользователю
- Права доступа на volume недостаточны

**Решение:**
1. Проверьте права доступа на hostPath:
   ```bash
   ls -ld /mnt/backups
   sudo chown 10001:10001 /mnt/backups
   sudo chmod 700 /mnt/backups
   ```

2. Используйте securityContext в Pod:
   ```yaml
   securityContext:
     fsGroup: 10001
     runAsUser: 10001
     runAsNonRoot: true
   ```

### Проблема 5: Высокое потребление памяти / CPU

**Симптомы:**
- Pod убивается (OOMKilled)
- Резервное копирование работает долго или зависает

**Решение:**
1. Увеличьте лимиты ресурсов:
   ```yaml
   resources:
     requests:
       cpu: 1000m
       memory: 1Gi
     limits:
       cpu: 4
       memory: 4Gi
   ```

2. Включите DEBUG логирование для анализа:
   ```yaml
   env:
   - name: GLOBAL_LOG_LEVEL
     value: "DEBUG"
   ```

3. Проверьте размер резервной копии и данные ELMA365

### Проблема 6: CronJob не запускается по расписанию

**Симптомы:**
- CronJob создан, но Job не запускается в ожидаемое время
- Нет ошибок в логах, но Job не создаётся

**Причины:**
- Неправильный формат расписания CRON
- Часовой пояс контроллера CronJob
- Количество успешно завершённых Job достигло лимита historyLimit

**Решение:**
1. Проверьте расписание:
   ```bash
   kubectl get cronjob elma-backup-daily -o yaml | grep -A 2 schedule
   ```

2. Убедитесь, что расписание в формате UTC:
   ```yaml
   schedule: "0 2 * * *"  # 02:00 UTC ежедневно
   ```

3. Проверьте и увеличьте historyLimit:
   ```yaml
   spec:
     schedule: "0 2 * * *"
     successfulJobsHistoryLimit: 5
     failedJobsHistoryLimit: 5
   ```

## Часто задаваемые вопросы (FAQ)

**В: Какой размер резервной копии обычно занимает ELMA365?**
О: Размер зависит от количества данных в приложении. Для оценки:
- Минимум: ~1-5 ГБ (малая инсталляция)
- Среднее: ~50-200 ГБ (типичная инсталляция)
- Максимум: >500 ГБ (крупная инсталляция с большим объёмом документов)

**В: Как часто нужно создавать резервные копии?**
О: Рекомендуется:
- Ежедневное резервное копирование с хранением 7-30 дней
- Еженедельное полное резервное копирование с долгосрочным хранением (при необходимости)

**В: Можно ли создавать резервные копии во время работы ELMA365?**
О: Да, утилита поддерживает резервное копирование "на бегу", но рекомендуется выполнять это в гервые часы (например, 02:00), когда нагрузка на систему минимальна.

**В: Поддерживается ли инкрементальное резервное копирование?**
О: В текущей версии 1.0.17 поддерживается только полное резервное копирование.

**В: Как восстановить данные из резервной копии?**
О: Информация о восстановлении находится в документации ELMA365. Контактируйте поддержку для подробного руководства по процедуре восстановления.

**В: Можно ли одновременно резервировать данные в S3 и на файловую систему?**
О: Нет, текущая версия поддерживает одно место назначения за раз. Для резервного копирования в оба места запустите две отдельные Job/CronJob.

**В: Какие права доступа требуются для kubeconfig?**
О: kubeconfig должен содержать достаточные права для:
- Получения списка Pod в соответствующих namespace
- Создания и удаления port-forward соединений
- Чтения информации о сервисах и конфигурациях (если требуется)

**В: Как отследить ход выполнения резервной копии?**
О: Используйте логирование:
```bash
# Для Docker
docker logs <container-id> -f

# Для Kubernetes
kubectl logs -f pod/<pod-name> -n elma365

# Или для Job
kubectl logs -f job/elma-backup-once -n elma365
```

## Лицензия

Этот проект лицензирован под [Apache License 2.0](LICENSE).

## Поддержка и обратная связь

При возникновении проблем:
1. Проверьте раздел "Устранение проблем"
2. Включите DEBUG логирование: `GLOBAL_LOG_LEVEL=DEBUG`
3. Обратитесь в поддержку ELMA365 с логами утилиты и конфигурацией
