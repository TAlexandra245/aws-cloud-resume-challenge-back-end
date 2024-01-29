variable "lambda_function_name" {
  default = "VisitCountFunction"
  type = string
}

variable "endpoint_path" {
  description = "The GET endpoint path"
  type = string
  default = "ViewsCounter"
}