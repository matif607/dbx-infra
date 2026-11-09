# Databricks Classic Workspace on AWS — Verified Runbook

A ClickOps runbook that actually succeeds, built from a real end-to-end debugging session.
Every "gotcha" here corresponds to a failure we hit and fixed.

---

## The #1 insight (the thing that finally worked)

There are **two IAM roles with different jobs**, and the hardest-won lesson is **which role each Databricks config uses**:

| Databricks config | Role it uses | Trust policy | S3 scope |
|---|---|---|---|
| **Compute credential** | compute role | trusts Databricks acct `414351767826` + ExternalId | none needed |
| **Workspace storage config** (root bucket) | **UC-trust role** (NOT the compute role!) | UC master role + **self-assume** | root bucket |
| **Metastore / UC storage credential** | UC-trust role | UC master role + **self-assume** | UC bucket |

> **The mistake that cost hours:** putting the root-bucket S3 permissions on the *compute role*. The storage-config validation does **not** use the compute role — it uses a role with **UC-master trust + self-assume**. So the root bucket's S3 permissions must live on a UC-trust role.

The simplest working setup: **one UC-trust role** (`databricks-uc-role`) that has S3 access to **both** the root bucket and the UC bucket, used for **both** the storage config and the metastore.

---

## Fixed values (keep consistent everywhere)

- **Region (everything):** `ap-south-1` — root bucket, UC bucket, VPC, metastore, workspace MUST match
- **Databricks AWS account (static):** `414351767826`
- **UC master role (static):** `arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL`
- **Your AWS account:** `<AWS-ACCT>` (e.g. `837484397818`)
- **Databricks account ID = ExternalId:** `<DBX-ACCT-ID>` (from account console; e.g. `930df241-...`)
- Root bucket: `dbx-root-<name>`  ·  UC bucket: `dbx-uc-<name>`
- Compute role: `databricks-compute-role`  ·  UC role: `databricks-uc-role`

---

## Gaps in the official Databricks doc (that caused failures)

1. Cross-account compute policy **omits** `ec2:DescribeNetworkAcls` and `ec2:DescribeVpcAttribute` -> network validation fails. **Add both.**
2. No mention that the root-bucket role needs **`s3:PutObjectAcl`** -> `PutWithBucketOwnerFullControl` denied. **Add it.**
3. Region-match is not emphasized -> an out-of-region bucket fails silently. **Everything same region.**
4. Doesn't make clear the **storage config role = UC-trust role**, not the compute role. **This is the big one.**
5. Easy copy/paste traps: spaces inside ARNs, trailing commas, hyphen/underscore role-name mismatches.

---

## PART 1 — Compute credential (cross-account role)

### 1.1 Create the role
IAM -> Roles -> Create role -> **AWS account -> Another AWS account**
- Account ID: `414351767826`
- Check **Require external ID** -> enter `<DBX-ACCT-ID>`
- Name: `databricks-compute-role`

