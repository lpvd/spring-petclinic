output "ec2_public_ip" {
  value       = aws_instance.app.public_ip
  description = "EC2_HOST in GitHub Secrets and ansible/inventory.ini"
}

output "rds_host" {
  value       = aws_db_instance.mysql.address
  description = "RDS_HOST in GitHub Secrets"
}

output "ecr_registry" {
  value       = aws_ecr_repository.app.repository_url
  description = "ECR_REGISTRY in GitHub Secrets"
}

output "alb_dns" {
  value       = aws_lb.main.dns_name
  description = "public URL of the app"
}
