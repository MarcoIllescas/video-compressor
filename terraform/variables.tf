variable "aws_region" {
    description = "The AWS region to deploy resources in."
    type        = string
    default     = "us-east-1"
}

variable "localstack_endpoint" {
    description = "The endpoint URL for LocalStack services."
    type        = string
    default     = "http://localhost:4566"
}