### 1.2 Inline permission policy (doc policy + the 2 missing EC2 actions)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Compute",
      "Effect": "Allow",
      "Action": [
        "ec2:AllocateAddress","ec2:AssignPrivateIpAddresses","ec2:AssociateDhcpOptions",
        "ec2:AssociateIamInstanceProfile","ec2:AssociateRouteTable","ec2:AttachInternetGateway",
        "ec2:AttachVolume","ec2:AuthorizeSecurityGroupEgress","ec2:AuthorizeSecurityGroupIngress",
        "ec2:CancelSpotInstanceRequests","ec2:CreateDhcpOptions","ec2:CreateFleet",
        "ec2:CreateInternetGateway","ec2:CreateLaunchTemplate","ec2:CreateLaunchTemplateVersion",
        "ec2:CreateNatGateway","ec2:CreateRoute","ec2:CreateRouteTable","ec2:CreateSecurityGroup",
        "ec2:CreateSubnet","ec2:CreateTags","ec2:CreateVolume","ec2:CreateVpc","ec2:CreateVpcEndpoint",
        "ec2:DeleteDhcpOptions","ec2:DeleteFleets","ec2:DeleteInternetGateway","ec2:DeleteLaunchTemplate",
        "ec2:DeleteLaunchTemplateVersions","ec2:DeleteNatGateway","ec2:DeleteRoute","ec2:DeleteRouteTable",
        "ec2:DeleteSecurityGroup","ec2:DeleteSubnet","ec2:DeleteTags","ec2:DeleteVolume","ec2:DeleteVpc",
        "ec2:DeleteVpcEndpoints","ec2:DescribeAvailabilityZones",
        "ec2:DescribeNetworkAcls","ec2:DescribeVpcAttribute",
        "ec2:DescribeFleetHistory","ec2:DescribeFleetInstances","ec2:DescribeFleets",
        "ec2:DescribeIamInstanceProfileAssociations","ec2:DescribeInstanceStatus","ec2:DescribeInstances",
        "ec2:DescribeInternetGateways","ec2:DescribeLaunchTemplates","ec2:DescribeLaunchTemplateVersions",
        "ec2:DescribeNatGateways","ec2:DescribePrefixLists","ec2:DescribeReservedInstancesOfferings",
        "ec2:DescribeRouteTables","ec2:DescribeSecurityGroups","ec2:DescribeSpotInstanceRequests",
        "ec2:DescribeSpotPriceHistory","ec2:DescribeSubnets","ec2:DescribeVolumes","ec2:DescribeVpcs",
        "ec2:DetachInternetGateway","ec2:DisassociateIamInstanceProfile","ec2:DisassociateRouteTable",
        "ec2:GetLaunchTemplateData","ec2:GetSpotPlacementScores","ec2:ModifyFleet","ec2:ModifyLaunchTemplate",
        "ec2:ModifyVpcAttribute","ec2:ReleaseAddress","ec2:ReplaceIamInstanceProfileAssociation",
        "ec2:RequestSpotInstances","ec2:RevokeSecurityGroupEgress","ec2:RevokeSecurityGroupIngress",
        "ec2:RunInstances","ec2:TerminateInstances"
      ],
      "Resource": ["*"]
    },
    {
      "Effect": "Allow",
      "Action": ["iam:CreateServiceLinkedRole","iam:PutRolePolicy"],
      "Resource": "arn:aws:iam::*:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot",
      "Condition": { "StringLike": { "iam:AWSServiceName": "spot.amazonaws.com" } }
    }
  ]
}
```
> The compute role does **NOT** need any S3 permissions. (This was the core mistake.)

Copy its Role ARN -> use it as the **Compute credential** in the workspace form.

---

## PART 2 — Network (customer-managed VPC), all in `ap-south-1`

### 2.1 VPC (VPC -> Create VPC -> "VPC and more")
- 2 public + **2 private** subnets, across **2 AZs**
- NAT gateway: **In 1 AZ**
- **Enable DNS hostnames** AND **Enable DNS resolution** (both required)

### 2.2 Security group (`dbx-sg`)
**Inbound** (source = this same SG):
- All TCP, ports `0-65535`, source = itself
- All UDP, ports `0-65535`, source = itself

**Outbound**:
- All TCP -> itself · All UDP -> itself
- TCP `443` -> 0.0.0.0/0
- TCP `3306` -> 0.0.0.0/0
- TCP `6666` -> 0.0.0.0/0
- TCP `8443-8451` -> 0.0.0.0/0  (full range — not 8443-8446)
- TCP `5432` -> 0.0.0.0/0
- TCP `53` -> 0.0.0.0/0

### 2.3 Routing & NACL
- Private subnets' route table: `0.0.0.0/0` -> **NAT gateway**
- NACL: `100 ALLOW ALL` + `* DENY` (the AWS default = allow-all) on **both** inbound and outbound

### 2.4 Register network config
Account console -> **Security -> Classic network configurations -> Add**: name, VPC ID, the **two private subnet IDs**, the SG ID.

---

## PART 3 — Buckets (both in `ap-south-1`)

Create two S3 buckets, **same region as the workspace**, SSE-S3:
- `dbx-root-<name>` — workspace root storage
- `dbx-uc-<name>` — Unity Catalog storage

### ⭐ The two buckets need DIFFERENT treatment — this was the hardest bug

The **root bucket** and the **UC bucket** are validated by Databricks through **different paths**, so they need different setup:

| Bucket | Validated via | Bucket policy? |
|---|---|---|
| **UC bucket** (`dbx-uc-<name>`) — metastore / storage credential | the UC role (`dbx-uc-role`) assuming via STS | **No bucket policy needed** — same-account IAM on the role is enough |
| **Root bucket** (`dbx-root-<name>`) — workspace storage config | Databricks' **account principal `414351767826`** directly | **REQUIRES a bucket policy** allowing `414351767826:root` |

> **The trap that cost hours:** the workspace storage-config validation accesses the root bucket as Databricks' account `414351767826`, governed by the **bucket policy** — NOT by the IAM role alone. With no bucket policy on the root bucket, you get `List/Put/PutWithBucketOwnerFullControl/Delete Access Denied` even though the IAM role's simulator shows all Allowed. The UC bucket does NOT hit this because it's validated via the role's STS assume path.

### Root bucket policy (REQUIRED — add this to `dbx-root-<name>`)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Grant Databricks Access",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::414351767826:root" },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::dbx-root-<name>",
        "arn:aws:s3:::dbx-root-<name>/*"
      ]
    }
  ]
}
```
> **Do NOT add the `aws:PrincipalTag/DatabricksAccountId` condition** that appears in some Databricks docs — with the console/classic flow that condition isn't satisfied and causes the same denial. Use the plain `414351767826:root` allow above (no `Condition` block). `s3:PutObjectAcl` is included for the `PutWithBucketOwnerFullControl` check.

