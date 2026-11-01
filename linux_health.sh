#!/usr/bin/env bash
# Linux System Health & Predictive Monitoring -- Bash and Linux utilities only.
# Run: bash linux_health.sh
# Help: bash linux_health.sh --help
# No Python, pip packages, web server or root permissions required.
# Browser dashboard: open health-data/dashboard.html while this runs.

usage() {
    cat <<'HELP'
Linux System Health & Predictive Monitoring
Usage: bash linux_health.sh [options]
  --interval N          Seconds between samples, 1-60 (default 5)
  --samples N           Stop after N samples; 0 means continuous (default 0)
  --cpu-threshold N     CPU alert percentage, 0-100 (default 80)
  --memory-threshold N  Memory alert percentage, 0-100 (default 85)
  --disk-threshold N    Root filesystem alert percentage, 0-100 (default 90)
  --data-dir PATH       Output directory (default ./health-data)
  --help                Show these instructions

Browser dashboard: open health-data/dashboard.html in your Windows browser.
The page reloads every 5 seconds. No web server or internet connection is needed.

Display: live CPU, memory, root filesystem and network rates.
Prediction: least-squares straight-line trend for CPU/memory/disk, 60 seconds
ahead, using the latest 20 samples from THIS run. Requires 20 samples spanning
at least 60 seconds. This is a trend estimate, not hardware failure prediction.
Predicted warnings require a rising trend with R-squared >= 0.5.
Current readings always trigger when they meet their threshold.
Network totals exclude loopback and combine all other interfaces.

Normal:     bash linux_health.sh
Alert demo: bash linux_health.sh --cpu-threshold 0 --data-dir demo-data
The demo deliberately lowers the threshold; it does not overload your computer.
View data:  tail -n 5 health-data/metrics.csv
View log:   tail -n 10 health-data/alerts.log
Stop:       Ctrl+C
On WSL, these readings describe the Linux environment, not all Windows activity.
HELP
}

# Aggregate CPU ticks: the first eight fields exclude guest ticks (already counted).
cpu_ticks() {
    awk '/^cpu / {s=0; for(i=2;i<=9;i++) s+=$i; print s, $5+$6; exit}' /proc/stat
}

network_bytes() {
    awk -F '[: ]+' 'NR>2 {if($2!="lo"){rx+=$3; tx+=$11}}
        END {printf "%.0f %.0f\n",rx,tx}' /proc/net/dev
}

# Input CSV is epoch,cpu_percent,memory_percent,disk_percent (no header).
# Keep the math in awk so the project uses standard Linux commands.
forecast() {
    awk -F, -v c="$2" -v limit="$3" -v label="$4" '
    {n++; if(n==1) start=$1; x[n]=$1-start; y[n]=$c; last=$c;
     sx+=x[n]; sy+=y[n]; sxx+=x[n]*x[n]; sxy+=x[n]*y[n]; syy+=y[n]*y[n]}
    END {
        if(n<20 || x[n]<60) {
            printf "%s: collecting history (%d/20 samples; %.0f/60 seconds)\n",label,n,x[n];
            exit
        }
        dx=n*sxx-sx*sx; dy=n*syy-sy*sy;
        if(dx<=0){print label ": waiting for advancing timestamps"; exit}
        slope=(n*sxy-sx*sy)/dx;
        intercept=(sy-slope*sx)/n;
        predicted=intercept+slope*(x[n]+60);
        if(predicted<0)predicted=0; if(predicted>100)predicted=100;
        r2=(dy>0 ? (n*sxy-sx*sy)^2/(dx*dy) : 0);
        if(r2>1)r2=1;
        status="trend estimate";
        if(last<limit && slope>0 && r2>=0.5 && predicted>=limit)
            status="PREDICTED WARNING: may reach threshold";
        printf "%s: next 60s %.2f%% | slope %+.2f points/min | R2 %.2f | %s\n",
            label,predicted,slope*60,r2,status;
    }' "$1"
}

