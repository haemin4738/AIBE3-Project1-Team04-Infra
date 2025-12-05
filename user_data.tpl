#!/bin/bash
set -e

# 1) 기본 설정
timedatectl set-timezone Asia/Seoul

# Swap
dd if=/dev/zero of=/swapfile bs=128M count=32
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab


# 2) Docker + Compose 설치
dnf update -y
dnf install -y docker git

systemctl enable docker
systemctl start docker

usermod -aG docker ec2-user

curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true

docker network create common || true


# 3) GHCR 로그인
runuser -l ec2-user -c "echo '${ghcr_token}' | docker login ghcr.io -u '${ghcr_owner}' --password-stdin"
runuser -l ec2-user -c "docker pull ghcr.io/${ghcr_owner}/aibe3-finalproject-team4-backend:latest || true"

# 4) MySQL 실행
docker run -d \
  --name mysql_1 \
  --restart unless-stopped \
  --network common \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=${db_root_password} \
  -e MYSQL_DATABASE=${app_db_name} \
  -e TZ=Asia/Seoul \
  -v /dockerProjects/mysql_1/data:/var/lib/mysql \
  mysql:8.0 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --default-time-zone=+09:00 \
  --performance_schema=OFF \
  --innodb_buffer_pool_size=256M


# 5) Redis 실행
docker run -d \
  --name redis_1 \
  --restart unless-stopped \
  --network common \
  -p 6379:6379 \
  -e TZ=Asia/Seoul \
  redis:7 \
  redis-server --requirepass "${redis_password}"


# 6) Nginx Proxy Manager 실행
docker run -d \
  --name npm_1 \
  --restart unless-stopped \
  --network common \
  -p 80:80 \
  -p 81:81 \
  -p 443:443 \
  -e TZ=Asia/Seoul \
  -e INITIAL_ADMIN_EMAIL=${npm_admin_email} \
  -e INITIAL_ADMIN_PASSWORD=${npm_admin_password} \
  -v /dockerProjects/npm_1/data:/data \
  -v /dockerProjects/npm_1/letsencrypt:/etc/letsencrypt \
  jc21/nginx-proxy-manager:latest


