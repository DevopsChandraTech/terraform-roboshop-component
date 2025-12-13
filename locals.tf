locals {
    ami_id = data.aws_ami.ami_id.id
    vpc_id = data.aws_ssm_parameter.vpc_id.value
    sg_id = data.aws_ssm_parameter.sg_id.value
    private_subnet_ids = split("," , data.aws_ssm_parameter.private_subnet_id.value)[0] #["10.0.1.0/24","10.0.2.0/24"] its comes with list we split that list
    tg_port = "${var.component}" == "frontend" ? 80 : 8080
    health_check_path = "${var.component}" == "frontend" ? "/" : "/health"
    backend_alb_listener_arn = data.aws_ssm_parameter.backend_alb_listener_arn.value
    frontend_alb_listener_arn = data.aws_ssm_parameter.frontend_alb_listener_arn.value
    listener_arn = "${var.component}" == "frontend" ? local.frontend_alb_listener_arn : local.backend_alb_listener_arn
    host_context = "${var.component}" == "frontend" ? "${var.project_name}-${var.environment}.${var.domain_name}" : "${var.component}.backend-alb-${var.environment}.${var.domain_name}"
    common_name_suffix = "${var.project_name}-${var.environment}" #roboshop-dev
    common_tags = {
        Project = "roboshop"
        Environment = "dev"
        Terraform = "true"
    }
}

