provider "aws" {
  region = "us-west-2"
}

data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }

  owners = ["979382823631"]
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.13.0"

  name   = "blog"
  vpc_id = module.blog_vpc.vpc_id

  ingress_rules       = ["https-443-tcp", "http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  # Permit backend traffic between resources using this security group.
  ingress_with_self = [
    {
      rule = "http-8080-tcp"
    }
  ]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_instance" "blog" {
  ami                         = data.aws_ami.app_ami.id
  instance_type               = var.instance_type
  subnet_id                   = module.blog_vpc.public_subnets[0]
  vpc_security_group_ids      = [module.blog_sg.security_group_id]
  associate_public_ip_address = true

  tags = {
    Name = "Learning Terraform"
  }
}

module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "10.5.1"

  name               = "blog-alb"
  load_balancer_type = "application"

  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.blog_sg.security_group_id]

  listeners = {
    ex-http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "blog"
      }
    }
  }

  target_groups = {
    blog = {
      name             = "blog-tg"
      protocol         = "HTTP"
      port             = 8080
      target_type      = "instance"
      create_attachment = false

      targets = {
        blog = {
          target_id = aws_instance.blog.id
          port      = 8080
        }
      }

      health_check = {
        enabled  = true
        protocol = "HTTP"
        path     = "/"
        matcher  = "200-399"
      }
    }
  }

  tags = {
    Environment = "dev"
  }
}
```
