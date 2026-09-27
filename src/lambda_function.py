"""
AWS Lambda handler for xG (expected goals) prediction.

Expected event JSON shape
-------------------------
Coordinates are on the StatsBomb 120 x 80 grid (origin top-left, y down).

Required fields:
  shot_x          : float  — 0 (own goal line) → 120 (opponent goal line)
  shot_y          : float  — 0 → 80 across the pitch

Optional fields (defaults shown):
  body_part       : str    — "Right Foot" | "Left Foot" | "Head" | "Other"  [default: "Right Foot"]
  play_type       : str    — "Open Play" | "Free Kick" | "Penalty"           [default: "Open Play"]
  under_pressure  : bool   — was a defender within ~2 m at the moment?       [default: false]
  keeper_x        : float  — goalkeeper x position (26–120)                  [default: 118.0]
  keeper_y        : float  — goalkeeper y position (21–61)                   [default: 40.0]
  defenders       : list   — [[x, y], ...] outfield defender positions (max 20). When
                             given, the three fields below are computed from it
                             (src/features.py) and any values sent for them are ignored.
  nearest_defender: float  — straight-line distance to closest defender      [default: 2.3]
  defender_density: int    — defenders within 5 units of the shooter (0–8)   [default: 1]
  defenders_between: int   — defenders inside the shooter → posts cone (0–10) [default: 0]

Response JSON shape
-------------------
  xg              : float  — predicted expected goals probability (0–1)
  features        : dict   — derived features used (distance, angle, …)
"""

import json
import math
import os

import boto3
import joblib
import pandas as pd

from features import angle, defender_features, distance

# ---------------------------------------------------------------------------
# Model loading — resolved relative to this file so it works both locally
# and inside a Lambda deployment package.
# ---------------------------------------------------------------------------
_HERE = os.path.dirname(os.path.abspath(__file__))
# Local-dev fallback: the notebooks and Terraform (s3.tf) treat the repo-root
# "models/" directory as canonical. In Lambda, MODELS_BUCKET is always set and
# the artefacts are pulled from S3 instead.
_MODELS_DIR = os.environ.get("MODELS_DIR", os.path.join(_HERE, os.pardir, "models"))
_MODELS_BUCKET = os.environ.get("MODELS_BUCKET")
_MODELS_CACHE = "/tmp/models"

_model = None
_preproc = None


def _load_models():
    global _model, _preproc
    if _model is not None:
        return

    if _MODELS_BUCKET:
        os.makedirs(_MODELS_CACHE, exist_ok=True)
        s3 = boto3.client("s3")
        for filename in ("xgboost.pkl", "preprocessor.pkl"):
            local_path = os.path.join(_MODELS_CACHE, filename)
            if not os.path.exists(local_path):
                s3.download_file(_MODELS_BUCKET, f"models/{filename}", local_path)
        models_dir = _MODELS_CACHE
    else:
        models_dir = _MODELS_DIR

    _model = joblib.load(os.path.join(models_dir, "xgboost.pkl"))
    _preproc = joblib.load(os.path.join(models_dir, "preprocessor.pkl"))


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------
VALID_BODY_PARTS = {"Right Foot", "Left Foot", "Head", "Other"}
VALID_PLAY_TYPES = {"Open Play", "Free Kick", "Penalty"}
MAX_DEFENDERS = 20
# Medians in data/shots_clean.csv — notebook 02 fills missing values with them,
# so inputs the model never had in training (no defenders placed, penalties)
# get the same treatment here.
_NEAREST_DEFENDER_FILL = 2.3345
_KEEPER_X_FILL = 118.1
_KEEPER_Y_FILL = 40.0


def _parse_defenders(raw) -> list:
    """Validate a [[x, y], ...] list of defender positions."""
    if not isinstance(raw, list):
        raise ValueError("defenders must be a list of [x, y] positions")
    if len(raw) > MAX_DEFENDERS:
        raise ValueError(f"defenders may contain at most {MAX_DEFENDERS} positions, got {len(raw)}")

    defenders = []
    for i, pos in enumerate(raw):
        if not isinstance(pos, (list, tuple)) or len(pos) != 2:
            raise ValueError(f"defenders[{i}] must be an [x, y] pair")
        x, y = float(pos[0]), float(pos[1])
        if not (0 <= x <= 120 and 0 <= y <= 80):
            raise ValueError(f"defenders[{i}] must be within 0–120 x 0–80, got [{x}, {y}]")
        defenders.append((x, y))
    return defenders


