###############################################################################
# Module: Database
# Aurora PostgreSQL Global Database + ElastiCache Redis
###############################################################################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "rds_config" {
  type = object({
    engine_version  = string
    instance_class  = string
    database_name   = string
    master_username = string
    allocated_storage = number
  })
}

variable "redis_config" {
  type = object({
    node_type       = string
    num_cache_nodes = number
    engine_version  = string
  })
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to access databases"
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Subnet Groups ──────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-${var.environment}-rds-subnet"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-rds-subnet"
  })
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.project_name}-${var.environment}-redis-subnet"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis-subnet"
  })
}

# ─── Security Groups ────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  vpc_id      = var.vpc_id
  description = "Security group for rds PostgreSQL"

  ingress {
    description     = "PostgreSQL from allowed SGs"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    # security_groups = var.allowed_security_group_ids
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.project_name}-redis-"
  vpc_id      = var.vpc_id
  description = "Security group for ElastiCache Redis"

  ingress {
    description     = "Redis from allowed SGs"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    # security_groups = var.allowed_security_group_ids
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-redis-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ─── rds Global Database ─────────────────────────────────────────────────
resource "aws_db_instance" "postgres" {
  identifier = "${var.project_name}-${var.environment}-postgres"

  engine         = "postgres"
  engine_version = var.rds_config.engine_version
  instance_class = var.rds_config.instance_class

  allocated_storage = var.rds_config.allocated_storage
  storage_type      = "gp3"

  db_name  = var.rds_config.database_name
  username = var.rds_config.master_username
  password = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = true

  backup_retention_period = 1
  skip_final_snapshot     = true

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-postgres"
  })

  depends_on = [
    aws_iam_role_policy_attachment.rds_monitoring
  ]
}

resource "random_password" "db_master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db_master" {
  name = "${var.project_name}/${var.environment}/postgres-credentials-v2"
}

resource "aws_secretsmanager_secret_version" "db_master" {
  secret_id = aws_secretsmanager_secret.db_master.id

  secret_string = jsonencode({
    username = var.rds_config.master_username
    password = random_password.db_master.result
    host     = aws_db_instance.postgres.address
    port     = 5432
    dbname   = var.rds_config.database_name
  })
}

resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-${var.environment}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ─── ElastiCache Redis (Replication Group) ──────────────────────────────────
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.project_name}-${var.environment}-redis"
  description          = "ElastiCache Redis for ${var.project_name}"

  node_type            = var.redis_config.node_type
  num_cache_clusters   = var.redis_config.num_cache_nodes
  engine_version       = var.redis_config.engine_version
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth[0].result

  automatic_failover_enabled = var.redis_config.num_cache_nodes > 1
  multi_az_enabled           = var.redis_config.num_cache_nodes > 1

  snapshot_retention_limit = 7
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:07:00"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-redis"
  })
}

resource "random_password" "redis_auth" {
  count   = 1
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name = "${var.project_name}/${var.environment}/redis-auth-token"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth[0].result
    endpoint   = aws_elasticache_replication_group.redis.primary_endpoint_address
    port       = 6379
  })
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "aurora_security_group_id" {
  value = aws_security_group.rds.id
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "db_endpoint" {
  value = aws_db_instance.postgres.address
}

output "db_port" {
  value = aws_db_instance.postgres.port
}

output "db_id" {
  value = aws_db_instance.postgres.id
}