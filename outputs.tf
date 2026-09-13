output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.comfyui.name
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = try(data.aws_instances.comfyui.ids[0], "")
}

output "public_ip" {
  description = "Public IP of the ComfyUI instance"
  value       = try(data.aws_instances.comfyui.public_ips[0], "")
}

output "private_ip" {
  description = "Private IP of the ComfyUI instance"
  value       = try(data.aws_instances.comfyui.private_ips[0], "")
}

output "comfyui_url" {
  description = "ComfyUI web interface URL"
  value       = try("http://${data.aws_instances.comfyui.public_ips[0]}:${var.comfyui_port}", "")
}

output "ssh_command" {
  description = "SSH command to access the instance"
  value = try(
    var.key_name != "" ? "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${data.aws_instances.comfyui.public_ips[0]}" : "ssh ec2-user@${data.aws_instances.comfyui.public_ips[0]}",
    ""
  )
}
