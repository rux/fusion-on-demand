variable "wake_token" {
  description = "Token the wake-up bookmark passes as ?token=. Changing it breaks the existing bookmark."
  type        = string
  sensitive   = true
}

variable "fusion_url" {
  description = "Tailnet URL the wake-up page links to."
  type        = string
}

variable "fusion_password" {
  description = "Fusion login password."
  type        = string
  sensitive   = true

  validation {
    # It is written inside double quotes in a systemd EnvironmentFile.
    condition     = !can(regex("[\"\\\\\\n]", var.fusion_password))
    error_message = "The password must not contain double quotes, backslashes or newlines."
  }
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key. Needed only if the data volume has lost Tailscale's node identity."
  type        = string
  sensitive   = true
  default     = ""
}