# 7) Elasticsearch + Nori 플러그인 설치 (이미지 생성)
mkdir -p /dockerProjects/elasticsearch/data
rm -rf /dockerProjects/elasticsearch/data/*
chown -R 1000:1000 /dockerProjects/elasticsearch/data

echo "▶ Step 1: Building temporary ES for plugin"
docker run -d \
  --name es_tmp \
  --network common \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  -e ES_JAVA_OPTS="-Xms256m -Xmx256m" \
  -v /dockerProjects/elasticsearch/data:/usr/share/elasticsearch/data \
  docker.elastic.co/elasticsearch/elasticsearch:8.18.8

echo "Waiting for ES to be ready..."
sleep 25

echo "▶ Step 2: Install Nori"
docker exec es_tmp bash -c "yes | bin/elasticsearch-plugin install analysis-nori"

echo "▶ Step 3: Commit custom image"
docker stop es_tmp
docker commit es_tmp custom-elasticsearch:8.18.8-nori
docker rm es_tmp


# 8) Elasticsearch 최종 실행
docker run -d \
  --name elasticsearch \
  --restart unless-stopped \
  --network common \
  -p 9200:9200 \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  -e ES_JAVA_OPTS="-Xms512m -Xmx512m" \
  -v /dockerProjects/elasticsearch/data:/usr/share/elasticsearch/data \
  custom-elasticsearch:8.18.8-nori


# 9) APP 디렉토리 생성
mkdir -p /home/ec2-user/app
chown -R ec2-user:ec2-user /home/ec2-user/app

cd /home/ec2-user/app


# 10) .env 생성
cat > .env <<EOF
JWT_SECRET=${jwt_secret}
JWT_ACCESS_EXP=${jwt_access_exp}
JWT_REFRESH_EXP=${jwt_refresh_exp}

MYSQL_USERNAME=root
MYSQL_PASSWORD=${db_root_password}

GHCR_OWNER=${ghcr_owner}
GHCR_TOKEN=${ghcr_token}

SPRING_AI_OPENAI_API_KEY=${spring_ai_openai_api_key}
AI_HUGGINGFACE_API_KEY=${ai_huggingface_api_key}

SPRING_AI_VECTORSTORE_PINECONE_API_KEY=${spring_ai_vectorstore_pinecone_api_key}
SPRING_AI_VECTORSTORE_PINECONE_INDEX_NAME=${spring_ai_vectorstore_pinecone_index_name}

GMAIL_SENDER_EMAIL=${gmail_sender_email}
GMAIL_SENDER_PASSWORD=${gmail_sender_password}

UNSPLASH_BASE_URL=${unsplash_base_url}
UNSPLASH_ACCESS_KEY=${unsplash_access_key}

GOOGLE_BASE_URL=${google_base_url}
GOOGLE_API_KEY=${google_api_key}
GOOGLE_CX_ID=${google_cx_id}

KAKAO_CLIENT_ID=${kakao_client_id}
NAVER_CLIENT_ID=${naver_client_id}
NAVER_CLIENT_SECRET=${naver_client_secret}
GOOGLE_CLIENT_ID=${google_client_id}
GOOGLE_CLIENT_SECRET=${google_client_secret}

SPRING__DATASOURCE__URL=jdbc:mysql://mysql_1:3306/${app_db_name}?serverTimezone=Asia/Seoul&characterEncoding=UTF-8
SPRING__DATASOURCE__USERNAME=root
SPRING__DATASOURCE__PASSWORD=${db_root_password}

SPRING__REDIS__HOST=redis_1
SPRING__REDIS__PORT=6379
SPRING__REDIS__PASSWORD=${redis_password}

CLOUD_AWS_S3_BUCKET=${cloud_aws_s3_bucket}
CLOUD_AWS_CREDENTIALS_ACCESS_KEY=${cloud_aws_credentials_access_key}
CLOUD_AWS_CREDENTIALS_SECRET_KEY=${cloud_aws_credentials_secret_key}

SPRING_ELASTICSEARCH_URIS=http://elasticsearch:9200

PIXABAY_ACCESS_KEY=${pixabay_access_key}
PIXABAY_BASE_URL=${pixabay_base_url}

NPM_HOST=localhost:81
NPM_PROXY_ID=1
NPM_EMAIL=${npm_admin_email}
NPM_PASSWORD=${npm_admin_password}

PROD_OAUTH2_REDIRECT_URI=${PROD_OAUTH2_REDIRECT_URI}
EOF


# 11) docker-compose 생성
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  app-blue:
    image: ghcr.io/prgrms-aibe-devcourse/aibe3-finalproject-team4-backend:latest
    container_name: next5-app-blue
    restart: unless-stopped
    networks:
      - common
    expose:
      - "8080"
    env_file:
      - .env

  app-green:
    image: ghcr.io/prgrms-aibe-devcourse/aibe3-finalproject-team4-backend:latest
    container_name: next5-app-green
    restart: unless-stopped
    networks:
      - common
    expose:
      - "8080"
    env_file:
      - .env

networks:
  common:
    external: true

EOF


# 12) deploy.sh 생성
#!/bin/bash
set -e

cd /home/ec2-user/app

# .env 로드
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

echo "=== 🔍 Checking current live container ==="

# 현재 라이브 컨테이너 판단 (blue or green)
if docker ps --format "{{.Names}}" | grep -q "next5-app-blue"; then
  LIVE="blue"
  IDLE="green"
else
  LIVE="green"
  IDLE="blue"
fi

echo "🔵 LIVE: $LIVE"
echo "🟢 IDLE: $IDLE"
echo "======================================"

echo "=== 📦 Pulling latest backend image ==="
docker pull ghcr.io/prgrms-aibe-devcourse/aibe3-finalproject-team4-backend:latest

echo "=== 🚀 Deploying to IDLE container: $IDLE ==="
docker-compose up -d app-$IDLE

echo "=== ⏳ Health check starting... ==="

SUCCESS=false
for i in {1..20}; do
  # IDLE 컨테이너의 Docker 네트워크 IP 조회
  CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' next5-app-$IDLE || echo "")

  if [ -n "$CONTAINER_IP" ]; then
    if curl -fs "http://${CONTAINER_IP}:8080/actuator/health" | grep -q '"status":"UP"'; then
      SUCCESS=true
      break
    fi
  fi

  echo "⏳ Waiting for container to be UP... ($i/20)"
  sleep 3
done

if [ "$SUCCESS" = false ]; then
  echo "❌ Health check failed! Rolling back..."
  docker-compose stop app-$IDLE || true
  exit 1
fi

echo "✅ Health check passed!"

echo "=== 🔑 Logging in to NPM (session-based) ==="

LOGIN_RESPONSE=$(curl -s -X POST "http://${NPM_HOST}/api/tokens" \
  -H "Content-Type: application/json" \
  --data "{\"identity\": \"${NPM_EMAIL}\", \"secret\": \"${NPM_PASSWORD}\"}")

TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  echo "❌ NPM login failed!"
  echo "Response: $LOGIN_RESPONSE"
  exit 1
fi

echo "🔑 NPM login OK, token issued."

echo "=== 🔄 Switching NPM Proxy to IDLE container ==="

# forwardHost만 blue/green으로 바꿔주는 요청
curl -s -X PUT "http://${NPM_HOST}/api/nginx/proxy-hosts/${NPM_PROXY_ID}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{
    \"forwardScheme\": \"http\",
    \"forwardHost\": \"next5-app-$IDLE\",
    \"forwardPort\": 8080
  }" >/dev/null

echo "🎯 NPM switched → LIVE is now next5-app-$IDLE"

echo "=== 🧹 Cleaning up old LIVE container ==="
docker-compose stop app-$LIVE || true
docker-compose rm -f app-$LIVE || true

echo "=== 📄 Saving deploy info ==="

IMAGE_SHA=$(docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/prgrms-aibe-devcourse/aibe3-finalproject-team4-backend:latest || echo "unknown")

cat > deployed_version.txt <<EOF2
LIVE=$IDLE
DEPLOYED_AT=$(date '+%Y-%m-%d %H:%M:%S')
IMAGE_SHA=$IMAGE_SHA
EOF2

echo "🎉 Deployment complete → ACTIVE: next5-app-$IDLE"

EOF

chmod +x deploy.sh


# 13) 초기 Blue 환경 실행
docker-compose up -d next5-app-001

# 기존 스크립트 끝에 추가

# 14) 모니터링 스택 설정
mkdir -p /home/ec2-user/monitoring/{prometheus,grafana/provisioning/{datasources,dashboards}}
chown -R ec2-user:ec2-user /home/ec2-user/monitoring

# Prometheus 설정
cat > /home/ec2-user/monitoring/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 5s
  evaluation_interval: 5s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'spring-boot-apps'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: 
        - 'next5-app-001:8080'
        - 'next5-app-002:8080'
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: '(next5-app-.*):.*'
        replacement: '\$1'

  - job_name: 'mysql'
    static_configs:
      - targets: ['mysql_1:3306']
    
  - job_name: 'redis'
    static_configs:
      - targets: ['redis_1:6379']
EOF

# Grafana 데이터소스 프로비저닝
cat > /home/ec2-user/monitoring/grafana/provisioning/datasources/prometheus.yml <<EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://next5-prometheus:9090
    isDefault: true
EOF

# 모니터링 Docker Compose
cat > /home/ec2-user/monitoring/docker-compose.yml <<EOF
version: "3.8"

services:
  prometheus:
    image: prom/prometheus
    container_name: next5-prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=15d'
    networks:
      - common

  grafana:
    image: grafana/grafana
    container_name: next5-grafana
    restart: unless-stopped
    ports:
      - "3100:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin1234
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    depends_on:
      - prometheus
    networks:
      - common

  influxdb:
    image: influxdb:1.8
    container_name: next5-influxdb
    restart: unless-stopped
    ports:
      - "8086:8086"
    environment:
      - INFLUXDB_DB=next5
      - INFLUXDB_ADMIN_USER=admin
      - INFLUXDB_ADMIN_PASSWORD=admin1234
    volumes:
      - influxdb-data:/var/lib/influxdb
    networks:
      - common

volumes:
  prometheus-data:
  grafana-data:
  influxdb-data:

networks:
  common:
    external: true
EOF

# 모니터링 스택 시작
cd /home/ec2-user/monitoring
runuser -l ec2-user -c "cd /home/ec2-user/monitoring && docker-compose up -d"

echo "=== MONITORING SETUP DONE ==="

echo "=== INIT DONE ==="
