# Inputs of the lab root. Cloud workflows pass them as TF_VAR_* repository variables
# (lists as JSON strings); docs/RUNBOOK.md lists every one. Every input is validated here; the
# modules trust what they receive.

variable "project_id" {
  description = "ID of the dedicated Google Cloud project of the lab (contract key project-id), the one given to terraform/bootstrap."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id must be a Google Cloud project ID: 6-30 lowercase letters, digits or hyphens, starting with a letter, e.g. tx03v2-lab-example."
  }
}

variable "region" {
  description = "Region of the lab (contract key region), the one given to terraform/bootstrap."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "The region must be a Google Cloud region name such as us-central1 or southamerica-east1."
  }
}

variable "github_owner" {
  description = "GitHub owner of this repository; used (lowercased) in the repository label. The workflows pass github.repository_owner."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$", var.github_owner))
    error_message = "The github_owner must be a valid GitHub user or organization name."
  }

  validation {
    condition     = lower(var.github_owner) != "your-github-user"
    error_message = "Set github_owner to the GitHub user that owns your forks (terraform.tfvars.example holds a placeholder)."
  }
}

# --- Identities and access ---

variable "deploy_service_account" {
  description = "E-mail of dx03v2-gha-deploy (bootstrap output deploy_service_account; contract key deploy/service-account). Gets Artifact Registry writer on dx03v2, Kubernetes Engine Cluster Viewer and Parameter Manager Parameter Accessor; the RoleBinding of platform/manifests uses it."
  type        = string

  validation {
    condition     = can(regex("^dx03v2-gha-deploy@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.deploy_service_account))
    error_message = "The deploy_service_account must be the e-mail of dx03v2-gha-deploy, e.g. dx03v2-gha-deploy@tx03v2-lab-example.iam.gserviceaccount.com."
  }

  validation {
    condition     = !can(regex("^dx03v2-gha-deploy@[a-z][a-z0-9-]{4,28}[a-z0-9]\\.iam\\.gserviceaccount\\.com$", var.deploy_service_account)) || endswith(var.deploy_service_account, "@${var.project_id}.iam.gserviceaccount.com")
    error_message = "The deploy_service_account must belong to project_id (the bootstrap creates it in the lab project)."
  }
}

variable "app_deployer_members" {
  description = "Extra IAM members (people deploying dx03v2 from a laptop), e.g. [\"user:you@example.com\"]. They get the same roles as dx03v2-gha-deploy (Artifact Registry writer on dx03v2, Kubernetes Engine Cluster Viewer, Parameter Manager Parameter Accessor) and platform/install.sh adds their e-mails to the dx03v2-deployers RoleBinding."
  type        = list(string)
  default     = []

  # No group: members: they would get the IAM roles but could never match the RoleBinding (Google
  # Groups for RBAC is not configured on the lab cluster); platform/install.sh refuses them too.
  validation {
    condition     = alltrue([for m in var.app_deployer_members : can(regex("^(user|serviceAccount):[a-z0-9][a-z0-9._%+-]*@[a-z0-9-]+(\\.[a-z0-9-]+)*\\.[a-z]{2,}$", m))])
    error_message = "Every app_deployer_members entry must be user:<e-mail> or serviceAccount:<e-mail> (lowercase), e.g. user:you@example.com; group: members cannot match the RoleBinding."
  }

  validation {
    condition     = length(distinct(var.app_deployer_members)) == length(var.app_deployer_members) && !contains(var.app_deployer_members, "serviceAccount:${var.deploy_service_account}")
    error_message = "The app_deployer_members entries must be unique and must not repeat deploy_service_account (it is always a deployer)."
  }
}

# --- Network (all CIDRs validated: RFC 1918, prefix sizes, no overlaps) ---

variable "nodes_subnet_cidr" {
  description = "Primary range of the nodes subnet (contract key nodes-subnet-cidr; /16 to /24, RFC 1918). The Private Service Connect endpoint of Cloud SQL takes an address in it."
  type        = string
  default     = "10.30.0.0/20"

  validation {
    condition     = can(regex("^[0-9.]+/(1[6-9]|2[0-4])$", var.nodes_subnet_cidr)) && try(cidrsubnet(var.nodes_subnet_cidr, 0, 0) == var.nodes_subnet_cidr, false)
    error_message = "The nodes_subnet_cidr must be a canonical IPv4 network with a prefix between /16 and /24, e.g. 10.30.0.0/20."
  }

  validation {
    condition = try(anytrue([
      for p in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      tonumber(split("/", var.nodes_subnet_cidr)[1]) >= tonumber(split("/", p)[1]) &&
      cidrhost("${split("/", var.nodes_subnet_cidr)[0]}/${split("/", p)[1]}", 0) == split("/", p)[0]
    ]), false)
    error_message = "The nodes_subnet_cidr must be inside an RFC 1918 range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)."
  }
}

variable "pods_cidr" {
  description = "Secondary range `pods` of the nodes subnet (/14 to /21, RFC 1918; Autopilot gives each node a /24 of it by default)."
  type        = string
  default     = "10.32.0.0/16"

  validation {
    condition     = can(regex("^[0-9.]+/(1[4-9]|2[01])$", var.pods_cidr)) && try(cidrsubnet(var.pods_cidr, 0, 0) == var.pods_cidr, false)
    error_message = "The pods_cidr must be a canonical IPv4 network with a prefix between /14 and /21, e.g. 10.32.0.0/16."
  }

  validation {
    condition = try(anytrue([
      for p in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      tonumber(split("/", var.pods_cidr)[1]) >= tonumber(split("/", p)[1]) &&
      cidrhost("${split("/", var.pods_cidr)[0]}/${split("/", p)[1]}", 0) == split("/", p)[0]
    ]), false)
    error_message = "The pods_cidr must be inside an RFC 1918 range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)."
  }

  validation {
    condition = try(
      cidrhost("${split("/", var.pods_cidr)[0]}/${min(tonumber(split("/", var.pods_cidr)[1]), tonumber(split("/", var.nodes_subnet_cidr)[1]))}", 0) !=
      cidrhost("${split("/", var.nodes_subnet_cidr)[0]}/${min(tonumber(split("/", var.pods_cidr)[1]), tonumber(split("/", var.nodes_subnet_cidr)[1]))}", 0),
    true)
    error_message = "The pods_cidr must not overlap nodes_subnet_cidr."
  }
}

variable "services_cidr" {
  description = "Secondary range `services` of the nodes subnet (/16 to /24, RFC 1918)."
  type        = string
  default     = "10.33.0.0/20"

  validation {
    condition     = can(regex("^[0-9.]+/(1[6-9]|2[0-4])$", var.services_cidr)) && try(cidrsubnet(var.services_cidr, 0, 0) == var.services_cidr, false)
    error_message = "The services_cidr must be a canonical IPv4 network with a prefix between /16 and /24, e.g. 10.33.0.0/20."
  }

  validation {
    condition = try(anytrue([
      for p in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      tonumber(split("/", var.services_cidr)[1]) >= tonumber(split("/", p)[1]) &&
      cidrhost("${split("/", var.services_cidr)[0]}/${split("/", p)[1]}", 0) == split("/", p)[0]
    ]), false)
    error_message = "The services_cidr must be inside an RFC 1918 range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)."
  }

  validation {
    condition = try(alltrue([
      for other in [var.nodes_subnet_cidr, var.pods_cidr] :
      cidrhost("${split("/", var.services_cidr)[0]}/${min(tonumber(split("/", var.services_cidr)[1]), tonumber(split("/", other)[1]))}", 0) !=
      cidrhost("${split("/", other)[0]}/${min(tonumber(split("/", var.services_cidr)[1]), tonumber(split("/", other)[1]))}", 0)
    ]), true)
    error_message = "The services_cidr must not overlap nodes_subnet_cidr or pods_cidr."
  }
}

variable "control_plane_cidr" {
  description = "Private /28 of the GKE control plane (RFC 1918, overlapping nothing in the VPC). The firewall rule of modules/gke lets this range reach the admission webhooks of the full profile on 8443 and 9443."
  type        = string
  default     = "172.31.255.240/28"

  validation {
    condition     = can(regex("^[0-9.]+/28$", var.control_plane_cidr)) && try(cidrsubnet(var.control_plane_cidr, 0, 0) == var.control_plane_cidr, false)
    error_message = "The control_plane_cidr must be a canonical IPv4 network with prefix /28, e.g. 172.31.255.240/28."
  }

  validation {
    condition = try(anytrue([
      for p in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      tonumber(split("/", var.control_plane_cidr)[1]) >= tonumber(split("/", p)[1]) &&
      cidrhost("${split("/", var.control_plane_cidr)[0]}/${split("/", p)[1]}", 0) == split("/", p)[0]
    ]), false)
    error_message = "The control_plane_cidr must be inside an RFC 1918 range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)."
  }

  validation {
    condition = try(alltrue([
      for other in [var.nodes_subnet_cidr, var.pods_cidr, var.services_cidr] :
      cidrhost("${split("/", var.control_plane_cidr)[0]}/${min(28, tonumber(split("/", other)[1]))}", 0) !=
      cidrhost("${split("/", other)[0]}/${min(28, tonumber(split("/", other)[1]))}", 0)
    ]), true)
    error_message = "The control_plane_cidr must not overlap nodes_subnet_cidr, pods_cidr or services_cidr."
  }
}

# --- Data stores, edge, secrets ---

variable "db_tier" {
  description = "Cloud SQL tier (edition ENTERPRISE). db-g1-small has 50 connections by default: up to 4 API replicas x DB_POOL_MAX 10 plus the migration (contract)."
  type        = string
  default     = "db-g1-small"

  validation {
    condition     = can(regex("^db-(g1-small|custom-[0-9]+-[0-9]+|n1-(standard|highmem)-[0-9]+)$", var.db_tier))
    error_message = "The db_tier must be a Cloud SQL Enterprise tier such as db-g1-small or db-custom-1-3840."
  }

  validation {
    condition     = var.db_tier != "db-f1-micro"
    error_message = "db-f1-micro allows only 25 connections, fewer than the dx03v2 API pool needs (4 replicas x 10 + migration): use db-g1-small or larger."
  }
}

variable "db_profile" {
  description = "core keeps the low-cost zonal instance; ha enables regional Cloud SQL and PITR; dr also provisions a cross-region recovery path."
  type        = string
  default     = "core"

  validation {
    condition     = contains(["core", "ha", "dr"], var.db_profile)
    error_message = "db_profile must be core, ha, or dr."
  }
}

variable "ha_db_tier" {
  description = "Dedicated-core Enterprise tier for the opt-in HA/DR profiles; shared-core has no HA SLA."
  type        = string
  default     = "db-custom-1-3840"

  validation {
    condition     = can(regex("^db-custom-(1|[2468]|[1-9][0-9]+)-[0-9]+$", var.ha_db_tier))
    error_message = "ha_db_tier must be a dedicated-core db-custom tier, such as db-custom-1-3840."
  }
}

variable "db_backup_count" {
  description = "Optional automated backup count; defaults to one in core and seven in HA/DR."
  type        = number
  default     = null

  validation {
    condition     = var.db_backup_count == null ? true : var.db_backup_count >= 1 && var.db_backup_count <= 365 && (var.db_profile == "core" || var.db_backup_count >= 7)
    error_message = "db_backup_count must be 1-365 and at least seven for HA/DR."
  }
}

variable "db_deletion_protection" {
  description = "Enable Terraform and Cloud SQL deletion protection; disable explicitly before lab teardown."
  type        = bool
  default     = false
}

variable "db_retain_backups_on_delete" {
  description = "Retain backups after deleting the instance; opt-in because retained backups incur cost."
  type        = bool
  default     = false
}

variable "dr_region" {
  description = "Secondary Google Cloud region, used only with db_profile=dr. Must differ from the primary region."
  type        = string
  default     = "us-east1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.dr_region)) && (var.db_profile != "dr" || var.dr_region != var.region)
    error_message = "dr_region must be a Google Cloud region different from region in the DR profile."
  }
  validation {
    condition     = var.db_profile != "dr" || (startswith(var.region, "us-") && startswith(var.dr_region, "us-"))
    error_message = "This DR learning path uses two US regions and a US multiregion recovery bucket."
  }
}

variable "active_region" {
  description = "Public DNS destination after a separately authorized, fenced failover. Does not promote a database."
  type        = string
  default     = "primary"
  validation {
    condition     = contains(["primary", "secondary"], var.active_region) && (var.active_region != "secondary" || var.db_profile == "dr")
    error_message = "active_region must be primary, or secondary only with db_profile=dr."
  }
}

variable "dr_nodes_subnet_cidr" {
  description = "Secondary region nodes subnet; isolated from the primary VPC."
  type        = string
  default     = "10.40.0.0/20"

  validation {
    condition     = can(regex("^[0-9.]+/(2[0-5])$", var.dr_nodes_subnet_cidr)) && try(cidrsubnet(var.dr_nodes_subnet_cidr, 0, 0) == var.dr_nodes_subnet_cidr, false)
    error_message = "dr_nodes_subnet_cidr must be a canonical /20-/25 CIDR."
  }

  validation {
    condition = try(anytrue([
      for private in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      cidrhost("${split("/", var.dr_nodes_subnet_cidr)[0]}/${split("/", private)[1]}", 0) == split("/", private)[0]
    ]), false)
    error_message = "dr_nodes_subnet_cidr must be RFC 1918 private space."
  }

  validation {
    condition = try(alltrue([
      for other in [var.dr_pods_cidr, var.dr_services_cidr, var.dr_control_plane_cidr] :
      cidrhost("${split("/", var.dr_nodes_subnet_cidr)[0]}/${min(tonumber(split("/", var.dr_nodes_subnet_cidr)[1]), tonumber(split("/", other)[1]))}", 0) !=
      cidrhost("${split("/", other)[0]}/${min(tonumber(split("/", var.dr_nodes_subnet_cidr)[1]), tonumber(split("/", other)[1]))}", 0)
    ]), false)
    error_message = "dr_nodes_subnet_cidr must not overlap secondary pods, services or control plane."
  }
}

variable "dr_pods_cidr" {
  description = "Secondary region GKE Pod range."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(regex("^[0-9.]+/(1[4-9]|2[01])$", var.dr_pods_cidr)) && try(cidrsubnet(var.dr_pods_cidr, 0, 0) == var.dr_pods_cidr, false)
    error_message = "dr_pods_cidr must be a canonical /14-/21 CIDR."
  }

  validation {
    condition = try(anytrue([
      for private in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      cidrhost("${split("/", var.dr_pods_cidr)[0]}/${split("/", private)[1]}", 0) == split("/", private)[0]
    ]), false)
    error_message = "dr_pods_cidr must be RFC 1918 private space."
  }
}

