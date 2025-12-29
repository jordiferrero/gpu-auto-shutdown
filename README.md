# GPU Auto-Shutdown

Automatically shuts down cloud GPU instances when they become idle. Saves money.

## Problem

For ML R&D, one often starts a GPU instance (AWS EC2, GCP, Azure) to train a model or run inference. The job may finish at 3 AM, but the instance keeps running until you remember to check it. You get charged for hours of unused expensive GPU time.

## Solution

This service monitors GPU usage. When usage drops from high to low and stays low for a buffer period, it shuts down the instance.

## Install

```bash
git clone https://github.com/jordiferrero/gpu-auto-shutdown.git
cd gpu-auto-shutdown
sudo ./install.sh
```

## Uninstall

```bash
sudo ./install.sh --uninstall
```

## Configure

Edit the service file:

```bash
sudo nano /etc/systemd/system/gpu-monitor.service
```

| Variable | Default | Description |
|----------|---------|-------------|
| `CHECK_INTERVAL` | 60 | Seconds between GPU checks |
| `BUFFER_TIME` | 20 | Minutes to wait before shutdown |
| `HIGH_USAGE_THRESHOLD` | 50 | GPU % considered "high" |
| `LOW_USAGE_THRESHOLD` | 5 | GPU % considered "low" |
| `MIN_HIGH_DURATION` | 5 | Minutes GPU must be high first |
| `CHECK_CLOUD_INSTANCE` | true | Verify running on cloud instance before shutdown (prevents accidental local shutdown) |

After editing:

```bash
sudo systemctl daemon-reload
sudo systemctl restart gpu-monitor
```

## Commands

```bash
journalctl -u gpu-monitor -f     # View logs
systemctl status gpu-monitor     # Status
sudo systemctl stop gpu-monitor  # Stop
sudo systemctl start gpu-monitor # Start
```

## Requirements

- Linux with systemd
- NVIDIA GPU(s) with `nvidia-smi` installed
- Root/sudo access for installation

## How It Works

1. Monitors GPU usage every 60 seconds (averages across all GPUs if multiple are present)
2. Waits for GPU to be "high" (>50%) for at least 5 minutes (your job is running)
3. When GPU drops to "low" (<5%), starts countdown
4. If GPU stays low for 20 minutes, shuts down instance
5. If GPU usage increases, countdown resets

**Multi-GPU Support**: If you have multiple GPUs, the monitor averages the usage across all GPUs. The shutdown logic applies to the average usage.

The instance shutdown stops billing on all cloud providers (AWS, GCP, Azure, etc).

## License

MIT