main() (
    set -euo pipefail
    export LC_ALL=C
    interval=5; max_samples=0; cpu_limit=80; mem_limit=85; disk_limit=90
    data_dir=./health-data
    script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    [[ -r "$script_dir/dashboard.awk" ]] || { echo 'Keep dashboard.awk next to linux_health.sh.' >&2; exit 1; }
    [[ -r "$script_dir/dashboard.template.html" ]] || { echo 'Keep dashboard.template.html next to linux_health.sh.' >&2; exit 1; }
    while (($#)); do
        case "$1" in
            --help|-h) usage; exit 0 ;;
            --interval|--samples|--cpu-threshold|--memory-threshold|--disk-threshold|--data-dir)
                (($#>=2)) || { printf 'Missing value for %s\n' "$1" >&2; exit 2; }
                case "$1" in
                    --interval) interval=$2 ;; --samples) max_samples=$2 ;;
                    --cpu-threshold) cpu_limit=$2 ;; --memory-threshold) mem_limit=$2 ;;
                    --disk-threshold) disk_limit=$2 ;; --data-dir) data_dir=$2 ;;
                esac
                shift 2 ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
        esac
    done
    for value in "$interval" "$max_samples" "$cpu_limit" "$mem_limit" "$disk_limit"; do
        [[ $value =~ ^(0|[1-9][0-9]{0,6})$ ]] || { echo 'Use nonnegative whole numbers (no leading zeros).' >&2; exit 2; }
    done
    ((interval>=1 && interval<=60 && cpu_limit<=100 && mem_limit<=100 && disk_limit<=100)) || {
        echo 'Interval must be 1-60; thresholds must be 0-100.' >&2; exit 2;
    }
    [[ -r /proc/stat && -r /proc/meminfo && -r /proc/net/dev ]] || {
        echo 'Run this in Ubuntu/Linux: required /proc files are unavailable.' >&2; exit 1;
    }
    for command in awk df date tail mkdir mktemp rm sleep mv; do
        command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
    done
    mkdir -p -- "$data_dir"
    csv="$data_dir/metrics.csv"; log="$data_dir/alerts.log"
    [[ -s $csv ]] || printf 'epoch,cpu_percent,memory_percent,disk_percent\n' > "$csv"
    window=$(mktemp)
    html_tmp=$(mktemp "$data_dir/.dashboard.XXXXXX")
    trap 'rm -f -- "$window" "$html_tmp"' EXIT
    trap 'printf "\nMonitor stopped. Readings saved in %s\n" "$data_dir"; exit 0' INT TERM
    read -r prev_total prev_idle < <(cpu_ticks)
    read -r prev_rx prev_tx < <(network_bytes)
    prev_time=$(date +%s)
    count=0
    while :; do
        sleep "$interval"
        now=$(date +%s)
        read -r total idle < <(cpu_ticks)
        read -r rx tx < <(network_bytes)
        cpu=$(awk -v dt="$((total-prev_total))" -v di="$((idle-prev_idle))" \
            'BEGIN {v=(dt>0?100*(dt-di)/dt:0); if(v<0)v=0; if(v>100)v=100; printf "%.2f",v}')
        mem=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2}
            END {if(t<=0)exit 1; printf "%.2f",100*(t-a)/t}' /proc/meminfo)
        disk=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        [[ $disk =~ ^[0-9]+$ ]] || { echo 'Could not read root disk usage.' >&2; exit 1; }
        rates=$(awk -v dr="$((rx-prev_rx))" -v dt="$((tx-prev_tx))" -v sec="$((now-prev_time))" \
            'BEGIN {if(sec<=0 || dr<0 || dt<0) print "counter reset / clock changed";
             else printf "RX %.2f KiB/s | TX %.2f KiB/s",dr/sec/1024,dt/sec/1024}')
        if ((now<=prev_time || now-prev_time>interval+30)); then
            : > "$window"  # Restart trend history after a clock jump or long suspension.
        fi
        printf '%s,%s,%s,%s\n' "$now" "$cpu" "$mem" "$disk" >> "$csv"
        printf '%s,%s,%s,%s\n' "$now" "$cpu" "$mem" "$disk" >> "$window"
        history=$(tail -n 20 "$window")
        printf '%s\n' "$history" > "$window"
        count=$((count+1))
        [[ ! -t 1 ]] || printf '\033[2J\033[H'
        printf 'LINUX SYSTEM HEALTH & PREDICTIVE MONITORING\n%s | Sample %s\n' "$(date -Is)" "$count"
        printf 'CPU %s%% | Memory %s%% | Root disk %s%%\n%s\n' "$cpu" "$mem" "$disk" "$rates"
        current=$(awk -v c="$cpu" -v m="$mem" -v d="$disk" -v cl="$cpu_limit" -v ml="$mem_limit" -v dl="$disk_limit" \
            'BEGIN {if(c>=cl)printf "CURRENT WARNING: CPU %.2f%% >= %s%%\n",c,cl;
                    if(m>=ml)printf "CURRENT WARNING: Memory %.2f%% >= %s%%\n",m,ml;
                    if(d>=dl)printf "CURRENT WARNING: Disk %.2f%% >= %s%%\n",d,dl}')
        predictions=$(forecast "$window" 2 "$cpu_limit" CPU
                      forecast "$window" 3 "$mem_limit" Memory
                      forecast "$window" 4 "$disk_limit" Disk)
        awk -v cpu_limit="$cpu_limit" -v mem_limit="$mem_limit" -v disk_limit="$disk_limit" \
            -v interval="$interval" -v count="$count" -v generated="$now" \
            -v template="$script_dir/dashboard.template.html" \
            -v rate_text="$rates" -v readable_time="$(date -Is)" \
            -f "$script_dir/dashboard.awk" "$window" > "$html_tmp"
        mv -f -- "$html_tmp" "$data_dir/dashboard.html"
        printf '\n%s\n' "$predictions"
        if [[ -n $current ]]; then printf '\n%s\n' "$current"; else printf '\nCurrent readings: below thresholds\n'; fi
        warnings=$(printf '%s\n%s\n' "$current" "$predictions" | awk '/WARNING/')
        if [[ -n $warnings ]]; then
            while IFS= read -r warning; do printf '%s %s\n' "$(date -Is)" "$warning" >> "$log"; done <<< "$warnings"
        fi
        printf '\nData: %s | Alerts: %s (created when a warning occurs)\nCtrl+C to stop.\n' "$csv" "$log"
        printf 'Browser dashboard: %s/dashboard.html (reloads automatically)\n' "$data_dir"
        prev_total=$total; prev_idle=$idle; prev_rx=$rx; prev_tx=$tx; prev_time=$now
        if ((max_samples>0 && count>=max_samples)); then break; fi
    done
)

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
