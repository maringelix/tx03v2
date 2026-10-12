# Generated secrets. Ephemeral resources are never stored in plan or state; their results are
# written only through write-only arguments (password_wo, secret_data_wo) whose *_wo_version
# decides when a new value is sent. The same apply sends the same database password to the Cloud
# SQL user and to the Secret Manager secret.
ephemeral "random_password" "db" {
  length  = 40
  special = false
}

# Contract: 48 random alphanumeric characters.
ephemeral "random_password" "admin_token" {
  length  = 48
  special = false
}

locals {
  # Contract: JSON with string values username, password, host, port, dbname (ephemeral as well).
  # host is the DNS name of the instance for Private Service Connect (the name verify-full checks).
  db_secret_value = jsonencode({
    username = module.cloudsql.user_name
    password = ephemeral.random_password.db.result
    host     = module.cloudsql.dns_name
    port     = tostring(module.cloudsql.port)
    dbname   = module.cloudsql.database_name
  })
}
