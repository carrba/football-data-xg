# ---------------------------------------------------------------------------
# CloudWatch Alarms
# ---------------------------------------------------------------------------

# SNS topic — alarm notifications
resource "aws_sns_topic" "alarms" {
  name = "${var.project}-alarms"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_sns_topic_subscription" "alarm_sms" {
  count     = var.alarm_sms != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "sms"
  endpoint  = var.alarm_sms
}

# Lambda — more than 100 invocations in a 12-hour window
resource "aws_cloudwatch_metric_alarm" "lambda_invocations_high" {
  alarm_name          = "${var.project}-lambda-invocations-high"
  alarm_description   = "Lambda invocations exceeded 100 over the last 12 hours"
  namespace           = "AWS/Lambda"
  metric_name         = "Invocations"
  dimensions          = { FunctionName = aws_lambda_function.xg_predict.function_name }
  statistic           = "Sum"
  period              = 43200 # 12 hours in seconds
  evaluation_periods  = 1
  threshold           = 200
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
}
