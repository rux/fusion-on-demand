#!/bin/bash
# Turns a fresh Amazon Linux 2023 instance into the Fusion server. cloud-init
# runs it once, on first boot, after writing the other files in server/.
# Output goes to /var/log/cloud-init-output.log.
#
# Expects in the environment: DATA_VOLUME_ID, FUSION_VERSION, FUSION_SHA256,
# and TAILSCALE_AUTH_KEY, which may be empty.
set -euo pipefail

# --- Data volume ---------------------------------------------------------
# Holds Fusion's database and Tailscale's node identity, so both survive the
# instance being replaced. Terraform attaches it only once the instance is
# running, so wait for it.
device="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${DATA_VOLUME_ID/-/}"
for _ in $(seq 120); do
  [ -e "$device" ] && break
  sleep 5
done
if [ ! -e "$device" ]; then
  echo "Data volume $DATA_VOLUME_ID did not appear" >&2
  exit 1
fi

# Format only a blank volume: one with a filesystem already holds the data.
if ! blkid "$device" >/dev/null; then
  mkfs.xfs -L fusion-data "$device"
fi

# nofail keeps the instance bootable, and so reachable through SSM, if the
# volume is ever missing. The services refuse to start without it.
if ! grep -q '^LABEL=fusion-data ' /etc/fstab; then
  cat >>/etc/fstab <<'EOF'
LABEL=fusion-data /data xfs defaults,nofail 0 2
/data/fusion /var/lib/fusion none bind,nofail,x-systemd.requires-mounts-for=/data 0 0
/data/tailscale /var/lib/tailscale none bind,nofail,x-systemd.requires-mounts-for=/data 0 0
EOF
fi
systemctl daemon-reload

mkdir -p /data
mountpoint -q /data || mount /data
mkdir -p /data/fusion /data/tailscale /var/lib/fusion /var/lib/tailscale
chmod 700 /data/tailscale
mountpoint -q /var/lib/fusion || mount /var/lib/fusion
mountpoint -q /var/lib/tailscale || mount /var/lib/tailscale

# --- Packages ------------------------------------------------------------
# /etc/dnf/vars/releasever is "latest", so this and dnf-automatic follow new
# Amazon Linux releases rather than staying on the AMI's.
dnf install -y zsh git jq dnf-automatic tailscale

# --- Fusion --------------------------------------------------------------
id fusion >/dev/null 2>&1 ||
  useradd --system --home-dir /var/lib/fusion --shell /sbin/nologin fusion
# A new instance may give the user a different UID from the one that owns
# the existing files.
chown -R fusion:fusion /data/fusion
chmod 750 /data/fusion

curl -fsSL -o /tmp/fusion \
  "https://github.com/0x2E/fusion/releases/download/$FUSION_VERSION/fusion-linux-arm64"
echo "$FUSION_SHA256  /tmp/fusion" | sha256sum --check
install -o root -g root -m 0755 /tmp/fusion /usr/local/bin/fusion
rm /tmp/fusion

# --- Tailscale -----------------------------------------------------------
systemctl enable --now tailscaled

tailscale_state() {
  tailscale status --json 2>/dev/null | jq -r '.BackendState // "NoState"'
}
for _ in $(seq 30); do
  case "$(tailscale_state)" in Running | NeedsLogin) break ;; esac
  sleep 2
done

# The identity on the data volume normally logs straight back in. A key is
# only needed when that identity has been lost.
if [ "$(tailscale_state)" = NeedsLogin ] && [ -n "$TAILSCALE_AUTH_KEY" ]; then
  tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname=fusion
fi

if [ "$(tailscale_state)" = Running ]; then
  # Serve, not Funnel: tailnet only.
  tailscale serve --bg 8080
else
  echo "Tailscale is not logged in. Over SSM, run:" >&2
  echo "  sudo tailscale up --hostname=fusion && sudo tailscale serve --bg 8080" >&2
fi

# --- Services ------------------------------------------------------------
systemctl enable --now fusion.service fusion-autostop.timer dnf-automatic-install.timer

# --- ec2-user's shell ----------------------------------------------------
usermod --shell /bin/zsh ec2-user
if [ ! -d /home/ec2-user/.oh-my-zsh ]; then
  sudo -u ec2-user git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git /home/ec2-user/.oh-my-zsh
  sudo -u ec2-user cp /home/ec2-user/.oh-my-zsh/templates/zshrc.zsh-template /home/ec2-user/.zshrc
fi