def _validate(event: dict) -> dict:
    """Return a normalised, validated parameter dict or raise ValueError."""
    params = {}

    # --- Required ---
    for field in ("shot_x", "shot_y"):
        if field not in event:
            raise ValueError(f"Missing required field: '{field}'")
        params[field] = float(event[field])

    if not (0 <= params["shot_x"] <= 120):
        raise ValueError(f"shot_x must be 0–120, got {params['shot_x']}")
    if not (0 <= params["shot_y"] <= 80):
        raise ValueError(f"shot_y must be 0–80, got {params['shot_y']}")

    # --- Optional with defaults ---
    body_part = str(event.get("body_part", "Right Foot")).strip().title()
    if body_part not in VALID_BODY_PARTS:
        raise ValueError(f"body_part must be one of {VALID_BODY_PARTS}, got '{body_part}'")
    params["body_part"] = body_part

    play_type = str(event.get("play_type", "Open Play")).strip().title()
    if play_type not in VALID_PLAY_TYPES:
        raise ValueError(f"play_type must be one of {VALID_PLAY_TYPES}, got '{play_type}'")
    params["play_type"] = play_type

    params["under_pressure"] = bool(event.get("under_pressure", False))

    if play_type == "Penalty":
        # Training penalties almost never have keeper/defender positions, so
        # notebook 02 filled them — use the same fills (not NaN or 0, which the
        # model never saw for penalties and scored at ~11%).
        params["keeper_x"] = _KEEPER_X_FILL
        params["keeper_y"] = _KEEPER_Y_FILL
        params["nearest_defender"] = _NEAREST_DEFENDER_FILL
        params["defender_density"] = 0
        params["defenders_between"] = 0
    else:
        params["keeper_x"] = float(event.get("keeper_x", 118.0))
        params["keeper_y"] = float(event.get("keeper_y", 40.0))
        if "defenders" in event:
            nearest, density, between = defender_features(
                (params["shot_x"], params["shot_y"]), _parse_defenders(event["defenders"])
            )
            # No defenders → NaN, filled exactly as notebook 02 fills training data
            params["nearest_defender"] = _NEAREST_DEFENDER_FILL if math.isnan(nearest) else nearest
            params["defender_density"] = 0 if math.isnan(density) else density
            params["defenders_between"] = 0 if math.isnan(between) else between
        else:
            params["nearest_defender"] = float(event.get("nearest_defender", 2.3))
            params["defender_density"] = int(event.get("defender_density", 1))
            params["defenders_between"] = int(event.get("defenders_between", 0))

    return params


# ---------------------------------------------------------------------------
# Feature engineering (shared with training via features.py)
# ---------------------------------------------------------------------------
def _build_features(params: dict) -> dict:
    sx, sy = params["shot_x"], params["shot_y"]

    return {
        "shot_x": sx,
        "shot_y": sy,
        "distance": distance(sx, sy),
        "angle": angle(sx, sy),
        "nearest_defender": params["nearest_defender"],
        "defender_density": params["defender_density"],
        "defenders_between": params["defenders_between"],
        "keeper_x": params["keeper_x"],
        "keeper_y": params["keeper_y"],
        "body_part": params["body_part"],
        "play_type": params["play_type"],
        "under_pressure": params["under_pressure"],
    }


# ---------------------------------------------------------------------------
# Lambda entry point
# ---------------------------------------------------------------------------
_RESPONSE_HEADERS = {"Content-Type": "application/json"}
_ORIGIN_SECRET = os.environ.get("ORIGIN_SECRET", "")


def handler(event: dict, context=None) -> dict:
    """
    AWS Lambda handler — supports both direct invocation and Lambda function URL.
    CORS is handled by the function URL configuration, not here.
    """
    # Reject requests that don't carry the CloudFront origin secret.
    # The header is injected by CloudFront and never visible to browsers.
    # Skip the check when ORIGIN_SECRET is not set (local dev / direct invocation).
    if _ORIGIN_SECRET:
        incoming = (event.get("headers") or {}).get("x-origin-secret", "")
        if not incoming or incoming != _ORIGIN_SECRET:
            return {
                "statusCode": 403,
                "headers": _RESPONSE_HEADERS,
                "body": json.dumps({"error": "Forbidden"}),
            }

    _load_models()

    # API Gateway HTTP API wraps the body as a JSON string under "body"
    if "body" in event:
        try:
            payload = json.loads(event["body"] or "{}")
        except (json.JSONDecodeError, TypeError):
            return {
                "statusCode": 400,
                "headers": _RESPONSE_HEADERS,
                "body": json.dumps({"error": "Request body is not valid JSON"}),
            }
    else:
        payload = event

    try:
        params = _validate(payload)
    except (ValueError, TypeError) as exc:
        return {
            "statusCode": 400,
            "headers": _RESPONSE_HEADERS,
            "body": json.dumps({"error": str(exc)}),
        }

    try:
        features = _build_features(params)
        df = pd.DataFrame([features])
        X = _preproc.transform(df)
        xg = float(_model.predict_proba(X)[0, 1])

        return {
            "statusCode": 200,
            "headers": _RESPONSE_HEADERS,
            "body": json.dumps(
                {
                    "xg": round(xg, 6),
                    "features": {
                        k: (None if (isinstance(v, float) and math.isnan(v)) else v)
                        for k, v in features.items()
                    },
                }
            ),
        }
    except Exception as exc:  # pylint: disable=broad-except
        return {
            "statusCode": 500,
            "headers": _RESPONSE_HEADERS,
            "body": json.dumps({"error": f"Prediction failed: {exc}"}),
        }
