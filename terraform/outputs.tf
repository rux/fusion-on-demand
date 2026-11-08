output "instance_id" {
  value = aws_instance.fusion.id
}

output "data_volume_id" {
  value = aws_ebs_volume.data.id
}

output "wakeup_url" {
  description = "Append ?token=<WAKE_TOKEN> to use it."
  value       = aws_lambda_function_url.wakeup.function_url
}
