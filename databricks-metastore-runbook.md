# Unity Catalog Metastore + Storage — Verified Runbook

Companion to `databricks-workspace-runbook.md`. Covers creating a Unity Catalog
**metastore**, plus the **storage credential**, **external location**, and
**managed storage location** objects that govern where data lives.

---

## The mental model (how the three Databricks docs fit together)

```
Metastore (one per region, account-level)          <- the top container
  |  (optional) metastore-level managed storage
  |
  +-- Storage credential  = IAM role UC assumes to reach an S3 bucket
  |      |
  |      +-- External location = a specific S3 path, governed, backed by that credential
  |             |
  |             +-- Catalog MANAGED LOCATION   <- managed tables for this catalog land here
  |                    +-- Schema MANAGED LOCATION (optional, overrides catalog)
```

| Doc | What it builds | Why |
|---|---|---|
| **Create a metastore** | the metastore + optional metastore-level managed storage (bucket + role) | the top container; one per region |
| **Storage credential + external location** | register an IAM role (credential) and an S3 path (location) with UC | lets UC read/write *additional* buckets/paths -> enables external tables & catalog managed storage |
| **Specify a managed storage location** | choose where managed tables/volumes physically land (metastore / catalog / schema) | lower level overrides higher; **catalog-level recommended** for data isolation |

**Key rule:** only **ONE metastore per region per account**. To practice creating one, use a region that doesn't already have a metastore (e.g. `us-east-1`).

---

## The shared role pattern (same as workspace-runbook Part 4)

Every time UC needs to touch S3 — metastore managed storage, a storage credential,
an external location — it uses a role with the **same shape**:

- **Trust policy:** UC master role (`arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL`) **+ self-assume** + your ExternalId
- **Permission policy:** S3 access to the bucket (object actions on `/*`, bucket actions on the bucket ARN) + self-assume

> This is identical to `databricks-uc-role` in the workspace runbook. Reuse the pattern; just point it at the relevant bucket.

### Fixed values
- Region for this metastore: `<REGION>` (e.g. `us-east-1`) — bucket, role storage, metastore all match
- Databricks AWS account (static): `414351767826`
- UC master role (static): `arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL`
- Your AWS account: `<AWS-ACCT>`
- Databricks account ID: `<DBX-ACCT-ID>`

---

## PART A — Create the metastore (Databricks doc 1)

### A.1 (Optional) S3 bucket for metastore-level managed storage
- Create an S3 bucket in `<REGION>`, SSE-S3, **no dots** in the name, **no S3 ACL** attached.
- One dedicated bucket per metastore.
- Note the path `s3://<metastore-bucket>/`.
- > Metastore-level managed storage is **optional**. Databricks recommends setting managed storage at the **catalog** level instead (Part C). You can create the metastore with no managed storage and add catalog-level storage later.

### A.2 (Optional) IAM role for that bucket
Same role pattern as workspace Part 4 — see PART B below for the exact JSON (it's the storage-credential role). Point it at the metastore bucket.

### A.3 Create the metastore
Account console -> **Catalog** -> **Create metastore**:
- **Name:** e.g. `metastore-<region>`
- **Region:** `<REGION>` (must match the bucket region and the workspaces that will use it)
- **(Optional) S3 bucket path + IAM role** from A.1/A.2 (omit if no metastore-level storage)
- **Create** -> when prompted, **assign a workspace** in that region (or leave unassigned if you have none there yet).

### A.4 Post-creation admin
- **Transfer metastore admin to a group** (the creator is admin by default; Databricks recommends a group).
- **Add CORS to the managed-storage bucket** (needed for uploads to managed volumes):
  ```json
  [
    {
      "AllowedHeaders": [],
      "AllowedMethods": ["PUT"],
      "AllowedOrigins": ["https://*.databricks.com"],
      "ExposeHeaders": [],
      "MaxAgeSeconds": 1800
    }
  ]
  ```
  (S3 -> bucket -> Permissions -> CORS.)

---

## PART B — Storage credential (Databricks doc 2)

A **storage credential** = an IAM role registered in UC so UC can reach an S3 bucket.
This is the SAME role pattern as workspace-runbook Part 4.

> **♻️ This role doubles as the workspace storage-config role.** The role you build here is the *same* UC-trust role the workspace runbook needs in its Part 4. **Build it ONCE here.** When you later create a workspace, do **not** create another UC role — reuse this one, and just ensure its permission policy's **Resource** list also includes the **workspace root bucket** (add `arn:aws:s3:::<root-bucket>` and `.../*` alongside the metastore/UC bucket). One UC role, pointed at every bucket UC must reach, used for both the metastore storage credential and the workspace storage configuration.

> **Important ordering quirk (self-assume):** Databricks' doc has you create the role with a **placeholder ExternalId `0000`** first, register it in Databricks to get the **real external ID**, then update the trust policy with that external ID + self-assume. If you already know your storage credential's external ID (or you're reusing the proven one-shot pattern), you can set the final trust policy directly. Either way, the final trust policy MUST be self-assuming, or validation fails with "Self Assume Role".

### B.1 Create the IAM role (final trust policy — UC master + self-assume)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL",
          "arn:aws:iam::<AWS-ACCT>:role/<THIS-ROLE-NAME>"
        ]
      },
      "Action": "sts:AssumeRole",
      "Condition": { "StringEquals": { "sts:ExternalId": "<STORAGE-CREDENTIAL-EXTERNAL-ID>" } }
    }
  ]
}
```
> `<STORAGE-CREDENTIAL-EXTERNAL-ID>` is given to you when you register the credential in Databricks (B.3). If following the strict doc flow, start with `0000` and update it after B.3. Role name in the self-assume ARN must match the real role name exactly.

### B.2 Permission policy (S3 + multipart + self-assume + optional KMS)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": ["arn:aws:s3:::<BUCKET>/*"]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": ["arn:aws:s3:::<BUCKET>"]
    },
    {
      "Effect": "Allow",
      "Action": ["sts:AssumeRole"],
      "Resource": ["arn:aws:iam::<AWS-ACCT>:role/<THIS-ROLE-NAME>"]
    }
  ]
}
```
> **Scoping rule (the gotcha):** object-level actions (`GetObject`, `PutObject`, `DeleteObject`, `ListMultipartUploadParts`, `AbortMultipartUpload`) go on the `/*` ARN; bucket-level actions (`ListBucket`, `GetBucketLocation`, `ListBucketMultipartUploads`) go on the bucket ARN. Mixing them up makes the IAM Policy Simulator show "denied" even though the grant exists.
>
> **KMS (only if the bucket is SSE-KMS):** add a statement with `kms:Decrypt`, `kms:Encrypt`, `kms:GenerateDataKey*` on the key ARN, AND add this role as a principal in the **KMS key policy**. Omit entirely for SSE-S3.

