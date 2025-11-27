#!/bin/bash
set -e

# 기본 설정
timedatectl set-timezone Asia/Seoul

# 스왑 4GB 설정
dd if=/dev/zero of=/swapfile bs=128M count=32
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# Docker 설치
dnf update -y
dnf install -y docker git curl

systemctl enable docker
systemctl start docker

# Docker Compose 설치
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true

# Docker 네트워크
docker network create common || true

# MySQL 컨테이너 (메모리 최적화 옵션 추가)
docker run -d \
  --name mysql_1 \
  --restart unless-stopped \
  --network common \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=${var.db_root_password} \
  -e MYSQL_DATABASE=${var.app_db_name} \
  -e TZ=Asia/Seoul \
  -v /dockerProjects/mysql_1/data:/var/lib/mysql \
  mysql:8.0 \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci \
  --default-time-zone=+09:00 \
  --performance_schema=OFF \
  --innodb_buffer_pool_size=256M

# Redis 컨테이너 (비밀번호 설정)
docker run -d \
  --name redis_1 \
  --restart unless-stopped \
  --network common \
  -p 6379:6379 \
  -e TZ=Asia/Seoul \
  redis:7 \
  redis-server --requirepass "${var.redis_password}"

# Nginx Proxy Manager
docker run -d \
  --name npm_1 \
  --restart unless-stopped \
  --network common \
  -p 80:80 \
  -p 81:81 \
  -p 443:443 \
  -e TZ=Asia/Seoul \
  -e INITIAL_ADMIN_EMAIL=${var.npm_admin_email} \
  -e INITIAL_ADMIN_PASSWORD=${var.npm_admin_password} \
  -v /dockerProjects/npm_1/data:/data \
  -v /dockerProjects/npm_1/letsencrypt:/etc/letsencrypt \
  jc21/nginx-proxy-manager:latest

# ElasticSearch 컨테이너 (t3.small 최적화)
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

# GHCR 로그인
echo "${var.ghcr_token}" | docker login ghcr.io -u ${var.ghcr_owner} --password-stdin

# 애플리케이션 디렉토리 생성
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# .env 파일 생성
cat > .env <<ENV_EOF
# JWT
JWT_SECRET=${var.jwt_secret}

# DB
MYSQL_USERNAME=root
MYSQL_PASSWORD=${var.db_root_password}

# AI
AI_OPENAI_API_KEY=${var.ai_openai_api_key}
AI_HUGGINGFACE_API_KEY=${var.ai_huggingface_api_key}

# VECTOR DB
PINECONE_API_KEY=${var.pinecone_api_key}
PINECONE_INDEX_NAME=${var.pinecone_index_name}

# EMAIL
GMAIL_SENDER_EMAIL=${var.gmail_sender_email}
GMAIL_SENDER_PASSWORD=${var.gmail_sender_password}

# EXTERNAL API
UNSPLASH_ACCESS_KEY=${var.unsplash_access_key}
GOOGLE_API_KEY=${var.google_api_key}
GOOGLE_CX_ID=${var.google_cx_id}

# OAUTH2
KAKAO_CLIENT_ID=${var.kakao_client_id}
NAVER_CLIENT_ID=${var.naver_client_id}
NAVER_CLIENT_SECRET=${var.naver_client_secret}
GOOGLE_CLIENT_ID=${var.google_client_id}
GOOGLE_CLIENT_SECRET=${var.google_client_secret}

# SPRING DB/REDIS HOSTS
SPRING__DATASOURCE__URL=jdbc:mysql://mysql_1:3306/${var.app_db_name}?serverTimezone=Asia/Seoul&characterEncoding=UTF-8
SPRING__DATASOURCE__USERNAME=root
SPRING__DATASOURCE__PASSWORD=${var.db_root_password}

SPRING__REDIS__HOST=redis_1
SPRING__REDIS__PORT=6379
SPRING__REDIS__PASSWORD=${var.redis_password}

# S3
AWS_S3_BUCKET=${var.s3_bucket_name}

ENV_EOF

# docker-compose.yml 생성
cat > docker-compose.yml <<COMPOSE_EOF
version: "3.8"

services:
  next5-app-001:
    image: ghcr.io/${var.ghcr_owner}/AIBE3_FinalProject_Team4_BE/backend:latest
    container_name: next5-app-001
    restart: unless-stopped
    networks: [common]
    ports:
      - "8080:8080"
    env_file:
      - .env
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - JAVA_OPTS=-Xms256m -Xmx384m

  next5-app-002:
    image: ghcr.io/${var.ghcr_owner}/AIBE3_FinalProject_Team4_BE/backend:latest
    container_name: next5-app-002
    restart: unless-stopped
    networks: [common]
    ports:
      - "8081:8080"
    env_file:
      - .env
    environment:
      - SPRING_PROFILES_ACTIVE=prod
      - JAVA_OPTS=-Xms256m -Xmx384m
    profiles:
      - blue-green

networks:
  common:
    external: true
COMPOSE_EOF

# deploy.sh 생성
cat > deploy.sh <<'DEPLOY_EOF'
#!/bin/bash
set -e

cd /home/ec2-user/app

echo "=== Pulling latest image ==="
docker pull ghcr.io/${var.ghcr_owner}/AIBE3_FinalProject_Team4_BE/backend:latest

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
  if curl -fs http://localhost:$PORT_NEW/actuator/health > /dev/null; then
    echo "Health OK"
    break
  fi
  echo "Waiting ($i/30)"
  sleep 3
done

echo "=== Updating Proxy Manager Forward Host ==="
docker exec npm_1 sqlite3 /data/database.sqlite \
  "UPDATE proxy_host SET forward_host='$NEW' WHERE domain_names LIKE '%${var.app_domain}%';"

docker exec npm_1 nginx -s reload || true

docker-compose stop $CURRENT || true
docker-compose rm -f $CURRENT || true

echo "Deployment complete → Active: $NEW"
DEPLOY_EOF

chmod +x deploy.sh

# 초기 Blue 컨테이너 실행
docker-compose up -d next5-app-001
