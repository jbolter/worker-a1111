#!/bin/bash

set -Eeuox pipefail

mkdir -p /"$1"/"$2"
cd /"$1"/"$2"
git init
git remote add origin "$3"
git fetch origin "$4" --depth=1
git reset --hard "$4"
rm -rf .git
