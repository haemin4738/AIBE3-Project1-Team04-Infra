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

# Docker & Git 설치
dnf update -y
dnf install -y docker git

systemctl enable docker
systemctl start docker

# Docker Compose 설치
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose || true

# Docker Network
docker network create common || true

# MySQL
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

# Redis
docker run -d \
  --name redis_1 \
  --restart unless-stopped \
  --network common \
  -p 6379:6379 \
  -e TZ=Asia/Seoul \
  redis:7 \
  redis-server --requirepass "${redis_password}"

# Nginx Proxy Manager
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

# ElasticSearch
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
echo "${ghcr_token}" | docker login ghcr.io -u ${ghcr_owner} --password-stdin

# 애플리케이션 디렉토리
mkdir -p /home/ec2-user/app
cd /home/ec2-user/app

# .env 생성
cat > .env <<EOF
JWT_SECRET=${jwt_secret}

MYSQL_USERNAME=root
MYSQL_PASSWORD=${db_root_password}

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
      SPRING_PROFILES_ACTIVE=prod
      JAVA_OPTS=-Xms256m -Xmx384m

  next5-app-002:
    image: ghcr.io/${ghcr_owner}/aibe3-finalproject-team4-backend:latest
    container_name: next5-app-002
    restart: unless-stopped
    networks: [common]
    ports:
      - "8081:8080"
    env_file: [.env]
    environment:
      SPRING_PROFILES_ACTIVE=prod
      JAVA_OPTS=-Xms256m -Xmx384m
    profiles: [blue-green]

networks:
  common:
    external: true
EOF

# deploy.sh 생성
cat > deploy.sh <<'EOF'
#!/bin/bash
set -e

cd /home/ec2-user/app

echo "=== Pulling latest image ==="
docker pull ghcr.io/${ghcr_owner}/aibe3-finalproject-team4-backend:latest

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
  echo "Waiting... $i/30"
  sleep 3
done

echo "=== Updating Proxy Manager Forward Host ==="
docker exec npm_1 sqlite3 /data/database.sqlite \
  "UPDATE proxy_host SET forward_host='$NEW' WHERE domain_names LIKE '%${app_domain}%';"

docker exec npm_1 nginx -s reload || true

docker-compose stop $CURRENT || true
docker-compose rm -f $CURRENT || true

echo "Deployment complete → Active: $NEW"
EOF

chmod +x deploy.sh

# 초기 Blue 컨테이너 실행
docker-compose up -d next5-app-001
