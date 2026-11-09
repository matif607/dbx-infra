# Databricks Serverless Workspace - External Team Prerequisites

## Overview

Your Databricks workspace uses serverless compute with Databricks-managed storage. No workspace root bucket is needed.

Your team is responsible for creating:

1. **S3 Bucket** — stores your team's data (external location, not workspace storage)
2. **S3 Bucket Policy** — grants Databricks access to the bucket
3. **IAM Data Access Role** — assumed by Unity Catalog to read/write data in your S3 bucket

please provide us with the details listed at the bottom of the document. We will then:
- Register the IAM role as a **Storage Credential** in Unity Catalog
- Create **External Locations** for the S3 prefixes you specify
- Grant your team permissions to read/write through the storage credential

---

## 1. IAM Data Access Role

This role is assumed by Databricks Unity Catalog to access data in your S3 bucket.

### Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TrustUcMasterRole",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "<databricks-account-id>"
        }
      }
    },
    {
      "Sid": "SelfAssume",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<your-aws-account-id>:role/<this-role-name>"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

> **Notes:**
> - The `<databricks-account-id>` is the UUID-style ID from the Databricks Account console (Settings → Account → Account ID). This is **not** an AWS account ID. We will share this with you.
> - We will also share the **Metastore ID** — needed if you want to validate the storage credential setup.
> - The `SelfAssume` statement must reference the same role being created. Without it, Unity Catalog reports validation errors when creating the storage credential.
> - Always set `sts:ExternalId` — it prevents the confused-deputy attack pattern.
> - If the role was just created, IAM may take 30–60 seconds to propagate. Retry validation if it fails immediately after creation.

### Permissions Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3DataAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::<bucket-name>",
        "arn:aws:s3:::<bucket-name>/*"
      ]
    }
  ]
}
```

You can tighten `Resource` to specific prefixes if you want to restrict access per business domain.

### KMS-Encrypted Buckets

If the bucket uses a customer-managed KMS key, add this statement to the role's permissions policy **and** update the KMS key policy to grant the role access:

**Role permissions policy (additional statement):**

```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt",
    "kms:Encrypt",
    "kms:GenerateDataKey*",
    "kms:ReEncrypt*",
    "kms:DescribeKey"
  ],
  "Resource": "<kms-key-arn>"
}
```

**KMS key policy (add the role as a principal):**

```json
{
  "Sid": "AllowDatabricksRoleKmsAccess",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::<your-aws-account-id>:role/<this-role-name>"
  },
  "Action": [
    "kms:Decrypt",
    "kms:Encrypt",
    "kms:GenerateDataKey*",
    "kms:ReEncrypt*",
    "kms:DescribeKey"
  ],
  "Resource": "*"
}
```

> Without the KMS key policy, reads return decryption errors with no obvious hint that KMS is the problem.

---

## 2. S3 Bucket Policy

Add the following bucket policy to grant Databricks and our Terraform runner access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Grant Databricks Access",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::414351767826:root"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketNotification",
        "s3:PutBucketNotification",
        "s3:GetEncryptionConfiguration",
        "s3:GetLifecycleConfiguration",
        "s3:PutLifecycleConfiguration"
      ],
      "Resource": [
        "arn:aws:s3:::<bucket-name>/*",
        "arn:aws:s3:::<bucket-name>"
      ],
      "Condition": {
        "StringEquals": {
          "aws:PrincipalTag/DatabricksAccountId": "<databricks-account-id>"
        }
      }
    },
    {
      "Sid": "Grant Terraform Runner Access",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<our-aws-account-id>:role/<terraform-runner-role>"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::<bucket-name>/*",
        "arn:aws:s3:::<bucket-name>"
      ]
    }
  ]
}
```

> **Important:** Do NOT create empty "folder" objects in S3 (zero-byte objects with trailing `/` in the key name). These cause Spark errors on serverless compute. S3 prefixes are created implicitly when actual data files are written.

---

## Common Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Storage credential validation failed | Self-assume statement missing in trust policy | Add the `SelfAssume` statement |
| AccessDenied on a path in the prefix | External location URL doesn't match or trailing slash mismatch | Confirm the URL exactly matches; trailing slashes matter |
| Reads work, writes fail with KMS error | KMS key policy missing the IAM role | Add `kms:Encrypt`, `kms:GenerateDataKey*` to key policy |
| Validation passed but queries still fail | IAM changes haven't propagated | Wait 60s after IAM edits, then re-validate |

| LIST works but SELECT fails | `s3:GetObject` not granted (only `s3:ListBucket` was granted) | Add `s3:GetObject` to the role's permissions policy |

---

## Placeholders Reference

| Placeholder | Description | Example |
|---|---|---|
| `<bucket-name>` | S3 bucket name | `analytics-data-dev` |
| `<this-role-name>` | The IAM role name (same role being created) | `analytics-dev-data-access` |
| `<your-aws-account-id>` | Your AWS account ID | `123456789012` |
| `<our-aws-account-id>` | Our AWS account ID (for Terraform runner) — we will provide this | `987654321098` |
| `<terraform-runner-role>` | Our Terraform runner IAM role — we will provide this | `terraform-ci-role` |
| `<databricks-account-id>` | Databricks account ID — UUID from Account console (we will provide this) | `adfwefewq-qewqef-fefe-13re-1r331r13r1` |
| `<kms-key-arn>` | KMS key ARN (if using KMS encryption) | `arn:aws:kms:us-east-1:123456:key/abc` |


---

## What to Provide Us

| Item | Description | Example |
|---|---|---|
| S3 bucket name | Name of the bucket | `analytics-data-dev` |
| Data access role ARN | ARN of the IAM role created | `arn:aws:iam::123456789012:role/analytics-dev-data-access` |
| S3 prefixes | List of S3 prefixes your team needs access to (we create external locations for these) | `bronze/`, `silver/`, `gold/` |
| KMS key ARN (if applicable) | KMS key used for bucket encryption | `arn:aws:kms:us-east-1:123456:key/abc` |
| AWS region | Region where the bucket is located | `us-east-1` |
