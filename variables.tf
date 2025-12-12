variable "project_name" {
    type = string
}

variable "environment" {
    type = string
    default = ""
}

variable "component" { #[catalogue,user,shipping,payment]
    type = string
    default = ""
}

variable "rule_priority" {
    default = ""
}

variable "domain_name" {
    type = string
}