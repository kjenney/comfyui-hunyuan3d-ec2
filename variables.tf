variable "region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for ComfyUI + Hunyuan3D"
  type        = string
  default     = "g6.4xlarge"
  validation {
    condition     = contains(["g5.4xlarge", "g5.12xlarge", "g6.4xlarge", "g6.12xlarge", "g7.2xlarge", "g7.12xlarge", "g7.24xlarge"], var.instance_type)
    error_message = "Instance type must be one of: g5.4xlarge, g5.12xlarge, g6.4xlarge, g6.12xlarge, g7.2xlarge, g7.12xlarge, g7.24xlarge"
  }
}

variable "use_spot" {
  description = "Whether to use Spot instances (saves ~70% but can be interrupted)"
  type        = bool
  default     = true
}

variable "ebs_volume_size_gb" {
  description = "Size of the EBS root volume in GB"
  type        = number
  default     = 150
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone (GPU instances may be AZ-limited)"
  type        = string
  default     = "us-east-1a"
}

variable "key_name" {
  description = "EC2 SSH key pair name"
  type        = string
  default     = ""
}

variable "ami_name" {
  description = "The AMI to use for the EC2 instance"
  type        = string
  default     = ""
}

variable "hf_token" {
  description = "Hugging Face token for gated models (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "model_version" {
  description = "Hunyuan3D model version"
  type        = string
  default     = "2.1"
}

variable "comfyui_port" {
  description = "Port for ComfyUI web interface"
  type        = number
  default     = 8188
}