variable "dr_services_cidr" {
  description = "Secondary region GKE Services range."
  type        = string
  default     = "10.43.0.0/20"

  validation {
    condition     = can(regex("^[0-9.]+/(1[6-9]|2[0-4])$", var.dr_services_cidr)) && try(cidrsubnet(var.dr_services_cidr, 0, 0) == var.dr_services_cidr, false)
    error_message = "dr_services_cidr must be a canonical /16-/24 CIDR."
  }

  validation {
    condition = try(anytrue([
      for private in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      cidrhost("${split("/", var.dr_services_cidr)[0]}/${split("/", private)[1]}", 0) == split("/", private)[0]
    ]), false)
    error_message = "dr_services_cidr must be RFC 1918 private space."
  }

  validation {
    condition = try(
      cidrhost("${split("/", var.dr_services_cidr)[0]}/${min(tonumber(split("/", var.dr_services_cidr)[1]), tonumber(split("/", var.dr_pods_cidr)[1]))}", 0) !=
      cidrhost("${split("/", var.dr_pods_cidr)[0]}/${min(tonumber(split("/", var.dr_services_cidr)[1]), tonumber(split("/", var.dr_pods_cidr)[1]))}", 0),
    false)
    error_message = "dr_services_cidr must not overlap dr_pods_cidr."
  }
}

