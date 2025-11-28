#!/bin/bash
set -e

# 기본 설정
timedatectl set-timezone Asia/Seoul

# 스왑 4GB
dd if=/dev/zero of=/swapfile bs=128M count=32
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# Docker & Docker Compose 설치
dnf update -y
dnf install -y docker git

systemctl enable docker
systemctl start docker

# ec2-user docker 그룹 추가
usermod -aG docker ec2-user

# Docker Compose 설치
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true

# Docker Network
docker network create common || true

# GHCR 로그인
runuser -l ec2-user -c "echo '${ghcr_token}' | docker login ghcr.io -u '${ghcr_owner}' --password-stdin"

# 최초 backend 이미지 미리 Pull
runuser -l ec2-user -c "docker pull ghcr.io/${ghcr_owner}/aibe3-finalproject-team4-backend:latest || true"


# 1) MySQL
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


# 2) Redis
docker run -d \
  --name redis_1 \
  --restart unless-stopped \
  --network common \
  -p 6379:6379 \
  -e TZ=Asia/Seoul \
  redis:7 \
  redis-server --requirepass "${redis_password}"


# 🔥 3) Nginx Proxy Manager
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


# 4) Elasticsearch (+Nori 자동 설치)
# 컨테이너 실행
docker run -d \
  --name elasticsearch_1 \
  --restart unless-stopped \
  --network common \
  -p 9200:9200 \
  -e discovery.type=single-node \
  -e xpack.security.enabled=false \
  -e ES_JAVA_OPTS="-Xms256m -Xmx256m" \
  -e TZ=Asia/Seoul \
  -v /dockerProjects/elasticsearch_1/data:/usr/share/elasticsearch/data \
  docker.elastic.co/elasticsearch/elasticsearch:8.3.3

# ES 100% Ready까지 대기
echo "⏳ Waiting for Elasticsearch to start..."
for i in {1..30}; do
  if curl -s http://localhost:9200 >/dev/null; then
    echo "Elasticsearch is UP"
    break
  fi
  echo "Waiting ${i}/30..."
  sleep 3
done

# Nori plugin 자동 설치
echo "Installing Nori plugin..."
docker exec elasticsearch_1 bash -c "yes | bin/elasticsearch-plugin install analysis-nori"

# Elasticsearch 재시작
docker restart elasticsearch_1

echo "Waiting for Elasticsearch (after plugin install)…"
sleep 5


# APP 디렉토리 생성
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# .env 생성
cat > .env <<EOF
JWT_SECRET=${jwt_secret}

MYSQL_USERNAME=root
MYSQL_PASSWORD=${db_root_password}

GHCR_OWNER=${ghcr_owner}
GHCR_TOKEN=${ghcr_token}

AI_OPENAI_API_KEY=${ai_openai_api_key}
AI_HUGGINGFACE_API_KEY=${ai_huggingface_api_key}

PINECONE_API_KEY=${pinecone_api_key}
PINECONE_INDEX_NAME=${pinecone_index_name}

GMAIL_SENDER_EMAIL=${gmail_sender_email}
GMAIL_SENDER_PASSWORD=${gmail_sender_password}

UNSPLASH_ACCESS_KEY=${unsplash_access_key}
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

AWS_S3_BUCKET=${s3_bucket_name}

AWS_ACCESS_KEY=${aws_access_key}
AWS_SECRET_KEY=${aws_secret_key}

# ✔ Elasticsearch 컨테이너명 기반
ELASTIC_URL=http://elasticsearch_1:9200
EOF


# docker-compose.yml 생성
cat > docker-compose.yml <<EOF
version: "3.8"

services:
  next5-app-001:
    image: ghcr.io/${ghcr_owner}/aibe3-finalproject-team4-backend:latest
    container_name: next5-app-001
    restart: unless-stopped
    networks: [common]
    ports:
      - "8080:8080"
    env_file: [.env]
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - JAVA_OPTS=-Xms256m -Xmx384m

  next5-app-002:
    image: ghcr.io/${ghcr_owner}/aibe3-finalproject-team4-backend:latest
    container_name: next5-app-002
    restart: unless-stopped
    networks: [common]
    ports:
      - "8081:8080"
    env_file: [.env]
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - JAVA_OPTS=-Xms256m -Xmx384m
    profiles: [blue-green]

networks:
  common:
    external: true
EOF

# 🔥 deploy.sh 생성
cat > deploy.sh <<'EOF'
#!/bin/bash
set -e

cd /home/ec2-user/app

echo "=== Pulling latest image ==="
docker pull ghcr.io/${GHCR_OWNER}/aibe3-finalproject-team4-backend:latest

if docker ps | grep -q next5-app-001; then
  CURRENT="next5-app-001"
  NEW="next5-app-002"
  PORT_NEW=8081
else
  CURRENT="next5-app-002"
  NEW="next5-app-001"
  PORT_NEW=8080
fi

echo "Switching from $CURRENT to $NEW"

if [ "$NEW" = "next5-app-002" ]; then
  docker-compose --profile blue-green up -d next5-app-002
else
  docker-compose up -d next5-app-001
fi

echo "=== Health Check ==="
for i in {1..30}; do
  if curl -fs http://localhost:$PORT_NEW/actuator/health >/dev/null; then
    echo "Health OK"
    break
  fi
  echo "Waiting... $i/30"
  sleep 3
done

docker-compose stop $CURRENT || true
docker-compose rm -f $CURRENT || true

echo "Deployment complete → Active: $NEW"
EOF

chmod +x deploy.sh


# 🔥 초기 Blue 컨테이너 실행
docker-compose up -d next5-app-001

