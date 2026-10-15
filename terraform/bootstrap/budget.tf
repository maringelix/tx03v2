# Monthly budget of the lab project (use a dedicated project). The amount is in the currency of the
# billing account: currency_code is omitted on purpose (it must match the billing account).
# Alerts at 50/90/100 % of the current spend and 100 % of the forecast go to the e-mail
# notification channels of budget_alert_emails (required: someone you name reads them) and to the
# billing account administrators and users (disable_default_iam_recipients = false). A budget never
# stops spending. Credits are not subtracted (EXCLUDE_ALL_CREDITS): the free-trial credits would
# keep the counted spend at zero and the alert would never come, although the credits end.
resource "google_monitoring_notification_channel" "budget" {
  for_each = toset(var.budget_alert_emails)

  display_name = "${local.lab_name} budget: ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }

  depends_on = [google_project_service.lab]
}

locals {
  budget_thresholds = [
    { percent = 0.5, basis = "CURRENT_SPEND" },
    { percent = 0.9, basis = "CURRENT_SPEND" },
    { percent = 1.0, basis = "CURRENT_SPEND" },
    { percent = 1.0, basis = "FORECASTED_SPEND" },
  ]
}

resource "google_billing_budget" "monthly" {
  billing_account = var.billing_account
  display_name    = "${local.lab_name}-monthly"

  budget_filter {
    projects               = ["projects/${local.project_number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      units = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = local.budget_thresholds
    content {
      threshold_percent = threshold_rules.value.percent
      spend_basis       = threshold_rules.value.basis
    }
  }

  all_updates_rule {
    disable_default_iam_recipients   = false
    monitoring_notification_channels = [for c in google_monitoring_notification_channel.budget : c.id]
  }

  depends_on = [google_project_service.lab]
}
