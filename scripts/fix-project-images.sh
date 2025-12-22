#!/usr/bin/env bash
set -euo pipefail

# Run from repo root: bash scripts/fix-project-images.sh
PROJECTS_DIR="content/projects"

# 1) Move any stray images from static/projects/** back to content/projects/**
if [ -d "static/projects" ]; then
  while IFS= read -r -d '' img; do
    rel="${img#static/projects/}"                # e.g., folder/featured.png
    folder="${rel%%/*}"                          # e.g., folder
    mkdir -p "$PROJECTS_DIR/$folder"
    echo "Moving $img -> $PROJECTS_DIR/$folder/"
    mv -f "$img" "$PROJECTS_DIR/$folder/"
  done < <(find static/projects -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0)
fi

# 2) For each project folder, ensure we have a "featured" image name and update index.md
while IFS= read -r -d '' dir; do
  # pick a featured image (prefer webp/png/jpg order)
  feat=""
  for ext in webp png jpg jpeg; do
    cand="$(ls "$dir"/featured.* 2>/dev/null | head -n1 || true)"
    [ -n "$cand" ] && feat="$cand" && break
    cand2="$(ls "$dir"/*."$ext" 2>/dev/null | head -n1 || true)"
    if [ -z "$feat" ] && [ -n "$cand2" ]; then
      mv -f "$cand2" "$dir/featured.$ext"
      feat="$dir/featured.$ext"
      break
    fi
  done
  [ -z "$feat" ] && { echo "No image found in $dir — skipping"; continue; }

  feat_name="$(basename "$feat")"

  md="$dir/index.md"
  if [ ! -f "$md" ]; then
    echo "Missing $md — creating minimal index.md"
    cat > "$md" <<EOF
---
title: "$(basename "$dir")"
date: $(date +%Y-%m-%d)
featureimage: "$feat_name"
imagePosition: "center"
draft: false
---
EOF
  else
    # If featureimage exists, replace its value; else insert before closing '---'
    if grep -q "^featureimage:" "$md"; then
      sed -i.bak "s#^featureimage:.*#featureimage: \"$feat_name\"#g" "$md"
    else
      # Insert after title/date lines inside the front matter
      awk -v kv="featureimage: \"$feat_name\"" '
        BEGIN{infm=0;added=0}
        /^---\s*$/{ if(infm==0){infm=1} else { if(!added){print kv; added=1}; infm=0} }
        {print}
        END{ if(infm==1 && !added){print kv; print "---"} }
      ' "$md" > "$md.tmp" && mv "$md.tmp" "$md"
    fi

    # Ensure imagePosition present (helps focus if you keep cover)
    if grep -q "^imagePosition:" "$md"; then
      sed -i.bak 's#^imagePosition:.*#imagePosition: "center"#g' "$md"
    else
      awk -v kv='imagePosition: "center"' '
        BEGIN{infm=0;added=0}
        /^---\s*$/{ if(infm==0){infm=1} else { if(!added){print kv; added=1}; infm=0} }
        {print}
        END{ if(infm==1 && !added){print kv; print "---"} }
      ' "$md" > "$md.tmp" && mv "$md.tmp" "$md"
    fi
  fi
  rm -f "$md.bak"
done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

echo "Done. Now run: hugo server -D"

