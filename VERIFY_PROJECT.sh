#!/usr/bin/env bash
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$project/validation-data"
evidence="$project/validation-data"
source "$project/linux_health.sh"
pass() { printf 'PASS %s\n' "$1"; }
bash -n "$project/linux_health.sh"
pass 'Bash syntax check'
bash "$project/linux_health.sh" --interval 1 --samples 1 --cpu-threshold 0 --data-dir "$evidence/demo-data" > "$evidence/demo-run.txt"
[[ $(awk 'END {print NR-1}' "$evidence/demo-data/metrics.csv") == 1 ]]
pass 'One real Linux sample written to CSV'
grep -q 'CURRENT WARNING: CPU' "$evidence/demo-data/alerts.log"
pass 'Zero-percent threshold logs a real reading'
grep -q 'ALERT DEMONSTRATION' "$evidence/demo-data/dashboard.html"
pass 'Dashboard explains the controlled alert demonstration'
! grep -q '{{' "$evidence/demo-data/dashboard.html"
pass 'All dashboard template fields replaced'
fixture=$(mktemp)
trap 'rm -f "$fixture"' EXIT
printf '1000,10,40,50\n' > "$fixture"
[[ $(forecast "$fixture" 2 80 CPU) == *'collecting history'* ]]
pass 'Insufficient history keeps the prediction unavailable'
awk 'BEGIN {for(i=0;i<20;i++) print 1000+5*i "," 10+i ",40,50"}' > "$fixture"
out=$(forecast "$fixture" 2 35 CPU)
[[ $out == *'41.00%'* && $out == *'PREDICTED WARNING'* ]]
pass 'Known rising test series predicts 41.00 percent and warns'
awk 'BEGIN {for(i=0;i<20;i++) print 1000+5*i ",40,40,50"}' > "$fixture"
out=$(forecast "$fixture" 2 80 CPU)
[[ $out == *'40.00%'* && $out == *'R2 0.00'* && $out != *'WARNING'* ]]
pass 'Flat test series remains 40.00 percent without a warning'
awk 'BEGIN {for(i=0;i<20;i++) print 1000+5*i "," 5*i ",40,50"}' > "$fixture"
[[ $(forecast "$fixture" 2 99 CPU) == *'100.00%'* ]]
pass 'Prediction is bounded at 100 percent'
awk -v cpu_limit=35 -v mem_limit=85 -v disk_limit=90 -v template="$project/dashboard.template.html" -f "$project/dashboard.awk" <(awk 'BEGIN {for(i=0;i<20;i++) print 1000+5*i "," 10+i ",40,50"}') > "$evidence/fixture-dashboard.html"
grep -q 'CPU may reach its threshold' "$evidence/fixture-dashboard.html"
pass 'Dashboard renderer recognizes the known predictive warning'
printf '\n10 checks passed.\nKnown input series above are test fixtures, not live measurements.\n'