### B.3 Register the credential in Databricks
Workspace (linked to the metastore) -> **Catalog** -> **Connect > Credentials** -> **Create credential**:
- Type: **AWS IAM Role**
- Name + the **IAM Role ARN** from B.1
- Create -> **copy the External ID** shown.
- If you used placeholder `0000`, go back to B.1 and replace it with this External ID (self-assume trust).

### B.4 Validate
Catalog -> Credentials -> select it -> **Validate Configuration**. All checks (including **Self Assume Role**) must pass. If Self-Assume fails, fix the trust policy (B.1) to include the role's own ARN.

---

## PART C — External location + managed storage (Databricks docs 2 & 3)

### C.1 Create the external location (binds a path to the credential)
Catalog -> **Connect > External Locations** -> **Create external location** -> **Manual**:
- Name
- Storage type: **S3**
- URL: `s3://<bucket-path>`
- Storage credential: the one from Part B
- Create.

Or SQL:
```sql
CREATE EXTERNAL LOCATION `<location-name>`
URL 's3://<bucket-path>'
WITH (STORAGE CREDENTIAL `<storage-credential-name>`);
```

### C.2 Grant on the external location
- `CREATE MANAGED LOCATION` -> to use it as managed storage for a catalog/schema
- `CREATE EXTERNAL TABLE` / `CREATE EXTERNAL VOLUME` -> to create external tables/volumes
- (Catalog Explorer -> the location -> Permissions -> Grant.)

### C.3 Set managed storage (doc 3) — recommended at CATALOG level
Managed tables/volumes land in the managed location, resolved lowest-first:
**schema MANAGED LOCATION -> else catalog -> else metastore.**

```sql
-- recommended: per-catalog managed storage (must sit inside a registered external location)
CREATE CATALOG <catalog-name>
MANAGED LOCATION 's3://<external-location-bucket-path>/<directory>';

-- or change later
ALTER CATALOG <catalog-name>
SET MANAGED LOCATION 's3://<external-location-bucket-path>/<directory>';

-- optional: per-schema override
CREATE SCHEMA <catalog>.<schema-name>
MANAGED LOCATION 's3://<external-location-bucket-path>/<directory>';
```
> UC appends hashed subdirs under the storage root (`__unitystorage/...`). The path you give is the "Storage Root"; the full path is the "Storage Location". Managed locations **cannot overlap** external tables/volumes.

---

## Validation gates & common failures

| Symptom | Fix |
|---|---|
| "Self Assume Role" validation fails | trust policy must include the role's OWN ARN (self-assume) + correct ExternalId |
| storage credential validate fails on S3 | permission policy scoping (object actions on `/*`, bucket actions on bucket ARN); region match |
| KMS access denied | add KMS perms to the role AND add the role to the KMS key policy |
| can't create metastore (already exists) | one metastore per region — use a different region |
| catalog MANAGED LOCATION rejected | the path must be inside a registered external location |

---

## Checklist

- [ ] Metastore region has no existing metastore (one per region)
- [ ] Metastore bucket: same region, no dots, no S3 ACL, (SSE-S3 or KMS with key-policy grant)
- [ ] Storage-credential role: trust = UC master + **self-assume** + ExternalId; name matches self-assume ARN
- [ ] Permission policy correctly scoped (object vs bucket ARNs); multipart actions included
- [ ] Storage credential registered + **Validate Configuration** passes (incl. Self Assume Role)
- [ ] External location created and bound to the credential
- [ ] Grants on the external location (`CREATE MANAGED LOCATION` / `CREATE EXTERNAL TABLE`)
- [ ] Managed storage set at **catalog** level (recommended)
- [ ] CORS added to managed-storage bucket (for managed volume uploads)
- [ ] Metastore admin transferred to a group

---

## Relationship to the workspace runbook

- The **storage-credential role** (Part B) is the **same role pattern** as `databricks-uc-role` in `databricks-workspace-runbook.md` Part 4 — custom trust (UC master + self-assume) + S3 policy with multipart actions. Build once, reuse the shape.
- The **workspace** attaches to this **metastore**; the metastore holds **catalogs**; catalogs use **external locations** for **managed storage**. That's the full chain from compute down to where a managed table's bytes land.
