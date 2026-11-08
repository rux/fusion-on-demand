resource "aws_iam_role" "wakeup" {
  name = "fusion-wakeup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "wakeup_logs" {
  role       = aws_iam_role.wakeup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "wakeup_start_instance" {
  name = "start-fusion-ec2-instance"
  role = aws_iam_role.wakeup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # DescribeInstances cannot be scoped to a resource.
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      },
      {
        Effect    = "Allow"
        Action    = "ec2:StartInstances"
        Resource  = "*"
        Condition = { StringEquals = { "ec2:ResourceTag/Name" = "fusion" } }
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "wakeup" {
  name              = "/aws/lambda/fusion-wakeup"
  retention_in_days = 30
}

data "archive_file" "wakeup" {
  type        = "zip"
  source_file = "${path.module}/wakeup/lambda_function.py"
  # A build artefact, rebuilt on every plan, so it lives with Terraform's
  # other working files.
  output_path = "${path.module}/.terraform/wakeup.zip"
}

resource "aws_lambda_function" "wakeup" {
  function_name    = "fusion-wakeup"
  role             = aws_iam_role.wakeup.arn
  runtime          = "python3.14"
  architectures    = ["arm64"]
  handler          = "lambda_function.lambda_handler"
  filename         = data.archive_file.wakeup.output_path
  source_code_hash = data.archive_file.wakeup.output_base64sha256

  environment {
    variables = {
      WAKE_TOKEN = var.wake_token
      FUSION_URL = var.fusion_url
    }
  }

  depends_on = [aws_cloudwatch_log_group.wakeup]
}

# Public endpoint: the function checks WAKE_TOKEN itself.
resource "aws_lambda_function_url" "wakeup" {
  function_name      = aws_lambda_function.wakeup.function_name
  authorization_type = "NONE"
}

# An unauthenticated function URL needs both permissions.
resource "aws_lambda_permission" "wakeup_url_public_access" {
  statement_id           = "FunctionURLAllowPublicAccess"
  function_name          = aws_lambda_function.wakeup.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "wakeup_url_invoke" {
  statement_id             = "FunctionURLAllowInvokeAction"
  function_name            = aws_lambda_function.wakeup.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}
