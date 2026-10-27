#!/usr/bin/env bash
# Builds one static site: the landing page at / and the Flutter web app at /app/.
# Deploy the resulting site/ folder to Appwrite Sites (or any static host).
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf site
mkdir -p site
cp landing/index.html site/index.html

(cd app && flutter build web --release --base-href /app/)
cp -r app/build/web site/app

echo "Built site/ — landing at /, web app at /app/"
