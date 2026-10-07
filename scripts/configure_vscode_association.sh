#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# configure_vscode_association.sh
# Adds the Wave Viewer editor association to VS Code settings.
#
# 2026 August
# Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

# Adds a workbench.editorAssociations entry to the user's VS Code settings.json
set -euo pipefail
SETTINGS="$HOME/.config/Code/User/settings.json"
mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
  echo "{}" > "$SETTINGS"
fi
# Use jq if available for robust JSON edit, otherwise do a dumb merge
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq '. as $orig | .["workbench.editorAssociations"] |= (if . == null then [] else . end) | .["workbench.editorAssociations"] += [{"viewType":"rohdWaveViewer.vcd","filenamePattern":"*.vcd"}]' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  echo "Updated $SETTINGS with rohdWaveViewer.vcd association"
else
  # naive append/replace: will not prevent duplicates cleanly
  python3 - "$SETTINGS" <<'PY'
import json,sys
p=sys.argv[1]
with open(p,'r+') as f:
    data=json.load(f)
    assoc=data.get('workbench.editorAssociations',[])
    entry={'viewType':'rohdWaveViewer.vcd','filenamePattern':'*.vcd'}
    if entry not in assoc:
        assoc.append(entry)
        data['workbench.editorAssociations']=assoc
        f.seek(0); f.truncate(); json.dump(data,f,indent=2)
        print('Updated',p)
    else:
        print('Association already present')
PY
fi

echo "Please reload VS Code (Developer: Reload Window) to apply settings."
