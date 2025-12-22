# Base Infra Config
variable "region" {
  type        = string
  default     = "ap-northeast-2"
  description = "AWS Region"
}

variable "prefix" {
  type        = string
  default     = "team4-next5"
}

variable "team_tag_value" {
  type    = string
  default = "devcos-team04"
}

variable "ec2_instance_type" {
  type        = string
  default     = "t3.small"
}

variable "ec2_key_name" {
  type = string
  description = "AWS EC2 SSH KeyPair name"
}

# Docker Image / GHCR
variable "ghcr_owner" {
  type        = string
  description = "GitHub Container Registry owner (organization or username)"
}

variable "ghcr_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token for GHCR login"
}

# Application
variable "app_domain" {
  type        = string
  description = "Backend domain"
  default     = "api.haemin.shop"
}

variable "app_db_name" {
  type        = string
  default     = "team4_next5_db"
}


# MySQL / Redis
variable "db_root_password" {
  type        = string
  sensitive   = true
}

variable "redis_password" {
  type        = string
  sensitive   = true
}


# JWT
variable "jwt_secret" {
  type        = string
  sensitive   = true
}

# AI API Keys
variable "ai_openai_api_key" {
  type        = string
  sensitive   = true
}

variable "spring_ai_openai_api_key" {
  type        = string
  sensitive   = true
}

variable "ai_huggingface_api_key" {
  type        = string
  sensitive   = true
}

# Pinecone Vector DB
variable "spring_ai_vectorstore_pinecone_api_key" {
  type        = string
  sensitive   = true
}

variable "spring_ai_vectorstore_pinecone_index_name" {
  type        = string
}

# Mail (Gmail SMTP)
variable "gmail_sender_email" {
  type = string
}

variable "gmail_sender_password" {
  type      = string
  sensitive = true
}

# External APIs
variable "unsplash_base_url" {
  type = string
}
variable "unsplash_access_key" {
  type      = string
  sensitive = true
}

variable "google_base_url" {
  type = string
}
variable "google_api_key" {
  type      = string
  sensitive = true
}

variable "google_cx_id" {
  type = string
}

# OAuth2 Credentials
variable "kakao_client_id" {
  type      = string
  sensitive = true
}

variable "naver_client_id" {
  type      = string
  sensitive = true
}

variable "naver_client_secret" {
  type      = string
  sensitive = true
}

variable "google_client_id" {
  type      = string
  sensitive = true
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}

# S3
variable "cloud_aws_s3_bucket" {
  type = string
}

variable "cloud_aws_region_static" {
  type = string

}

# NPM
variable "npm_admin_email" {
  type        = string
  description = "Initial admin email for Nginx Proxy Manager"
}

variable "npm_admin_password" {
  type        = string
  description = "Initial admin password for Nginx Proxy Manager"
  sensitive   = true
}

variable "spring_elasticsearch_uris" {
  type        = string
  description = "ElasticSearch URL"
  sensitive = true
}
variable "cloud_aws_credentials_access_key" {
  type        = string
  description = "AWS Access Key"
  sensitive = true
}
variable "cloud_aws_credentials_secret_key" {
  type        = string
  description = "AWS Secret Key"
  sensitive = true
}

variable "jwt_access_exp" {
  type       = number
  description = "JWT Access Token Expiration Time in milliseconds"
}

variable "jwt_refresh_exp" {
  type       = number
  description = "JWT Refresh Token Expiration Time in milliseconds"
}

variable "mail_host" {
  type        = string
  description = "Mail service host"
}
variable "mail_port" {
  type        = number
  description = "Mail service port"
}
variable "mail_protocol" {
  type        = string
  description = "Mail service protocol"
}

variable "pixabay_access_key" {
  type      = string
  sensitive = true
}

variable "pixabay_base_url" {
  type = string
}

variable "PROD_OAUTH2_REDIRECT_URI" {
  type      = string
  description = "Production OAuth2 Redirect URI"
}

variable "google_cloud_credentials_json" {
  type      = string
  sensitive = true
}

variable "npm_host" {
  type        = string
  description = "NPM Host"
  default     = "localhost:81"
}

variable "npm_proxy_id" {
  type        = string
  description = "NPM Proxy ID"
  default     = "1"
}