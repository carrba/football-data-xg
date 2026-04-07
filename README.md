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
  index.html          # Static web UI (dark-themed form → calls the API)
  Dockerfile          # Container image for Lambda (linux/amd64)
  requirements.txt    # Python deps: xgboost, scikit-learn, pandas, boto3
  build_image.ps1     # PowerShell helper to build & push the Docker image
  input_example.json  # Example request payload
  models/             # Trained model artefacts (xgboost.pkl, preprocessor.pkl)

terraform/            # Infrastructure-as-Code (AWS, Terraform ≥ 5.x provider)
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
| `defender_density` | Defenders within a ~3-unit radius |
| `defenders_between` | Defenders blocking the sightline to goal |

---

## Quickstart

### 1. Install dependencies

```bash
pip install -r src/requirements.txt
```

### 2. Run the notebooks

Open the notebooks in order:

1. `01_load_statsbomb_data.ipynb` — builds `data/shots_clean.csv` from the raw StatsBomb event files.
2. `02_train_xg_model.ipynb` — trains the XGBoost model and saves artefacts under `src/models/`.
3. `03_predict_from_image.ipynb` — optional: run predictions from a pitch image.

### 3. Test the Lambda handler locally

```bash
python - <<'EOF'
import json, src.lambda_function as lf
event = json.load(open("src/input_example.json"))
print(lf.lambda_handler(event, None))
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

- AWS CLI configured (`aws configure` or named profile `my-profile`)
- Docker (for building the Lambda container image)
- Terraform ≥ 1.5

### Deploy

```bash
# 1. Provision infrastructure
cd terraform
terraform init
terraform apply -var-file=terraform.tfvars

# 2. Build & push the container image (commands printed by Terraform)
terraform output -raw docker_push_commands | bash

# 3. Upload the web UI and model artefacts to S3
aws s3 cp src/index.html        s3://<bucket>/index.html
aws s3 cp src/models/           s3://<bucket>/models/ --recursive
```

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
  "nearest_defender": 10,
  "defender_density": 0,
  "defenders_between": 1
}
```

Only `shot_x` and `shot_y` are required; all other fields have sensible defaults.

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
