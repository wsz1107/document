# Redmine → Jira Auto-Sync Plugin

**Requirement Specification**

---

## 1. Goal

Develop a **Redmine plugin (Ruby)** that automatically creates a **Jira issue** when a Redmine issue meets specific conditions, and then **writes the Jira issue key back to the Redmine issue**.

The plugin must be **safe, idempotent, configurable**, and suitable for **production use**.

---

## 2. Trigger Conditions

The plugin must execute **only when ALL of the following conditions are met**:

1. A **Redmine issue already exists** (not during initial creation).
2. The issue is **updated**, and its **status changes** to a configured **“Accepted”** status.
3. The user who performed the update:

   * Is logged in
   * Has a **specific Role** in the **same Project** as the issue
4. The Redmine issue **does NOT already have a Jira issue key** stored.

If **any condition is not met**, the plugin must **do nothing**.

---

## 3. Jira Issue Creation

When triggered, the plugin must:

1. Create **exactly one Jira issue** using the Jira REST API.
2. Use **Jira Cloud authentication**:

   * Email + API Token (HTTP Basic Auth)
3. Populate required Jira fields:

   * `project.key` (configurable)
   * `issuetype.name` (configurable, e.g. `Task`)
   * `summary` (generated from a configurable template)
4. Populate optional fields:

   * `description` from the Redmine issue description
   * Additional fields may be added later (design must be extensible)

---

## 4. Redmine Update After Success

If Jira issue creation **succeeds**:

1. Store the Jira issue key (e.g. `ABC-123`) in a **Redmine Issue Custom Field** named:

   * `Jira Key`
2. Add a **journal note** to the Redmine issue, for example:

   * `Jira issue created: ABC-123`
3. The Redmine update must be **transactional** (no partial state).

If Jira issue creation **fails**:

* Do **not** write the Jira key
* Log the error
* Optionally add a failure note to the journal (must not block the user)

---

## 5. Idempotency Rules (Critical)

* The plugin must **never create more than one Jira issue per Redmine issue**.
* If the `Jira Key` custom field already has a value:

  * Jira creation must be skipped entirely.
* Re-saving or re-editing the issue after it reaches “Accepted” must **not** trigger another Jira issue.

---

## 6. Background Processing

* Jira API calls **must not block** the Redmine request lifecycle.
* Jira issue creation must run in a **background job**.
* The job must:

  * Be retryable
  * Log failures clearly
  * Be safe to re-run without creating duplicates

---

## 7. Configuration (Admin UI)

The plugin must provide a **Redmine Admin settings page** with the following configurable values:

* Enable / Disable sync (boolean)
* Accepted Status ID
* Role ID allowed to trigger sync
* Jira Base URL
* Jira Project Key
* Jira Issue Type
* Jira Email
* Jira API Token
* Jira Summary Template

  * Example: `[RM#{issue.id}] #{issue.subject}`

**No values may be hard-coded.**

---

## 8. Technical Constraints

* Redmine version: **5.x**
* Architecture:

  * Use **Redmine plugin hooks**
  * Prefer `model_issue_after_save`
  * No controller overrides
* Language: **Ruby (Rails style)**
* Jira API: **REST API v3**
* Storage:

  * Jira issue key stored **only** in Redmine custom field
* Logging:

  * Use Rails logger
* Dependencies:

  * Avoid external gems unless strictly necessary

---

## 9. Explicit Non-Goals (Out of Scope)

The following features are **not included** in this version:

* Two-way sync (Jira → Redmine)
* Updating Jira issues after creation
* Bulk backfill of existing Redmine issues
* Jira webhooks
* Multi-Jira project routing

---

## 10. Success Criteria

The implementation is considered complete when:

* Exactly **one** Jira issue is created per qualifying Redmine issue
* Only users with the configured role can trigger the sync
* Jira issue key is reliably written back to Redmine
* No duplicate Jira issues are ever created
* Redmine UI performance is unaffected
* All behavior is configurable via Admin UI

