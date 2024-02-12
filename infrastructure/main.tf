terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

#terraform {
#  backend "s3" {
#    bucket = "terraform-file-state"
#    key ="global/s3/terraform.tfstate"
#    region = "us-east-1"
#    dynamodb_table = "terraform-state-locking"
#    encrypt = true
#  }
#}


provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

#S3 bucket
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-file-state"

  lifecycle {
    prevent_destroy = true
  }

  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}
# DynamoDB Table
resource "aws_dynamodb_table" "visitor_count_ddb" {
  name         = "VisitorsCounter"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "value_id"

  attribute {
    name = "value_id"
    type = "N"
  }

  attribute {
    name = "counter_value"
    type = "N"
  }

  global_secondary_index {
    name            = "visitors_count"
    hash_key        = "counter_value"
    projection_type = "ALL"
    read_capacity   = 1
    write_capacity  = 1
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "Cloud Resume Challenge"
  }
}


resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locking"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# DynamoDB Table Item
resource "aws_dynamodb_table_item" "visitor_count_ddb" {
  table_name = aws_dynamodb_table.visitor_count_ddb.name
  hash_key   = aws_dynamodb_table.visitor_count_ddb.hash_key

  lifecycle {
    prevent_destroy = true
  }

  item = jsonencode({
    "value_id"      = { N = "1" },
    "counter_value" = { N = "1" },
  })
}

# Retrieve the current AWS region dynamically
data "aws_region" "current" {}

# Retrieve the current AWS account ID dynamically
data "aws_caller_identity" "current" {}

# create lambda iam role
resource "aws_iam_role" "lambda_role" {
  name               = "aws_resume_lambda_role"
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "lambda.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

# create lambda iam role policy
resource "aws_iam_policy" "iam_policy_for_lambda" {
  name        = "iam_policy_for_aws_resume_lambda_role"
  path        = "/"
  description = "AWS IAM Policy for aws lambda to access dynamodb"
  policy      = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Effect": "Allow",
     "Action": [
       "dynamodb:BatchGetItem",
       "dynamodb:GetItem",
       "dynamodb:Query",
       "dynamodb:Scan",
       "dynamodb:BatchWriteItem",
       "dynamodb:PutItem",
       "dynamodb:UpdateItem"
     ],
     "Resource": "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
   },
   {
     "Effect": "Allow",
     "Action": [
       "logs:CreateLogStream",
       "logs:PutLogEvents"
     ],
     "Resource": "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
   },
   {
     "Effect": "Allow",
     "Action": "logs:CreateLogGroup",
     "Resource": "*"
   }
 ]
}
EOF
}

# iam role policy attachment to lambda role
resource "aws_iam_role_policy_attachment" "attach_iam_policy_to_iam_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.iam_policy_for_lambda.arn
}

# Archive the lambda function python code
data "archive_file" "zip_the_python_code" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/lambda/func.zip"
}

# lambda function creation
resource "aws_lambda_function" "terraform_lambda_func" {
  filename      = "${path.module}/lambda/func.zip"
  function_name = "VisitCounterFunction"
  role          = aws_iam_role.lambda_role.arn
  handler       = "func.lambda_handler"
  runtime       = "python3.9"
  depends_on    = [aws_iam_role_policy_attachment.attach_iam_policy_to_iam_role]
  environment {
    variables = {
      TABLE_NAME = "VisitorsCounter"
    }
  }

}

resource "aws_api_gateway_rest_api" "my_api" {
  name = "CountViews"
}

resource "aws_api_gateway_resource" "my_api_resource" {
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "counter"
  rest_api_id = aws_api_gateway_rest_api.my_api.id
}

resource "aws_api_gateway_method" "my_api_method" {
  resource_id   = aws_api_gateway_resource.my_api_resource.id
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  http_method   = "GET"
  authorization = "NONE"
}

data "aws_arn" "api_gw_deployment_arn" {
  arn = aws_api_gateway_deployment.my_api_deploy.execution_arn
}

resource "aws_api_gateway_integration" "my_api_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.my_api_resource.id
  http_method             = aws_api_gateway_method.my_api_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.terraform_lambda_func.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terraform_lambda_func.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = aws_api_gateway_rest_api.my_api.execution_arn
}

resource "aws_api_gateway_deployment" "my_api_deploy" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [
    aws_api_gateway_method.my_api_method,
    aws_api_gateway_integration.my_api_integration,
  ]
}

resource "aws_api_gateway_stage" "my_api_stage" {
  deployment_id = aws_api_gateway_deployment.my_api_deploy.id
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  stage_name    = "developer"
  lifecycle {
    ignore_changes = [stage_name]
  }
}