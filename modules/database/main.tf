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

variable "aurora_config" {
  type = object({
    engine_version  = string
    instance_class  = string
    instance_count  = number
    database_name   = string
    master_username = string
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

variable "is_global_primary" {
  description = "Whether this is the primary cluster for Aurora Global"
  type        = bool
  default     = true
}

variable "global_cluster_identifier" {
  description = "Aurora Global cluster identifier (for DR secondary)"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ─── Subnet Groups ──────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-${var.environment}-aurora-subnet"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-subnet"
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
resource "aws_security_group" "aurora" {
  name_prefix = "${var.project_name}-aurora-"
  vpc_id      = var.vpc_id
  description = "Security group for Aurora PostgreSQL"

  ingress {
    description     = "PostgreSQL from allowed SGs"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-aurora-sg"
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
    security_groups = var.allowed_security_group_ids
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

# ─── Aurora Global Database ─────────────────────────────────────────────────
resource "aws_rds_global_cluster" "this" {
  count = var.is_global_primary ? 1 : 0

  global_cluster_identifier = "${var.project_name}-global-aurora"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_config.engine_version
  database_name             = var.aurora_config.database_name
  storage_encrypted         = true
}

# ─── Aurora Cluster ──────────────────────────────────────────────────────────
resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.project_name}-${var.environment}-aurora"
  engine             = "aurora-postgresql"
  engine_version     = var.aurora_config.engine_version

  # Only set these for primary cluster
  database_name   = var.is_global_primary ? var.aurora_config.database_name : null
  master_username = var.is_global_primary ? var.aurora_config.master_username : null
  master_password = var.is_global_primary ? random_password.aurora_master[0].result : null

  global_cluster_identifier = var.is_global_primary ? aws_rds_global_cluster.this[0].id : var.global_cluster_identifier

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]

  storage_encrypted = true
  storage_type      = "aurora-iopt1"

  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = var.environment != "prod"
  deletion_protection     = var.environment == "prod"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.aurora_config.instance_class == "db.serverless" ? [1] : []
    content {
      max_capacity = var.aurora_config.max_capacity
      min_capacity = var.aurora_config.min_capacity
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora"
    Role = var.is_global_primary ? "Primary-Writer" : "DR-Reader"
  })

  lifecycle {
    ignore_changes = [master_password]
  }
}

resource "random_password" "aurora_master" {
  count   = var.is_global_primary ? 1 : 0
  length  = 32
  special = false
}

# Store master password in Secrets Manager
resource "aws_secretsmanager_secret" "aurora_master" {
  count = var.is_global_primary ? 1 : 0
  name  = "${var.project_name}/${var.environment}/aurora-master-password"
  tags  = var.tags
}

resource "aws_secretsmanager_secret_version" "aurora_master" {
  count     = var.is_global_primary ? 1 : 0
  secret_id = aws_secretsmanager_secret.aurora_master[0].id
  secret_string = jsonencode({
    username = var.aurora_config.master_username
    password = random_password.aurora_master[0].result
    host     = aws_rds_cluster.this.endpoint
    port     = 5432
    dbname   = var.aurora_config.database_name
  })
}

# ─── Aurora Instances ────────────────────────────────────────────────────────
resource "aws_rds_cluster_instance" "this" {
  count = var.aurora_config.instance_count

  identifier         = "${var.project_name}-${var.environment}-aurora-${count.index}"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = var.aurora_config.instance_class
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version

  db_subnet_group_name = aws_db_subnet_group.aurora.name

  performance_insights_enabled = true
  monitoring_interval          = 60
  monitoring_role_arn          = aws_iam_role.rds_monitoring.arn

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-aurora-${count.index}"
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
output "aurora_cluster_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "aurora_reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "aurora_cluster_id" {
  value = aws_rds_cluster.this.id
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "global_cluster_identifier" {
  value = var.is_global_primary ? aws_rds_global_cluster.this[0].id : var.global_cluster_identifier
}
