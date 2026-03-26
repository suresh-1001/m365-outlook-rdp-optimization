# Email Deliverability — SPF, DKIM, DMARC

This document covers the email authentication review performed as part of this engagement, ensuring outbound mail from Exchange Online is authenticated and delivered reliably.

---

## Why Email Deliverability Matters

Without proper DNS email authentication, outbound mail from your Exchange Online tenant may:
- Land in recipients' spam/junk folders
- Be rejected by recipient mail servers
- Be spoofable by third parties impersonating your domain
- Fail DMARC alignment checks at major providers (Gmail, Microsoft, Yahoo)

---

## The Three Authentication Layers

```
Outbound email from Exchange Online
        │
        ▼
   SPF Check ──────── Does this IP have permission to send for this domain?
        │
        ▼
  DKIM Signing ──────── Is this email cryptographically signed by the domain?
        │
        ▼
 DMARC Evaluation ────── Do SPF and DKIM align with the From: header domain?
        │
        ▼
  Recipient Inbox (PASS) or Spam/Reject (FAIL)
```

---

## SPF (Sender Policy Framework)

SPF is a DNS TXT record that lists which mail servers are authorized to send email for your domain.

### Exchange Online SPF Record

Add this TXT record to your domain's DNS:

| Record Type | Host | Value |
|---|---|---|
| TXT | `@` | `v=spf1 include:spf.protection.outlook.com -all` |

**What this means:**
- `include:spf.protection.outlook.com` — authorizes all Microsoft Exchange Online IPs
- `-all` — hard fail: any server NOT in the list is unauthorized (recommended)
- `~all` — soft fail: unauthorized servers are flagged but not rejected (use during testing)

### Verify SPF

```powershell
# Check SPF record
Resolve-DnsName -Name "yourdomain.com" -Type TXT | Where-Object { $_.Strings -like "*spf*" }
```

Or via command line:
```bash
dig TXT yourdomain.com
nslookup -type=TXT yourdomain.com
```

**Expected result:** `v=spf1 include:spf.protection.outlook.com -all`

---

## DKIM (DomainKeys Identified Mail)

DKIM adds a cryptographic signature to outbound emails. The recipient's mail server verifies the signature using a public key published in your DNS.

### Enable DKIM in Exchange Online

1. Go to **Microsoft Defender portal** → https://security.microsoft.com
2. Navigate to: **Email & Collaboration → Policies & Rules → Threat Policies → Email Authentication Settings**
3. Select the **DKIM** tab
4. Find your domain → click **Enable**
5. Microsoft will display two CNAME records to add to your DNS

### DNS Records Required

| Record Type | Host | Value |
|---|---|---|
| CNAME | `selector1._domainkey.yourdomain.com` | `selector1-yourdomain-com._domainkey.yourdomain.onmicrosoft.com` |
| CNAME | `selector2._domainkey.yourdomain.com` | `selector2-yourdomain-com._domainkey.yourdomain.onmicrosoft.com` |

> ⚠️ DNS propagation can take up to 48 hours. Do not enable DKIM in the Defender portal until the CNAME records are confirmed live.

### Verify DKIM

```powershell
# Check DKIM selector 1
Resolve-DnsName -Name "selector1._domainkey.yourdomain.com" -Type CNAME

# Check DKIM selector 2
Resolve-DnsName -Name "selector2._domainkey.yourdomain.com" -Type CNAME
```

---

## DMARC (Domain-based Message Authentication, Reporting and Conformance)

DMARC builds on SPF and DKIM. It tells recipient mail servers what to do when an email fails SPF or DKIM, and where to send reports.

### Recommended DMARC Rollout — Three Phases

**Phase 1 — Monitor (Start Here)**

```
v=DMARC1; p=none; rua=mailto:dmarc-reports@yourdomain.com
```

- `p=none` — no action taken on failure, just report
- `rua=` — aggregate report destination (check this email for delivery insights)
- Run in this mode for 2–4 weeks before moving to enforcement

**Phase 2 — Quarantine**

```
v=DMARC1; p=quarantine; pct=25; rua=mailto:dmarc-reports@yourdomain.com
```

- `p=quarantine` — failing emails go to spam
- `pct=25` — apply to 25% of failing mail initially, increase over time

**Phase 3 — Reject (Full Enforcement)**

```
v=DMARC1; p=reject; rua=mailto:dmarc-reports@yourdomain.com; ruf=mailto:dmarc-reports@yourdomain.com
```

- `p=reject` — failing emails are rejected outright
- `ruf=` — forensic report destination (individual failure details)

### Add DMARC DNS Record

| Record Type | Host | Value |
|---|---|---|
| TXT | `_dmarc.yourdomain.com` | `v=DMARC1; p=none; rua=mailto:dmarc-reports@yourdomain.com` |

### Verify DMARC

```powershell
Resolve-DnsName -Name "_dmarc.yourdomain.com" -Type TXT
```

```bash
dig TXT _dmarc.yourdomain.com
```

---

## AWS SES Integration (If Applicable)

If the organization uses AWS SES for transactional email alongside Exchange Online:

### SPF for AWS SES

Add `include:amazonses.com` to your existing SPF record:

```
v=spf1 include:spf.protection.outlook.com include:amazonses.com -all
```

> ⚠️ SPF has a 10-lookup limit. Adding too many `include:` statements causes SPF to fail. Audit all your sending sources before adding new ones.

### DKIM for AWS SES

1. In AWS SES console → Verified identities → select domain → DKIM
2. AWS provides three CNAME records
3. Add them to your DNS
4. Wait for verification to complete in the SES console

### DMARC Alignment with SES

For DMARC alignment, emails sent via SES must either:
- Pass SPF with the From: domain (use custom MAIL FROM domain in SES), OR
- Pass DKIM signed with the From: domain (use SES DKIM signing)

---

## Full Authentication Validation Checklist

- [ ] SPF record present: `v=spf1 include:spf.protection.outlook.com -all`
- [ ] SPF includes all sending services (Exchange Online, SES, any third-party senders)
- [ ] SPF lookup count is under 10
- [ ] DKIM CNAME records are live in DNS
- [ ] DKIM enabled in Microsoft Defender / Exchange Online
- [ ] DKIM selectors validate: `selector1._domainkey.yourdomain.com`
- [ ] DMARC TXT record present: `_dmarc.yourdomain.com`
- [ ] DMARC policy progressed to at least `p=quarantine` after monitoring period
- [ ] Test email sent — check headers for `Authentication-Results: dmarc=pass`

### Test Authentication

Send a test email to **mail-tester.com** or **mxtoolbox.com** to verify SPF, DKIM, and DMARC are passing end-to-end.

Also check full headers of a received email:
- In Outlook: File → Properties → Internet headers
- Look for: `Authentication-Results: spf=pass; dkim=pass; dmarc=pass`