variable "dr_control_plane_cidr" {
  description = "Private /28 of the secondary GKE control plane."
  type        = string
  default     = "172.31.255.224/28"

  validation {
    condition     = try(cidrsubnet(var.dr_control_plane_cidr, 0, 0) == var.dr_control_plane_cidr && tonumber(split("/", var.dr_control_plane_cidr)[1]) == 28, false)
    error_message = "dr_control_plane_cidr must be a canonical /28 CIDR."
  }

  validation {
    condition = try(anytrue([
      for private in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      cidrhost("${split("/", var.dr_control_plane_cidr)[0]}/${split("/", private)[1]}", 0) == split("/", private)[0]
    ]), false)
    error_message = "dr_control_plane_cidr must be RFC 1918 private space."
  }
}

variable "enable_waf" {
  description = "Cloud Armor policy tx03v2-lab-waf (preconfigured SQLi and XSS rules) for the Gateway backends. Parity with tx01v2/tx02v2; about US$7/month for the policy and its rules (docs/COSTS.md)."
  type        = bool
  default     = true
}

variable "dns_zone_name" {
  description = "Optional public Cloud DNS zone for the app hostname. Delegate the published name servers before expecting certificate issuance. Empty keeps the core profile free of a public domain."
  type        = string
  default     = ""

  validation {
    condition     = var.dns_zone_name == "" || can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$", var.dns_zone_name))
    error_message = "dns_zone_name must be empty or a lowercase public DNS zone such as example.com."
  }
}