### UC bucket policy
Leave the **UC bucket** (`dbx-uc-<name>`) **without a bucket policy** — the metastore/storage-credential validation uses the role's STS assume path, so same-account IAM on `dbx-uc-role` is sufficient.

---

## PART 4 — The UC-trust role (used for BOTH storage config AND metastore)

> **⚠️ CHECK FIRST — you may already have this role.** This UC-trust role is the **same role** Databricks calls a "storage credential" role, and it is **most likely already created during metastore setup** (see `databricks-metastore-runbook.md` Part B). If you already have a UC role (e.g. `dbx-uc-role`) with: (a) trust = UC master + self-assume + your ExternalId, and (b) an S3 permission policy, then **do NOT create a new role** — just make sure its permission policy's **Resource** list includes **this workspace's root bucket** (add the root bucket if it only covers the metastore/UC bucket). Only create the role from scratch (4.1 + 4.2) if no UC role exists yet (e.g. your region had an auto-created metastore and you never set up a role).
>
> **Reusable pattern:** custom trust (UC master + self-assume) + an S3 permission policy with the multipart actions. You reuse it any time Unity Catalog needs to reach an S3 bucket — metastore managed storage, storage credentials, and external locations all use this same structure.

### 4.1 Create role with custom trust (UC master + self-assume)
IAM -> Create role -> **Custom trust policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
          "arn:aws:iam::<AWS-ACCT>:role/databricks-uc-role"
        ]
      },
      "Action": "sts:AssumeRole",
      "Condition": { "StringEquals": { "sts:ExternalId": "<DBX-ACCT-ID>" } }
    }
  ]
}
```
Name it **exactly** `databricks-uc-role` — the self-assume ARN above must match the real name character-for-character.

### 4.2 Permission policy — access to BOTH buckets + self-assume
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:DeleteObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": [
        "arn:aws:s3:::dbx-root-<name>/*",
        "arn:aws:s3:::dbx-uc-<name>/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": [
        "arn:aws:s3:::dbx-root-<name>",
        "arn:aws:s3:::dbx-uc-<name>"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["sts:AssumeRole"],
      "Resource": ["arn:aws:iam::<AWS-ACCT>:role/databricks-uc-role"]
    }
  ]
}
```
> **Action placement matters (resource type):**
> - **Object-level** actions go on the `/*` ARN: `GetObject`, `GetObjectVersion`, `PutObject`, `PutObjectAcl`, `DeleteObject`, `ListMultipartUploadParts`, `AbortMultipartUpload`.
> - **Bucket-level** actions go on the bucket ARN (no `/*`): `ListBucket`, `GetBucketLocation`, `ListBucketMultipartUploads`.
> If you put an object-level multipart action (`ListMultipartUploadParts` / `AbortMultipartUpload`) on the bucket ARN, the IAM Policy Simulator shows it "denied" — a scoping mismatch, not a missing grant.
>
> **Required by Databricks:** `GetObject`, `PutObject`, `DeleteObject`, `ListBucket`, `GetBucketLocation`, plus `s3:PutObjectAcl` (satisfies the `PutWithBucketOwnerFullControl` check). The three **multipart** actions are from the metastore doc — recommended for large/multipart uploads but not strictly required for workspace/storage validation. The **self-assume** statement is required for the UC credential flow.

