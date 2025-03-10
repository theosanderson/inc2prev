#!/bin/sh

git pull -Xours
git add data/*.csv
git add outputs/*.csv
git diff-index --quiet HEAD || git commit -m"Updated estimates $(date)"
git push -v

git branch -D gh-pages
git checkout --orphan gh-pages
git rm -rf .
git add docs/*.html
git commit -m "Update report"
git push --force origin gh-pages
git checkout master

