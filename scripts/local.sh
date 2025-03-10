#!/bin/sh

git pull -Xours

Rscript data-raw/update_cis.R
Rscript data-raw/update_ab.R

echo Local
Rscript scripts/estimate.R -d 1 -l && Rscript scripts/analyse.R -l

echo Regional
git status | grep -q cis.csv && Rscript scripts/estimate.R -r -d 1 -i -a && Rscript scripts/analyse.R -r -a

Rscript scripts/generate_local_ab.r
