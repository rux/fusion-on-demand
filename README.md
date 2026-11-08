# Fusion

A personal [Fusion](https://github.com/0x2E/fusion) RSS reader on AWS. It runs on a small EC2 instance that is reachable only over Tailscale, shuts itself down 90 minutes after boot, and is started again from a bookmarked link.

Everything is defined in [`terraform/`](terraform/). The instance is disposable: the only state worth keeping is on an EBS data volume, which holds Fusion's database and Tailscale's node identity.

## Use

1. Open the wake-up bookmark: the `wakeup_url` output, then `?token=` and the `wake_token` from `terraform/secrets.auto.tfvars`.
2. Once the instance has booted, open the `fusion_url` from that file on a device on the tailnet.

## Deploy

You need Terraform, credentials for the AWS account and an existing S3 state bucket. From `terraform/`, copy the example configuration files:

```sh
cp secrets.auto.tfvars.example secrets.auto.tfvars
cp backend.hcl.example backend.hcl
```

Set your wake token, tailnet URL and Fusion password in `secrets.auto.tfvars`, and your state bucket name in `backend.hcl`. Both files are git-ignored. Terraform initialises its backend before loading variables, so the bucket settings need a separate file.

Then initialise and deploy:

```sh
terraform init -backend-config=backend.hcl
terraform apply
```

Snapshot the data volume before upgrading Fusion. A new version may migrate the database, and there are no other backups.

## Tailscale

The tailnet needs MagicDNS and HTTPS certificates turned on.

When the data volume has no Tailscale identity (on the first deploy, or after losing the volume), the instance joins with `tailscale_auth_key`. Remove any old `fusion` machine from the tailnet first, or the new one joins as `fusion-1` and the URL changes. Once it has joined, turn off its key expiry, or the stored identity will eventually stop working.

## Shell access

There is no SSH key, only Session Manager. Sessions start as `ssm-user`. To use the zsh set up for `ec2-user`, set the account's Session Manager preferences to run as `ec2-user` with the Linux shell profile `exec /bin/zsh -l`. With the instance running and the Session Manager plugin installed, from `terraform/`:

```sh
aws ssm start-session --region eu-west-2 --target "$(terraform output -raw instance_id)"
```
