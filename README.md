# ComfyUI + Hunyuan3D on AWS EC2

Terraform configuration to provision a GPU instance with ComfyUI and native Hunyuan3D 2.0 multiview support for generating glTF/GLB models.

## Instance Types

| Instance | GPU | VRAM | Price/hr (OD) | Spot (~) |
|---|---|---|---|---|
| g6.4xlarge | 1× L4 | 24 GB | $3.69 | $1.11 |
| g6.12xlarge | 4× L4 | 96 GB | $14.76 | $4.43 |
| g5.4xlarge | 1× A10G | 24 GB | $3.06 | $0.92 |
| g7.2xlarge | 1× RTX PRO 4500 | 32 GB | $4.34 | $1.30 |
| g7.12xlarge | 2× RTX PRO 4500 | 64 GB | $8.68 | $2.60 |
| g7.24xlarge | 4× RTX PRO 4500 | 128 GB | $17.36 | $5.21 |

VRAM requirements:
- Shape generation only: ~10 GB
- Texture generation: ~21 GB
- Shape + texture: ~29 GB

## Setup

1. **Create a `.env.sh` file**:

```bash
cp .env.sh.example .env.sh
```

Fill in the correct values for the variables.


2. **Initialize and apply:**
   ```bash
   source .env.sh
   printenv | grep TF_VAR_ami_name
   terraform init
   terraform plan
   terraform apply
   ```

3. **Access ComfyUI:**
   ```bash
   terraform output comfyui_url
   # Open in browser: http://<public-ip>:8188
   ```

5. **SSH into the instance:**
   ```bash
   terraform output ssh_command
   ```

## To Tear Down

```bash
terraform destroy
```

## Files

- `main.tf` — EC2 instance, VPC, security group, IAM, user data
- `variables.tf` — configurable variables
- `outputs.tf` — instance IP, URLs, SSH command
- `userdata.sh.tftpl` — user data script template (Hunyuan3D models downloaded at launch)

## Notes

- The `lifecycle { ignore_changes = [user_data] }` block prevents Terraform from destroying and recreating the instance if the user data script changes — the script only runs at instance launch, not on updates.
- If you need to update the user data, you'll need to destroy and recreate the instance.
- The `ignore_changes` block also prevents accidental recreation if you change the `model_version` variable — in that case, destroy and recreate.
- GPU instances may be AZ-limited. If your chosen AZ doesn't have the GPU type, change `availability_zone` in variables.tf.
- The EBS volume is encrypted by default.
- Spot instances save ~70% but can be interrupted with 2-minute warning.