---

## PART 5 — Databricks configs (which role goes where)

| Config (in workspace form / account console) | Bucket | Role ARN |
|---|---|---|
| **Compute credential** | — | `databricks-compute-role` |
| **Workspace storage configuration** | `dbx-root-<name>` | **`databricks-uc-role`** <- NOT the compute role |
| **Metastore / UC storage credential** | `dbx-uc-<name>` | `databricks-uc-role` |
| **Network configuration** | — | the VPC config from Part 2 |

---

## PART 6 — Create the workspace

Account console -> **Create workspace** (use a **fresh browser / incognito** to avoid the stale "Workspace information is not available" error):
- **Name:** a NEW name not used by any failed attempt
- **Region:** `ap-south-1`
- **Compute credentials:** `databricks-compute-role`
- **Network configuration:** your VPC config
- **Workspace storage:** storage config on `dbx-root-<name>` using `databricks-uc-role`
- **Metastore:** `ap-south-1` metastore (UC role)
- **Private access setting:** None
- Create -> wait a few minutes for **Running**.

---

## Validation gates (what each failure means)

| Error mentions | Gate | Fix |
|---|---|---|
| credential validation / invalid cross account role | compute role trust | ExternalId must equal `<DBX-ACCT-ID>`; account = `414351767826` |
| network validation `DescribeNetworkAcls` / `DescribeVpcAttribute` | compute policy | add those two EC2 actions |
| network validation DNS | VPC | enable DNS hostnames + resolution |
| storage credential can't be assumed / no self-assume | UC role trust | UC master + self-assume; role name matches ARN |
| storage config List/Put/Delete **PutWithBucketOwnerFullControl** denied (role simulator shows Allowed) | **root bucket missing its bucket policy** | add the bucket policy to the ROOT bucket allowing `arn:aws:iam::414351767826:root` (NO `PrincipalTag` condition). The workspace storage-config validates via Databricks' account principal, not the IAM role — so the bucket policy is mandatory here. (THE BIG ONE.) |
| storage config denied even with role perms correct + ExternalId matching + region matching | same as above | it is almost always the **root bucket policy** — the IAM role being perfect does not matter for this path |
| "Workspace information is not available" | platform/session | fresh incognito, new workspace name |

---

## Final checklist

- [ ] Everything in `ap-south-1` (both buckets, VPC, metastore, workspace)
- [ ] Compute role: trust = `414351767826` + ExternalId; policy has `DescribeNetworkAcls` + `DescribeVpcAttribute`; **no S3 needed**
- [ ] VPC: DNS hostnames + resolution ON
- [ ] SG inbound: All TCP/UDP `0-65535` from self
- [ ] SG outbound: 443, 3306, 6666, **8443-8451**, 5432, 53 + self
- [ ] Private subnets route `0.0.0.0/0` -> NAT
- [ ] UC role: trust = UC master + **self-assume** + ExternalId; name matches the self-assume ARN exactly
- [ ] UC role policy covers **both** buckets, includes `s3:PutObjectAcl` + self-assume
- [ ] **Storage configuration uses the UC role (not the compute role)**
- [ ] **ROOT bucket HAS a bucket policy** allowing `arn:aws:iam::414351767826:root` (no `PrincipalTag` condition) — required; this is the #1 cause of storage-config denials
- [ ] UC bucket has NO bucket policy (role's STS path suffices)
- [ ] All ARNs typo-free (no spaces, no trailing commas, correct hyphens/underscores)
- [ ] Fresh browser session, new workspace name
