LINUX COMMAND PROJECT -- TECHNICAL NOTES

Begin with START_HERE.txt for Windows and WSL launch instructions.

IMPLEMENTATION
linux_health.sh              Bash collector, terminal output and alert logging
dashboard.awk                Arithmetic, prediction and dashboard rendering
dashboard.template.html      HTML/CSS frontend and SVG chart container
VERIFY_PROJECT.sh            Ten validation checks

The application runtime uses Bash and ordinary Linux utilities: awk, df, date,
tail, sleep, mkdir, mktemp and mv. No Python, Node.js, JavaScript, external CDN,
database service or HTTP server is required.

LIVE FILES
health-data/metrics.csv       epoch,cpu_percent,memory_percent,disk_percent
health-data/dashboard.html    Automatically regenerated frontend
health-data/alerts.log        Created on the first warning

CPU is calculated from changes in /proc/stat counters. Memory uses MemTotal and
MemAvailable from /proc/meminfo. Root disk usage comes from df -P /, at whole-
percent resolution. Network rates combine non-loopback interfaces from
/proc/net/dev; they are displayed but are not stored in the CSV columns.

PREDICTIONS
awk fits a straight line to the latest 20 observations from the current run.
Prediction requires those readings to span at least 60 seconds. The default
five-second interval produces the first estimate after about 100 seconds.
Use the default five seconds for the presentation. Shorter intervals of 1-3
seconds may keep the 20-reading window below the required 60-second span.

The horizon is 60 seconds and estimates are limited to 0-100%. Predicted warnings
require a positive slope, R-squared >= 0.5, current usage below the threshold,
and an estimate reaching that threshold. R-squared measures past fit, not future
accuracy. A clock reversal or long suspension resets the recent trend window.

WARNINGS
Default limits: CPU 80%, memory 85%, disk 90%.
A current value at or above its limit produces a warning. Warnings can repeat
on each qualifying cycle. Duplicate suppression and cleared events are not
implemented. The controlled 0% threshold demonstration must be labeled as a test.

USEFUL COMMANDS
bash linux_health.sh --help
cat /proc/stat
cat /proc/meminfo
free -m
df -P /
cat /proc/net/dev
tail -n 5 health-data/metrics.csv
tail -n 10 health-data/alerts.log

LIMITS
Only one collector should write to an output directory at a time. CSV/log files
continue to grow; no automatic retention or rotation is applied. Forecasts start
with fresh history each run even if an old CSV exists. A stopped collector leaves
the last HTML snapshot visible; page refresh alone does not collect new readings.
Remote monitoring, email notifications and scheduled services are future work.
