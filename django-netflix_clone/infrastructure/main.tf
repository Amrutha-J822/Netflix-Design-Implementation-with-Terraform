provider "aws" {
  region = var.aws_region
}

# VPC Configuration
resource "aws_vpc" "netflix_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "netflix-vpc-${var.environment}"
  }
}

# Create a public subnet
resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.netflix_vpc.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "netflix-public-subnet-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.netflix_vpc.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "netflix-public-subnet-b"
  }
}

# Create a DB subnet group
resource "aws_db_subnet_group" "netflix_db_subnet_group" {
  name       = "netflix-db-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = {
    Name = "Netflix DB Subnet Group"
  }
}

# Create an ElastiCache subnet group
resource "aws_elasticache_subnet_group" "netflix_cache_subnet_group" {
  name       = "netflix-cache-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

# Update the RDS instances to use the subnet group
resource "aws_db_instance" "primary" {
  identifier           = "netflix-db-primary-${var.environment}"
  engine              = "mysql"
  engine_version      = "8.4.3" # Use a supported version
  instance_class      = "db.t3.micro" # Compatible instance class
  allocated_storage   = 20
  username            = "admin"
  password            = "temppassword123"  # Change this in production!
  skip_final_snapshot = true
  db_subnet_group_name = aws_db_subnet_group.netflix_db_subnet_group.name
}

resource "aws_db_instance" "secondary" {
  identifier           = "netflix-db-secondary-${var.environment}"
  engine              = "mysql"
  engine_version      = "8.4.3" # Use a supported version
  instance_class      = "db.t3.micro" # Compatible instance class
  allocated_storage   = 20
  username            = "admin"
  password            = "temppassword123"  # Change this in production!
  skip_final_snapshot = true
  db_subnet_group_name = aws_db_subnet_group.netflix_db_subnet_group.name
}

# Update the ElastiCache cluster to use the subnet group
resource "aws_elasticache_cluster" "netflix_cache" {
  cluster_id           = "netflix-cache-${var.environment}"
  engine              = "redis"
  node_type           = "cache.t2.micro"
  num_cache_nodes     = 1
  port                = 6379
  subnet_group_name   = aws_elasticache_subnet_group.netflix_cache_subnet_group.name
}

# Security Layer
resource "aws_waf_ipset" "ip_blacklist" {
  name = "netflix-ip-blacklist-${var.environment}"
}

resource "aws_waf_rule" "ip_rate_limit" {
  name        = "netflix-ip-rate-limit-${var.environment}"
  metric_name = "netflixIpRateLimit${var.environment}"

  predicates {
    data_id = aws_waf_ipset.ip_blacklist.id
    negated = false
    type    = "IPMatch"
  }
}

resource "aws_waf_web_acl" "netflix_waf" {
  name        = "netflix-waf-${var.environment}"
  metric_name = "netflixWaf${var.environment}"

  default_action {
    type = "ALLOW"
  }

  rules {
    action {
      type = "BLOCK"
    }
    priority = 1
    rule_id  = aws_waf_rule.ip_rate_limit.id
    type     = "REGULAR"
  }
}

# Add the missing CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for Netflix content"
}

resource "aws_cloudfront_distribution" "netflix_cdn" {
  enabled = true
  
  origin {
    domain_name = aws_s3_bucket.content.bucket_regional_domain_name
    origin_id   = "S3Origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3Origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# API Layer
resource "aws_api_gateway_rest_api" "netflix_api" {
  name        = "netflix-api-${var.environment}"
  description = "Netflix API Gateway"
}

# Compute Layer
resource "aws_instance" "ec2_primary" {
  ami           = "ami-0c7217cdde317cfec"  # Amazon Linux 2023
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_a.id
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3 python3-pip git
              pip3 install django==4.0.2 Pillow==9.0.1
              EOF

  tags = {
    Name = "netflix-primary-${var.environment}"
  }
}

resource "aws_instance" "ec2_secondary" {
  ami           = "ami-0c7217cdde317cfec"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_b.id
  associate_public_ip_address = true

  tags = {
    Name = "netflix-secondary-${var.environment}"
  }
}

# Lambda Functions
resource "aws_iam_role" "lambda_role" {
  name = "netflix_lambda_role_${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_lambda_function" "content_processor" {
  filename      = data.archive_file.content_processor.output_path
  function_name = "netflix-content-processor-${var.environment}"
  role         = aws_iam_role.lambda_role.arn
  handler      = "index.handler"
  runtime      = "python3.9"

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }
}

# Storage Layer
resource "aws_s3_bucket" "content" {
  bucket_prefix = "netflix-content-${var.environment}"
}

# Monitoring
resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "netflix-cpu-alarm-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors EC2 CPU utilization"
  alarm_actions      = []
}

# Data source for Lambda ZIP files
data "archive_file" "content_processor" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/content-processor"
  output_path = "${path.module}/content-processor.zip"
}