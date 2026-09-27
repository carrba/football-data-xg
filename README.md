# football-data-xG

A machine-learning pipeline that trains an **Expected Goals (xG)** model on StatsBomb open data and deploys it as a serverless API with a web front-end on AWS.

---

## What is xG?

Expected Goals (xG) is a metric that estimates the probability a shot results in a goal, based on the shot's location and context (body part used, defensive pressure, goalkeeper position, etc.). A value of `0.9` means the shot had a 90 % chance of being scored.

---

## Project structure

```
data/
  shots_clean.csv          # Pre-processed shots dataset
  statsbomb/
    competitions.json      # StatsBomb competition metadata
    events/                # Raw StatsBomb event JSON files (one per match)
    matches/               # Match metadata

notebooks/
  01_load_statsbomb_data.ipynb   # Parse raw StatsBomb events → shots_clean.csv
  02_train_xg_model.ipynb        # Train & evaluate XGBoost xG model
  03_predict_from_image.ipynb    # Ad-hoc prediction from a pitch image, translated into pitch coordinates using Statsbombs 120x80 standard.

src/
  lambda_function.py  # AWS Lambda handler — accepts shot features, returns xG
  features.py         # Shot feature engineering shared by notebook 01 and the Lambda
  index.html          # Static web UI (click-to-place pitch → calls the API)
  Dockerfile          # Container image for Lambda (linux/amd64)
  requirements.txt    # Python deps: xgboost, scikit-learn, pandas, boto3
  build_image.ps1     # PowerShell helper to build & push the Docker image
  input_example.json  # Example request payload

models/               # Trained model artefacts (xgboost.pkl, preprocessor.pkl) — git-ignored
                      # Written by 02_train_xg_model.ipynb, uploaded to S3 by Terraform

terraform/            # Infrastructure-as-Code (AWS provider ~> 6.x)
  main.tf             # Provider & backend config
  lambda.tf           # Lambda function + IAM role
  ecr.tf              # ECR repository for the container image
  s3.tf               # S3 bucket (static site + model artefacts)
  cfn.tf              # CloudFront distribution (CDN + origin routing)
  apigw.tf            # API Gateway (optional HTTP API layer)
  cloudwatch.tf       # Alarms & log groups
  outputs.tf          # CloudFront URL, ECR URL, helper push commands
  variables.tf        # Input variables
  terraform.tfvars    # Your environment values (not committed)
```

---

## Model features

| Feature | Description |
|---|---|
| `shot_x / shot_y` | Shot location on the 120 × 80 pitch |
| `distance` | Straight-line distance to goal centre (derived) |
| `angle` | Angle to goal (derived) |
| `body_part` | Right Foot / Left Foot / Head / Other |
| `play_type` | Open Play / Free Kick / Penalty |
| `under_pressure` | Defender within ~2 m at the moment of the shot |
| `keeper_x / keeper_y` | Goalkeeper position |
| `nearest_defender` | Distance to the closest outfield defender |
| `defender_density` | Defenders within 5 units (~5 yards) of the shooter |
| `defenders_between` | Defenders inside the shooting cone (triangle shooter → left post → right post) |

The defender features are computed from player positions by `src/features.py`,
used both when building the training data (notebook 01) and by the Lambda when a
request sends `defenders` positions, so training and serving can't drift.

---

## Quickstart

### 1. Install dependencies

```bash
pip install -r src/requirements.txt
```

### 2. Run the notebooks

Open the notebooks in order:

1. `01_load_statsbomb_data.ipynb` — builds `data/shots_clean.csv` from the raw StatsBomb event files.
2. `02_train_xg_model.ipynb` — trains the XGBoost model and saves artefacts under `models/` (repo root).
3. `03_predict_from_image.ipynb` — optional: run predictions from a pitch image.

### 3. Test the Lambda handler locally

```bash
cd src
python - <<'EOF'
import json, lambda_function as lf
event = json.load(open("input_example.json"))
print(lf.handler(event, None))
EOF
```

---

## AWS deployment

All cloud resources are managed with Terraform. The architecture is:

```
Browser → CloudFront → S3 (index.html)
                    ↘ Lambda Function URL (xG prediction API)
                         ↑
                      ECR (container image)
                      S3  (model artefacts: xgboost.pkl, preprocessor.pkl)
```

### Prerequisites

- AWS CLI configured — Terraform uses the named profile set in `terraform/main.tf` (`itbc-test` by default; change it or override with `AWS_PROFILE`)
- Docker (for building the Lambda container image)
- Terraform ≥ 1.5 (AWS provider `~> 6.42`, pinned in `terraform/main.tf`)

### Deploy

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply -var-file=terraform.tfvars

# 2. Build & push the container image (commands printed by Terraform)
terraform output -raw docker_push_commands | bash

# 3. Re-apply — the Lambda's image_uri is resolved from the ":latest" tag's
#    digest (see lambda.tf), so a new push is a real plan diff and this
#    rolls the function onto it automatically.
terraform apply -var-file=terraform.tfvars
```

`index.html`, the pitch diagram, and the model artefacts under `models/` are
uploaded to S3 by Terraform (`s3.tf`) — no manual `aws s3 cp` step is needed.
Re-run `terraform apply` whenever those files change.

Note: a model-only update (new `.pkl`s, no code change) uploads to S3 fine,
but Lambda caches the model in memory per execution environment with no
freshness check — warm containers keep serving the old model until they
recycle. Force it with a no-op config touch:
`aws lambda update-function-configuration --function-name football-xg-predict --description "models refreshed $(date -u +%Y-%m-%dT%H:%M:%SZ)"`.
A real code/image deploy (the steps above) doesn't need this — updating
`image_uri` already invalidates warm environments on its own.

The `cloudfront_url` Terraform output is the public URL for the xG predictor.

---

## API reference

**POST** `<lambda_function_url>`

```json
{
  "shot_x": 104.0,
  "shot_y": 45.0,
  "body_part": "Right Foot",
  "play_type": "Open Play",
  "under_pressure": false,
  "keeper_x": 118.0,
  "keeper_y": 42.0,
  "defenders": [[110.0, 41.0], [102.5, 46.7]]
}
```

Only `shot_x` and `shot_y` are required; all other fields have sensible defaults.

`defenders` is a list of outfield defender positions (max 20, goalkeeper excluded);
the Lambda derives `nearest_defender`, `defender_density` and `defenders_between`
from it. Instead of `defenders` you can send those three values directly
(e.g. `"nearest_defender": 10, "defender_density": 0, "defenders_between": 1`) —
if both are sent, `defenders` wins. With an empty list, the features get the same
fills as missing values in training.

**Response**

```json
{
  "xg": 0.23,
  "features": {
    "distance": 18.4,
    "angle": 0.41,
    ...
  }
}
```

---

## Data

Shot data comes from the [StatsBomb open data](https://github.com/statsbomb/open-data) repository (free to use for non-commercial purposes under the StatsBomb Open Data Licence).

---

## Tech stack

| Layer | Technology |
|---|---|
| Data & modelling | Python, pandas, scikit-learn, XGBoost |
| Serving | AWS Lambda (container), Lambda Function URL |
| Front-end | Vanilla HTML/CSS/JS, hosted on S3 + CloudFront |
| Infrastructure | Terraform, ECR, S3, CloudFront, CloudWatch |
