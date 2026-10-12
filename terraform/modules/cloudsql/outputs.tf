output "instance_name" {
  description = "Instance name (tx03v2-lab-<4 hex>)."
  value       = google_sql_database_instance.this.name
}

output "dns_name" {
  description = "DNS name of the instance for Private Service Connect, without the final dot (secret key host)."
  value       = trimsuffix(google_sql_database_instance.this.dns_name, ".")
}

output "endpoint_ip" {
  description = "Internal IP of the Private Service Connect endpoint (contract key db/endpoint-ip)."
  value       = google_compute_address.endpoint.address
}

output "port" {
  description = "PostgreSQL port."
  value       = 5432
}

output "database_name" {
  description = "Database of the app."
  value       = google_sql_database.app.name
}

output "user_name" {
  description = "Database user of the app."
  value       = google_sql_user.app.name
}
