"""
Shot feature engineering shared by training (notebooks/01) and serving
(lambda_function.py), so the model sees the same features in both places.

All coordinates are on the StatsBomb 120 x 80 grid: x runs 0 (own goal line)
-> 120 (opponent goal line), y runs 0 -> 80, goal centre at (120, 40).
"""

import math

import numpy as np

GOAL_CENTRE = np.array([120.0, 40.0])
LEFT_POST = np.array([120.0, 36.0])
RIGHT_POST = np.array([120.0, 44.0])

DENSITY_RADIUS = 5.0


def distance(shot_x: float, shot_y: float) -> float:
    """Straight-line distance from the shot to the goal centre."""
    return math.sqrt((120 - shot_x) ** 2 + (40 - shot_y) ** 2)


def angle(shot_x: float, shot_y: float) -> float:
    """Angle (radians) subtended by the goalposts from the shot position."""
    shot = np.array([shot_x, shot_y])
    vec_l = LEFT_POST - shot
    vec_r = RIGHT_POST - shot
    cos_angle = np.dot(vec_l, vec_r) / (
        np.linalg.norm(vec_l) * np.linalg.norm(vec_r) + 1e-9
    )
    return float(np.arccos(np.clip(cos_angle, -1, 1)))


def _in_shot_cone(point, shooter) -> bool:
    """Is `point` inside the triangle shooter -> left post -> right post?"""
    v0 = LEFT_POST - shooter
    v1 = RIGHT_POST - shooter
    v2 = point - shooter

    dot00 = np.dot(v0, v0)
    dot01 = np.dot(v0, v1)
    dot02 = np.dot(v0, v2)
    dot11 = np.dot(v1, v1)
    dot12 = np.dot(v1, v2)

    inv_denom = 1 / (dot00 * dot11 - dot01 * dot01 + 1e-9)
    u = (dot11 * dot02 - dot01 * dot12) * inv_denom
    v = (dot00 * dot12 - dot01 * dot02) * inv_denom
    return u >= 0 and v >= 0 and (u + v) <= 1


def defender_features(shooter, defenders, radius: float = DENSITY_RADIUS):
    """
    Defender-context features for one shot.

    shooter   : (x, y) of the shot
    defenders : iterable of (x, y) for opposing outfield players (goalkeeper
                excluded)

    Returns (nearest_defender, defender_density, defenders_between). With no
    defenders all three are NaN, matching training — the caller fills them
    (see notebooks/02 and lambda_function.py).
    """
    defenders = [np.asarray(d, dtype=float) for d in defenders]
    if not defenders:
        return (math.nan, math.nan, math.nan)

    s = np.asarray(shooter, dtype=float)
    dists = [float(np.linalg.norm(d - s)) for d in defenders]

    nearest = min(dists)
    density = int(sum(dist <= radius for dist in dists))
    between = int(sum(bool(_in_shot_cone(d, s)) for d in defenders))
    return (nearest, density, between)
