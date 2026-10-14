# Monthly Cloud Billing budget of the lab project: on by default, scoped to the project, alerts at
# 50/90/100 % of the spend and 100 % of the forecast, optional e-mail channels, and the input
# validations that keep a typo from creating a budget for the wrong thing.

mock_provider "google" {
  source = "../tests/mocks"
}

variables {
  github_owner        = "maringelix"
  project_id          = "tx03v2-lab-example"
  billing_account     = "000000-000000-000000"
  budget_alert_emails = ["lab-alerts@example.org"]
}

run "budget_is_on_and_scoped_to_the_project" {
  command = apply

  assert {
    condition = (
      google_billing_budget.monthly.billing_account == "000000-000000-000000" &&
      google_billing_budget.monthly.display_name == "tx03v2-lab-monthly" &&
      google_billing_budget.monthly.budget_filter[0].projects == toset(["projects/000000000000"]) &&
      google_billing_budget.monthly.budget_filter[0].calendar_period == "MONTH"
    )
    error_message = "The budget must cover the lab project (by number), month by month, on the given billing account."
  }

  assert {
    condition     = google_billing_budget.monthly.amount[0].specified_amount[0].units == "10"
    error_message = "Default budget: 10 units of the billing account currency."
  }

  assert {
    condition = [for t in google_billing_budget.monthly.threshold_rules : "${t.threshold_percent}/${t.spend_basis}"] == [
      "0.5/CURRENT_SPEND",
      "0.9/CURRENT_SPEND",
      "1/CURRENT_SPEND",
      "1/FORECASTED_SPEND",
    ]
    error_message = "Alerts at 50, 90 and 100 % of the current spend and 100 % of the forecast."
  }

  assert {
    condition = (
      google_billing_budget.monthly.all_updates_rule[0].disable_default_iam_recipients == false &&
      length(google_billing_budget.monthly.all_updates_rule[0].monitoring_notification_channels) == 1
    )
    error_message = "Billing account administrators always get the alerts, plus one channel per budget_alert_emails entry."
  }

  assert {
    condition = (
      length(google_monitoring_notification_channel.budget) == 1 &&
      google_monitoring_notification_channel.budget["lab-alerts@example.org"].type == "email" &&
      google_monitoring_notification_channel.budget["lab-alerts@example.org"].labels.email_address == "lab-alerts@example.org"
    )
    error_message = "Each budget_alert_emails entry becomes an e-mail notification channel."
  }

  assert {
    condition     = output.budget_name == "tx03v2-lab-monthly"
    error_message = "budget_name must name the budget that sends the alerts."
  }
}

run "no_extra_channel_by_default" {
  command = apply

  variables {
    budget_alert_emails = []
    budget_amount       = 25
  }

  assert {
    condition = (
      length(google_monitoring_notification_channel.budget) == 0 &&
      length(google_billing_budget.monthly.all_updates_rule[0].monitoring_notification_channels) == 0 &&
      google_billing_budget.monthly.amount[0].specified_amount[0].units == "25"
    )
    error_message = "Without e-mails no channel is created; budget_amount reaches the budget."
  }
}

run "rejects_a_billing_account_with_the_prefix" {
  command = plan

  variables {
    billing_account = "billingAccounts/000000-000000-000000"
  }

  expect_failures = [var.billing_account]
}

run "rejects_a_zero_budget" {
  command = plan

  variables {
    budget_amount = 0
  }

  expect_failures = [var.budget_amount]
}

run "rejects_a_fractional_budget" {
  command = plan

  variables {
    budget_amount = 7.5
  }

  expect_failures = [var.budget_amount]
}

run "rejects_an_invalid_alert_email" {
  command = plan

  variables {
    budget_alert_emails = ["not-an-email"]
  }

  expect_failures = [var.budget_alert_emails]
}

run "placeholder_alert_email_is_refused" {
  command = plan

  variables {
    budget_alert_emails = ["You@Example.com"]
  }

  expect_failures = [var.budget_alert_emails]
}
