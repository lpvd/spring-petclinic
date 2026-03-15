# terraform/main.tf

# ── VPC ───────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true   # to resolve RDS endpoint by name
  enable_dns_support   = true

  tags = { Name = "${var.project_name}-vpc" }
}

# ── Internet Gateway ──────────────────────────────────────────────────
# So that resources in public subnets can go to internet and accept incoming traffic
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-igw" }
}

# ── Public subnets — for EC2 and ALB ─────────────────────────────────────
# Two public subnets in different AZ — ALB requires minimum 2 AZ
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true   # EC2 automatically gets public IP

  tags = { Name = "${var.project_name}-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-b" }
}

# ── Private subnets — only for RDS  ───────────────────────────────────
# Without route to internet — RDS is not accessible from the outside
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "${var.project_name}-private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"   # RDS subnet group requitres 2 different AZ

  tags = { Name = "${var.project_name}-private-b" }
}

# ── Route table for public subnets  ─────────────────────────────────────
# Redirects all external traffic to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

# Link route table to each public subnet
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ── Security Groups ─────────────────────────────────────────────────────

# ALB — accepts HTTP from any IP
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# EC2 — SSH from anywhere (github changes IP ranges of their runners), app - only from ALB
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow SSH from my IP and app traffic from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # used to be [var.my_ip]
  }

  ingress {
    description     = "App port from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-app-sg" }
}

# RDS — MySQL only from EC2
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL from app EC2 only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from app only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = { Name = "${var.project_name}-rds-sg" }
}

# ── SSH Key Pair ────────────────────────────────────────────────────────
# Terraform loads public key to AWS
# Private key is stored locally
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-key"
  public_key = file("~/.ssh/petclinic-key.pub")
}

# ── IAM Role для EC2 ────────────────────────────────────────────────────
# Allows EC2 to go to ECR and CloudWatch without extra credentials
resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"

  # Allows EC2 service to take this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-ec2-role" }
}

# Link an existing AWS policy — only reading images from ECR
resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Link an existing AWS policy — write metrics to CloudWatch
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Instance Profile — a "wrapper" around IAM Role
# EC2 can't use a Role directly — only via Instance Profile
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# ── AMI — find a supported Amazon Linux 2023 automatically ───────────
# Instead of hardcoding ami-xxxxxxxx which will be outdated in a few months
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── EC2 Instance ────────────────────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Larger memory — default 8GB is not enough for Docker images
  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = "${var.project_name}-app" }
}

# ── RDS Subnet Group ────────────────────────────────────────────────────
# RDS requires subnet with at least 2 AZ
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Subnet group for petclinic RDS"
  subnet_ids  = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = { Name = "${var.project_name}-db-subnet-group" }
}

# ── RDS Parameter Group ─────────────────────────────────────────────────
# Configure MySQL for spring-petclinic — UTF8 encoding
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.project_name}-mysql8"
  family = "mysql8.0"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = { Name = "${var.project_name}-mysql8" }
}

# ── RDS Instance ────────────────────────────────────────────────────────
resource "aws_db_instance" "mysql" {
  # Ifentification
  identifier = "${var.project_name}-mysql"
  db_name    = var.db_name

  # Engine
  engine         = "mysql"
  engine_version = "8.0"

  # Storage
  instance_class    = var.db_instance_class   # db.t3.micro
  allocated_storage = 20                       # GB

  # Credentials
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false   # only from VPC

  # Config
  parameter_group_name = aws_db_parameter_group.mysql.name
  storage_type         = "gp2"
  storage_encrypted    = true

  # Backup
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Just for simplicity of this project — remove protection from deletion
  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true

  # Multi-AZ is turned off too
  multi_az = false

  tags = { Name = "${var.project_name}-mysql" }
}

# ── Application Load Balancer ───────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false              # публічний, доступний з інтернету
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id               # ALB вимагає мінімум 2 AZ
  ]

  tags = { Name = "${var.project_name}-alb" }
}

# ── Target Group ────────────────────────────────────────────────────────
# Група серверів куди ALB направляє трафік
# Зараз там буде один EC2 instance
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 8080                         # порт на якому слухає spring-petclinic
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"            # ALB перевіряє цей URL
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2              # 2 успішні перевірки → healthy
    unhealthy_threshold = 3              # 3 невдалі → unhealthy
    interval            = 30             # перевіряє кожні 30 секунд
    timeout             = 5
    matcher             = "200-399"      # будь-який з цих кодів = успіх
  }

  tags = { Name = "${var.project_name}-tg" }
}

# ── Listener ────────────────────────────────────────────────────────────
# ALB is listening to port 80 and redirects traffic to the target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── Target Group Attachment ─────────────────────────────────────────────
# Register EC2 instance in target group
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 8080
}

# ── ECR Repository ──────────────────────────────────────────────────────
# Add here to not create a separate file
resource "aws_ecr_repository" "app" {
  name         = "spring-petclinic"
  force_delete = true    # allows deleting the repo even if there are images

  tags = { Name = "${var.project_name}-ecr" }
}
