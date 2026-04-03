# Geoblock
Geographic IP blocking for Linux — from the command line.
Geoblock is a free, donation-based firewall utility for Linux. Block incoming traffic by country using iptables and xt_geoip, with persistent rules that survive reboots, automatic boot-time restore, and twice-daily GeoIP database updates.

# Features
Block or unblock traffic by ISO country code or full country name
Supports 100+ countries with automatic code normalization
Rules are saved on every action and auto-restored on boot via systemd
GeoIP database updates run twice daily (6 AM & 6 PM) via systemd timer or cron
Permanent history log with automatic rotation (10 MB threshold, 5 archives)
Works with both systemd and traditional cron
Minimal dependencies: iptables, xtables-addons, libtext-csv-perl, wget

# Installation
Download the installer and run it as root:
```bash
chmod +x geoblock-1.5-installer.sh && sudo ./geoblock-1.5-installer.sh
```

# Usage
geoblock block CN          # Block China
geoblock block Russia      # Block by full name
geoblock unblock CN        # Unblock China
geoblock list              # List blocked countries
geoblock status            # Show firewall status
geoblock --help            # Full usage

# Dependencies
Linux with iptables
xtables-addons (xt_geoip kernel module)
libtext-csv-perl
wget
