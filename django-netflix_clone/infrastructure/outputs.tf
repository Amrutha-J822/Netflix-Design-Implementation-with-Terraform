# outputs.tf

# API Gateway URL
output "api_gateway_url" {
  value       = aws_api_gateway_rest_api.netflix_api.execution_arn
  description = "URL of the API Gateway endpoint"
}

# CloudFront Domain
output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.netflix_cdn.domain_name
  description = "Domain name of the CloudFront distribution"
}

# Primary EC2 Instance Public IP
output "primary_ec2_public_ip" {
  value       = aws_instance.ec2_primary.public_ip
  description = "Public IP of the primary EC2 instance"
}

# Secondary EC2 Instance Public IP
output "secondary_ec2_public_ip" {
  value       = aws_instance.ec2_secondary.public_ip
  description = "Public IP of the secondary EC2 instance"
}

# RDS Primary Endpoint
output "rds_primary_endpoint" {
  value       = aws_db_instance.primary.endpoint
  description = "Endpoint of the primary RDS instance"
}

# RDS Secondary Endpoint
output "rds_secondary_endpoint" {
  value       = aws_db_instance.secondary.endpoint
  description = "Endpoint of the secondary RDS instance"
}

# ElastiCache Endpoint
output "elasticache_endpoint" {
  value       = aws_elasticache_cluster.netflix_cache.configuration_endpoint
  description = "Endpoint of the ElastiCache cluster"
}
