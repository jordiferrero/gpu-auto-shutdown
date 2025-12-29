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
CHECK_CLOUD_INSTANCE="${CHECK_CLOUD_INSTANCE:-true}"  # Check if running on cloud instance before shutdown

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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

get_gpu_usage() {
    # Get usage for all GPUs and calculate average
    local usages
    usages=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | tr -d ' ')
    
    if [[ -z "$usages" ]]; then
        echo ""
        return
    fi
    
    # Calculate average across all GPUs
    local sum=0
    local count=0
    while IFS= read -r usage; do
        if [[ "$usage" =~ ^[0-9]+$ ]]; then
            sum=$((sum + usage))
            ((count++))
        fi
    done <<< "$usages"
    
    if [[ $count -eq 0 ]]; then
        echo ""
        return
    fi
    
    echo $((sum / count))
}

is_cloud_instance() {
    # Check cloud metadata services (most reliable method)
    # AWS EC2
    if curl -s --max-time 1 --connect-timeout 1 http://169.254.169.254/latest/meta-data/instance-id &>/dev/null; then
        return 0
    fi
    
    # GCP
    if curl -s --max-time 1 --connect-timeout 1 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/id &>/dev/null; then
        return 0
    fi
    
    # Azure
    if curl -s --max-time 1 --connect-timeout 1 -H "Metadata: true" http://169.254.169.254/metadata/instance?api-version=2021-02-01 &>/dev/null; then
        return 0
    fi
    
    # Fallback: check system indicators
    if [[ -f /sys/class/dmi/id/product_name ]]; then
        local product
        product=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
        if [[ "$product" =~ (amazon|google|microsoft|openstack) ]]; then
            return 0
        fi
    fi
    
    # Check for hypervisor UUID (AWS/Xen)
    if [[ -f /sys/hypervisor/uuid ]]; then
        return 0
    fi
    
    return 1
}

do_shutdown() {
    # Check if we should verify cloud instance (if enabled)
    if [[ "$CHECK_CLOUD_INSTANCE" == "true" ]]; then
        if ! is_cloud_instance; then
            log "WARN: Not detected as cloud instance - skipping shutdown for safety"
            log "Set CHECK_CLOUD_INSTANCE=false to disable this check"
            return 1
        fi
    fi
    
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

# Validate thresholds
if [[ $LOW_USAGE_THRESHOLD -ge $HIGH_USAGE_THRESHOLD ]]; then
    echo "ERROR: LOW_USAGE_THRESHOLD ($LOW_USAGE_THRESHOLD) must be less than HIGH_USAGE_THRESHOLD ($HIGH_USAGE_THRESHOLD)" >&2
    exit 1
fi

# Calculate check counts from time settings
high_checks_needed=$(( (MIN_HIGH_DURATION * 60) / CHECK_INTERVAL ))
low_checks_needed=$(( (BUFFER_TIME * 60) / CHECK_INTERVAL ))
[[ $high_checks_needed -lt 1 ]] && high_checks_needed=1
[[ $low_checks_needed -lt 1 ]] && low_checks_needed=1

log "GPU Monitor started"
log "Config: check=${CHECK_INTERVAL}s, buffer=${BUFFER_TIME}m, high>${HIGH_USAGE_THRESHOLD}%, low<${LOW_USAGE_THRESHOLD}%, cloud_check=${CHECK_CLOUD_INSTANCE}"

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
        ((high_usage_count++))
        low_usage_count=0
        
        if [[ $high_usage_count -ge $high_checks_needed ]] && [[ "$was_high" != "true" ]]; then
            log "GPU now in HIGH state (${usage}%)"
            was_high=true
        fi

    # Low usage
    elif [[ $usage -le $LOW_USAGE_THRESHOLD ]]; then
        if [[ "$was_high" == "true" ]]; then
            ((low_usage_count++))
            remaining=$(( low_checks_needed - low_usage_count ))
            log "GPU LOW (${usage}%) - shutdown in ~$((remaining * CHECK_INTERVAL / 60))m"
            
            if [[ $low_usage_count -ge $low_checks_needed ]]; then
                if do_shutdown; then
                    # Shutdown command was successful (system will halt)
                    exit 0
                else
                    # Shutdown failed (e.g., not a cloud instance) - reset and continue monitoring
                    log "Shutdown aborted - resetting countdown and continuing to monitor"
                    low_usage_count=0
                fi
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
