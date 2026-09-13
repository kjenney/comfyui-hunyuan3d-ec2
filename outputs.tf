output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.comfyui.id
}

output "public_ip" {
  description = "Public IP of the ComfyUI instance"
  value       = aws_instance.comfyui.public_ip
}

output "private_ip" {
  description = "Private IP of the ComfyUI instance"
  value       = aws_instance.comfyui.private_ip
}

output "comfyui_url" {
  description = "ComfyUI web interface URL"
  value       = "http://${aws_instance.comfyui.public_ip}:${var.comfyui_port}"
}

output "ssh_command" {
  description = "SSH command to access the instance"
  value       = var.key_name != "" ? "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_instance.comfyui.public_ip}" : "ssh ec2-user@${aws_instance.comfyui.public_ip}"
}
