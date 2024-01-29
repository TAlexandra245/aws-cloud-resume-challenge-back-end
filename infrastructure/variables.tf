variable "lambda_function_name" {
  default = "VisitCounterFunction"
  type    = string
}

variable "my_region" {
  type    = string
  default = "us-east-1"
}

variable "accountId" {
  type = string
}
variable "endpoint_path" {
  description = "The GET endpoint path"
  type        = string
  default     = "count"
}