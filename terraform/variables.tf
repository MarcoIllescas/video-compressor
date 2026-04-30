variable "aws_region" {
    description = "The AWS region to deploy resources in."
    type        = string
    default     = "us-east-1"
}

variable "aws_access_key" {
    type    = string
    default = "value"
}

variable "aws_secret_key" {
    type    = string
    default = "value"
}

variable "use_localstack" {
    description = "Whether to use LocalStack for testing."
    type        = bool
    default     = true
}

variable "localstack_endpoint" {
    description = "The endpoint URL for LocalStack services."
    type        = string
    default     = "http://localhost:4566"
}