variable "app_domain_name" {
  description = "Optional hostname for the full HTTPS profile, inside dns_zone_name. A delegated public domain is required for the Google-managed certificate."
  type        = string
  default     = ""

  validation {
    condition     = var.app_domain_name == "" || can(regex("^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$", var.app_domain_name))
    error_message = "app_domain_name must be empty or a lowercase public DNS hostname."
  }

  validation {
    condition = (
      (var.app_domain_name == "" && var.dns_zone_name == "") ||
      (var.app_domain_name != "" && var.dns_zone_name != "" &&
      endswith(var.app_domain_name, ".${var.dns_zone_name}"))
    )
    error_message = "Set app_domain_name and dns_zone_name together; the app must be a subdomain of the delegated zone."
  }
}

variable "enable_managed_mesh" {
  description = "Register the GKE Autopilot cluster with the project's fleet and enable managed Cloud Service Mesh. Required by the full profile; core may leave this false."
  type        = bool
  default     = false
}

variable "db_password_version" {
  description = "Increment to rotate the database password; it drives the Cloud SQL user and the Secret Manager secret together (write-only versions)."
  type        = number
  default     = 1

  validation {
    condition     = var.db_password_version >= 1 && floor(var.db_password_version) == var.db_password_version
    error_message = "The db_password_version must be a positive integer."
  }
}

variable "admin_token_version" {
  description = "Increment to generate a new dx03v2 admin token (write-only secret version)."
  type        = number
  default     = 1

  validation {
    condition     = var.admin_token_version >= 1 && floor(var.admin_token_version) == var.admin_token_version
    error_message = "The admin_token_version must be a positive integer."
  }
}
variable "continuity_notification_channels" {
  description = "Existing Cloud Monitoring channel resource names; empty keeps incidents in the console. No channel credentials enter Terraform."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for channel in var.continuity_notification_channels : can(regex("^projects/${var.project_id}/notificationChannels/[0-9]+$", channel))])
    error_message = "Use existing Cloud Monitoring notification channel resource names."
  }
}
