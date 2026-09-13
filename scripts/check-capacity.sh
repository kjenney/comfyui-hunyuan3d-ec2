#!/usr/bin/env bash
# check-capacity.sh — probe EC2 capacity pressure for specific instance types.
#
# EC2 has no public "free capacity" API. This script approximates where GPU
# capacity exists from two durable signals:
#
#   1. Offerings — which AZs currently advertise each instance type
#      (ec2:DescribeInstanceTypeOfferings). A type missing from an AZ can't be
#      launched there, period.
#
#   2. Spot price vs on-demand — current spot price vs the type's on-demand
#      price (ec2:DescribeSpotPriceHistory + pricing:GetProducts). Spot supply
#      is a good proxy for how contended the type+AZ is:
#        - spot near on-demand or far above baseline  -> tight; expect long waits
#        - spot well under on-demand (~30-70%)        -> healthy supply
#
# Usage:
#   ./scripts/check-capacity.sh [region] [instance-type] [type...]
#   ./scripts/check-capacity.sh
#   ./scripts/check-capacity.sh us-east-1 g6.4xlarge g5.4xlarge g6.12xlarge
#
# Defaults: region us-east-1, types = the GPU set variables.tf allows.
# Requires: aws cli + credentials (default profile, or AWS_PROFILE set).

set -euo pipefail

exec python3 - "$@" <<'PY'
import json
import os
import subprocess
import sys
from collections import defaultdict

REGION = sys.argv[1] if len(sys.argv) > 1 else "us-east-1"
TYPES = sys.argv[2:] or [
    "g5.4xlarge", "g5.12xlarge", "g6.4xlarge", "g6.12xlarge",
    "g7.2xlarge", "g7.12xlarge", "g7.24xlarge",
]

# Pricing API is global (always us-east-1); map region -> location name.
REGION_LOC = {
    "us-east-1": "US East (N. Virginia)",
    "us-east-2": "US East (Ohio)",
    "us-west-1": "US West (N. California)",
    "us-west-2": "US West (Oregon)",
    "eu-west-1": "EU West (Ireland)",
    "eu-west-2": "EU West (London)",
    "eu-central-1": "EU Central (Frankfurt)",
    "ap-south-1": "Asia Pacific (Mumbai)",
    "ap-southeast-1": "Asia Pacific (Singapore)",
    "ap-southeast-2": "Asia Pacific (Sydney)",
    "ap-northeast-1": "Asia Pacific (Tokyo)",
    "ap-northeast-2": "Asia Pacific (Seoul)",
    "sa-east-1": "South America (Sao Paulo)",
}


def aws(args, region=None):
    cmd = ["aws", "--region", region or REGION] + args
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        return json.loads(out.stdout) if out.stdout.strip() else {}
    except Exception:
        return {}


def ondemand_price(itype):
    loc = REGION_LOC.get(REGION)
    if not loc:
        return None
    data = aws(
        [
            "pricing", "get-products", "--region", "us-east-1",
            "--service-code", "AmazonEC2",
            "--filters",
            f"Type=TERM_MATCH,Field=instanceType,Value={itype}",
            "Type=TERM_MATCH,Field=operatingSystem,Value=Linux",
            "Type=TERM_MATCH,Field=tenancy,Value=Shared",
            f"Type=TERM_MATCH,Field=location,Value={loc}",
            "--query", "PriceList[0]",
            "--output", "text",
        ],
        region=None,
    )
    # PriceList entries come back as a JSON-string; --output text strips quoting,
    # but if it came through as a bare dict, handle both.
    raw = data if isinstance(data, str) else json.dumps(data)
    try:
        d = json.loads(raw)
        for v in d["terms"]["OnDemand"].values():
            for sku in v["priceDimensions"].values():
                return float(sku["pricePerUnit"]["USD"])
    except Exception:
        return None
    return None


def verdict(od, spot):
    if not od or spot is None:
        return ""
    r = spot / od
    if r >= 1.0:
        return "VERY TIGHT"
    if r >= 0.75:
        return "tight"
    if r >= 0.35:
        return "healthy"
    return "plentiful"


# 1. On-demand prices
od = {t: ondemand_price(t) for t in TYPES}

# 2. Spot price history (last hour)
ts = str(int(__import__("time").time()) - 3600)
spots = aws([
    "ec2", "describe-spot-price-history",
    "--instance-types", *TYPES,
    "--product-descriptions", "Linux/UNIX",
    "--start-time", ts,
]) .get("SpotPriceHistory", [])

# Latest spot price per (type, az) + running low
latest = {}
low = defaultdict(dict)
for s in spots:
    k = (s["InstanceType"], s["AvailabilityZone"])
    p = float(s["SpotPrice"])
    if k not in latest:
        latest[k] = (s.get("Timestamp"), p)
    lo = low[s["InstanceType"]].get(s["AvailabilityZone"])
    if lo is None or p < lo:
        low[s["InstanceType"]][s["AvailabilityZone"]] = p

# 3. Offerings per AZ
offers = aws([
    "ec2", "describe-instance-type-offerings",
    "--location-type", "availability-zone",
    "--filters", f"Name=instance-type,Values={','.join(TYPES)}",
    "--query", "InstanceTypeOfferings[].[InstanceType,Location]",
]) or []
offered_az = defaultdict(set)
for itype, az in offers:
    if az:
        offered_az[az].add(itype)

azs = sorted(offered_az) or [""]

print(f"Region: {REGION}   Types: {', '.join(TYPES)}\n")
print(f"{'INSTANCE TYPE':<14}{'AZ':<12}{'OFFERED':<9}{'SPOT $/hr':>10}"
      f"{'OD $/hr':>10}{'SPOT %OD':>9}  VERDICT")
print("-" * 80)
for az in azs:
    for t in TYPES:
        offered = "yes" if t in offered_az.get(az, set()) else ("NO" if az else "?")
        sp = latest.get((t, az))
        sp_s = f"{sp[1]:.4f}" if sp else "-"
        od_s = f"{od[t]:.4f}" if od.get(t) else "n/a"
        pct = f"{sp[1]/od[t]*100:.0f}" if sp and od.get(t) else "-"
        v = verdict(od.get(t), sp[1] if sp else None)
        print(f"{t:<14}{az:<12}{offered:<9}{sp_s:>10}{od_s:>10}{pct:>8}%  {v}")
    if az != azs[-1]:
        print()

if not spots and not offers:
    print("No data returned — check your AWS credentials and permissions:")
    print("  ec2:DescribeSpotPriceHistory, ec2:DescribeInstanceTypeOfferings,")
    print("  pricing:GetProducts")
PY
