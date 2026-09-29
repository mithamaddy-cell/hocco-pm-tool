#!/bin/sh
# Cloudflare Pages build: publish ONLY the app's own files (into dist/).
# Database scripts, CLAUDE.md and other internal files stay out of the live site.
set -e
rm -rf dist && mkdir dist
cp index.html hocco-*.html hocco-*.js hocco-tokens.css _headers robots.txt dist/
echo "Published files:"; ls dist
