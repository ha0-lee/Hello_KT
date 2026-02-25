# Lambda, EventBridge (전원 스케줄러)

# 람다 함수 정의 (시작용)
data "archive_file" "start_zip" {
  type        = "zip"
  source_file = "${path.module}/ec2_start.py"
  output_path = "${path.module}/ec2_start.zip"
}

data "archive_file" "stop_zip" {
  type        = "zip"
  source_file = "${path.module}/ec2_stop.py"
  output_path = "${path.module}/ec2_stop.zip"
}


# 2. 람다용 IAM 역할(Role) 생성
resource "aws_iam_role" "lambda_role" {
  name = "ec2_scheduler_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 3. EC2 제어 권한(Policy) 정의 및 연결
resource "aws_iam_role_policy" "ec2_policy" {
  name = "ec2_control_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:StartInstances", "ec2:StopInstances", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
resource "aws_lambda_function" "ec2_start_lambda" {
  filename      = data.archive_file.start_zip.output_path
  function_name = "EC2_Start_Function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "ec2_start.lambda_handler"
  runtime       = "python3.9"


  environment {
    variables = {
      # [중요!] 생성된 EC2 2대의 ID를 쉼표로 합쳐서 자동으로 전달합니다.
      INSTANCE_IDS = join(",", concat(aws_instance.Worker_server[*].id, [aws_instance.Master_server.id], [aws_instance.monitoring_server.id]))
    }
  }
}

# 5. 람다 함수 정의 (중지용)
resource "aws_lambda_function" "ec2_stop_lambda" {
  filename         = data.archive_file.stop_zip.output_path
  function_name    = "EC2_Stop_Function"
  role             = aws_iam_role.lambda_role.arn
  handler          = "ec2_stop.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.stop_zip.output_base64sha256

  environment {
    variables = {
      INSTANCE_IDS = join(",", concat(aws_instance.Worker_server[*].id, [aws_instance.Master_server.id], [aws_instance.monitoring_server.id]))
    }
  }
}

# 6. EventBridge (스케줄러) - 10시 시작
resource "aws_cloudwatch_event_rule" "start_rule" {
  name                = "ec2_start_rule"
  schedule_expression = "cron(0 1 * * ? *)" # UTC 01:00 = KST 10:00
}

resource "aws_cloudwatch_event_target" "start_target" {
  rule      = aws_cloudwatch_event_rule.start_rule.name
  target_id = "start_lambda"
  arn       = aws_lambda_function.ec2_start_lambda.arn
}

# 7. EventBridge (스케줄러) - 14시 중지
resource "aws_cloudwatch_event_rule" "stop_rule" {
  name                = "ec2_stop_rule"
  schedule_expression = "cron(0 5 * * ? *)" # UTC 05:00 = KST 14:00
}

resource "aws_cloudwatch_event_target" "stop_target" {
  rule      = aws_cloudwatch_event_rule.stop_rule.name
  target_id = "stop_lambda"
  arn       = aws_lambda_function.ec2_stop_lambda.arn
}

# 8. EventBridge가 람다를 호출할 수 있게 권한 부여
resource "aws_lambda_permission" "allow_start" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_start_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.start_rule.arn
}

resource "aws_lambda_permission" "allow_stop" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_stop_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stop_rule.arn
}
