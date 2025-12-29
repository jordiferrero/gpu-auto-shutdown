#!/bin/bash
#
# GPU Auto-Shutdown Monitor
# Shuts down cloud instance when GPU becomes idle after being busy.
#

# =============================================================================
# CONFIGURATION (Override via environment variables)
# =============================================================================

CHECK_INTERVAL="${CHECK_INTERVAL:-60}"           # Seconds between checks
BUFFER_TIME="${BUFFER_TIME:-20}"                 # Minutes before shutdown
HIGH_USAGE_THRESHOLD="${HIGH_USAGE_THRESHOLD:-50}"  # % considered "high"
LOW_USAGE_THRESHOLD="${LOW_USAGE_THRESHOLD:-5}"     # % considered "low"
MIN_HIGH_DURATION="${MIN_HIGH_DURATION:-5}"      # Minutes GPU must be high first
LOG_FILE="${LOG_FILE:-/var/log/gpu-monitor.log}"

# =============================================================================
# STATE
# =============================================================================

high_usage_count=0
low_usage_count=0
was_high=false

# =============================================================================
# FUNCTIONS
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_gpu_usage() {
    nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' '
}

do_shutdown() {
    log "=== INITIATING SHUTDOWN ==="
    # Try shutdown, fall back to poweroff
    if command -v shutdown &>/dev/null; then
        shutdown -h now "GPU idle - auto shutdown"
    else
        poweroff
    fi
}

# =============================================================================
# MAIN
# =============================================================================

# Calculate check counts from time settings
high_checks_needed=$(( (MIN_HIGH_DURATION * 60) / CHECK_INTERVAL ))
low_checks_needed=$(( (BUFFER_TIME * 60) / CHECK_INTERVAL ))
[[ $high_checks_needed -lt 1 ]] && high_checks_needed=1
[[ $low_checks_needed -lt 1 ]] && low_checks_needed=1

log "GPU Monitor started"
log "Config: check=${CHECK_INTERVAL}s, buffer=${BUFFER_TIME}m, high>${HIGH_USAGE_THRESHOLD}%, low<${LOW_USAGE_THRESHOLD}%"

# Check nvidia-smi exists
if ! command -v nvidia-smi &>/dev/null; then
    log "ERROR: nvidia-smi not found"
    exit 1
fi

while true; do
    usage=$(get_gpu_usage)
    
    if [[ ! "$usage" =~ ^[0-9]+$ ]]; then
        log "WARN: Could not read GPU usage"
        sleep "$CHECK_INTERVAL"
        continue
    fi

    # High usage
    if [[ $usage -ge $HIGH_USAGE_THRESHOLD ]]; then
        ((high_usage_count++)) || true
        low_usage_count=0
        
        if [[ $high_usage_count -ge $high_checks_needed ]] && [[ "$was_high" != "true" ]]; then
            log "GPU now in HIGH state (${usage}%)"
            was_high=true
        fi

    # Low usage
    elif [[ $usage -le $LOW_USAGE_THRESHOLD ]]; then
        if [[ "$was_high" == "true" ]]; then
            ((low_usage_count++)) || true
            remaining=$(( low_checks_needed - low_usage_count ))
            log "GPU LOW (${usage}%) - shutdown in ~$((remaining * CHECK_INTERVAL / 60))m"
            
            if [[ $low_usage_count -ge $low_checks_needed ]]; then
                do_shutdown
                exit 0
            fi
        fi

    # Between thresholds - reset low counter
    else
        if [[ $low_usage_count -gt 0 ]]; then
            log "GPU usage increased (${usage}%) - reset countdown"
        fi
        low_usage_count=0
    fi

    sleep "$CHECK_INTERVAL"
done
