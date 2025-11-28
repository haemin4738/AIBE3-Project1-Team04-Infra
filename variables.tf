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

variable "ai_huggingface_api_key" {
  type        = string
  sensitive   = true
}

# Pinecone Vector DB
variable "pinecone_api_key" {
  type        = string
  sensitive   = true
}

variable "pinecone_index_name" {
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
variable "unsplash_access_key" {
  type      = string
  sensitive = true
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
variable "s3_bucket_name" {
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

variable "elastic_url" {
  type        = string
  description = "ElasticSearch URL"
  sensitive = true
}
variable "aws_access_key" {
  type        = string
  description = "AWS Access Key"
  sensitive = true
}
variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Key"
  sensitive = true
}