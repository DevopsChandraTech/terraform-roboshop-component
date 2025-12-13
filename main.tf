resource "aws_instance" "main" {
  ami           = local.ami_id
  instance_type = "t3.micro"
  vpc_security_group_ids = [local.sg_id]
  subnet_id = local.private_subnet_id
  tags = merge(
    local.common_tags,
    {
      Name = "${local.common_name_suffix}-catalogue" #roboshop-dev-catalogue
    }
  )
}

resource "terraform_data" "main" { #if instance id replaced it can be triggered
    triggers_replace =  [
      aws_instance.main.id
  ] 

  connection {
    type        = "ssh"
    user        = "ec2-user"
    password    = "DevOps321"
    host        = aws_instance.main.private_ip
  }

  provisioner "file" {
    source = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment}"
    ]
  }
}

resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped"
  depends_on = [ terraform_data.main ]
}

resource "aws_ami_from_instance" "main" {
  name               = "${local.common_name_suffix}-${var.component}-ami"
  source_instance_id = aws_instance.main.id
  depends_on = [ aws_ec2_instance_state.main ]
  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-${var.component}-ami"
    }
  )
}

resource "aws_lb_target_group" "main" {
  name     = "${local.common_name_suffix}-${var.component}"
  port     = local.tg_port #if frontend port number is 80 otherwise port number is 8080
  protocol = "HTTP"
  vpc_id   = local.vpc_id
  deregistration_delay = 60 # waiting for instance deletion then instance deleted

  health_check {
    enabled   = true
    healthy_threshold = 2
    unhealthy_threshold = 2
    interval = 10
    matcher = "200-299"
    protocol = "HTTP"
    port = local.tg_port
    path = local.health_check_path
    timeout = 2
  }
}

resource "aws_launch_template" "main" {
  name = "${local.common_name_suffix}-${var.component}"
  image_id = aws_ami_from_instance.main.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t3.micro"

  vpc_security_group_ids = [local.sg_id]
  # when we run terraform apply again, a new version will be created with new AMI ID
  update_default_version = true

  # tags attached to the instance
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name_suffix}-${var.component}"
      }
    )
  }
  # tags attached to the volume created by instance
  tag_specifications {
    resource_type = "volume"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name_suffix}-${var.component}"
      }
    )
  }
    # tags attached to the launch template
  tags = merge(
      local.common_tags,
      {
        Name = "${local.common_name_suffix}-${var.component}"
      }
  )
}

resource "aws_autoscaling_group" "main" { #likes HR
  name                      = "${local.common_name_suffix}-${var.component}"
  max_size                  = 10
  min_size                  = 1
  health_check_grace_period = 100
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = false
  launch_template {
    id = aws_launch_template.main.id
    version = aws_launch_template.main.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50 # atleast 50% of the instances should be up and running
    }
    triggers = ["launch_template"]
  }

  vpc_zone_identifier       = local.private_subnet_ids
  target_group_arns = [aws_lb_target_group.main.arn]

  dynamic "tag" {
    for_each = merge(
      local.common_tags,
      {
        Name = "${local.common_name_suffix}-${var.component}"
      }
    )
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  timeouts {
      delete = "15m"
  }
}

resource "aws_autoscaling_policy" "main" {
  autoscaling_group_name = aws_autoscaling_group.main.name
  name                   = "${local.common_name_suffix}-${var.component}"
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0
  }
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = local.listener_arn
  priority     = var.rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
  #host_header --> ex : netbanking.icicibank.com --> this is most preferrable
  #context_header --> ex : icicibank.com/netbanking/cart
  condition {
    host_header {
      values = [ local.host_context ]
    }
  }
}

resource "terraform_data" "main-local" { #if instance id replaced it can be triggered
  triggers_replace =  [
      aws_instance.main.id
  ] 

  depends_on = [ aws_autoscaling_policy.main ]

  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
}

