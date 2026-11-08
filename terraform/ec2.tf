locals {
  fusion_version = "v1.3.0"
  # SHA-256 of fusion-linux-arm64, from the release's checksums.txt.
  fusion_sha256 = "60222671312a038dcd813ab0c153da68fbe35d6c4a31b1c784d1b836648def3b"

  # cloud-init writes these files, then runs the bootstrap script once.
  cloud_config = {
    write_files = [
      {
        path    = "/etc/systemd/system/fusion.service"
        content = file("${path.module}/server/fusion.service")
      },
      {
        path    = "/etc/systemd/system/fusion-autostop.service"
        content = file("${path.module}/server/fusion-autostop.service")
      },
      {
        path    = "/etc/systemd/system/fusion-autostop.timer"
        content = file("${path.module}/server/fusion-autostop.timer")
      },
      {
        path    = "/etc/systemd/system/dnf-automatic-install.timer.d/override.conf"
        content = file("${path.module}/server/dnf-automatic-install-override.conf")
      },
      {
        path    = "/etc/systemd/system/tailscaled.service.d/override.conf"
        content = file("${path.module}/server/tailscaled-override.conf")
      },
      {
        path    = "/etc/yum.repos.d/tailscale.repo"
        content = file("${path.module}/server/tailscale.repo")
      },
      {
        path    = "/etc/dnf/vars/releasever"
        content = "latest\n"
      },
      {
        path        = "/etc/fusion.env"
        permissions = "0600"
        content     = templatefile("${path.module}/server/fusion.env.tftpl", { password = var.fusion_password })
      },
      {
        path        = "/usr/local/sbin/bootstrap-fusion"
        permissions = "0755"
        content     = file("${path.module}/server/bootstrap.sh")
      },
    ]
    runcmd = [[
      "env",
      "DATA_VOLUME_ID=${aws_ebs_volume.data.id}",
      "FUSION_VERSION=${local.fusion_version}",
      "FUSION_SHA256=${local.fusion_sha256}",
      "TAILSCALE_AUTH_KEY=${var.tailscale_auth_key}",
      "/usr/local/sbin/bootstrap-fusion",
    ]]
  }
}

resource "aws_security_group" "fusion" {
  name        = "fusion"
  description = "Fusion sg to allow outbound connections only"

  # Access is over Tailscale only. An empty list makes Terraform remove any
  # inbound rule added by hand.
  ingress = []

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Fusion's database and Tailscale's node identity. This is the only state
# worth keeping: everything else is rebuilt from this directory.
resource "aws_ebs_volume" "data" {
  availability_zone = "eu-west-2d"
  type              = "gp3"
  size              = 4
  encrypted         = true

  tags = {
    Name = "fusion-data"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Lets Session Manager reach the instance. It is the only way to a shell, as
# there is no SSH key.
resource "aws_iam_role" "fusion" {
  name = "fusion-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "fusion_ssm" {
  role       = aws_iam_role.fusion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "fusion" {
  name = "fusion-instance-role"
  role = aws_iam_role.fusion.name
}

resource "aws_instance" "fusion" {
  # Amazon Linux 2023 ARM64. dnf follows the latest release once running, so
  # this only needs bumping to speed up the first boot.
  ami               = "ami-0d623184a69654e22"
  instance_type     = "t4g.micro"
  availability_zone = aws_ebs_volume.data.availability_zone

  vpc_security_group_ids = [aws_security_group.fusion.id]
  iam_instance_profile   = aws_iam_instance_profile.fusion.name

  # systemd shuts the OS down after 90 minutes; that must stop, not
  # terminate, the instance.
  instance_initiated_shutdown_behavior = "stop"

  user_data = "#cloud-config\n${yamlencode(local.cloud_config)}"
  # cloud-init only acts on first boot, so a changed configuration needs a
  # new instance. The data volume moves across to it.
  user_data_replace_on_change = true

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
    tags = {
      Project = "fusion"
    }
  }

  tags = {
    # The wake-up Lambda finds the instance by this tag, and its IAM policy
    # only lets it start instances that carry it.
    Name = "fusion"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.fusion.id

  # Lets the filesystem unmount cleanly before the volume is detached.
  stop_instance_before_detaching = true
}

resource "aws_ec2_tag" "fusion_network_interface" {
  resource_id = aws_instance.fusion.primary_network_interface_id
  key         = "Project"
  value       = "fusion"
}
