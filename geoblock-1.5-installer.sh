#!/bin/bash
#
# geoblock-1.5-installer.sh
# Installer for Castle Walls Geoblock - Geographic IP blocking utility
# Author: CYBERACQ
# Website: https://cyberacq.com/geoblock
# GitHub: https://github.com/cyberacq/geoblock
# Version: 1.5
#

set -e

VERSION="1.5"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/cyberacq/geoblock"
GEOIP_DIR="/usr/share/xt_geoip"
SYSTEMD_DIR="/etc/systemd/system"
CRON_DIR="/etc/cron.d"
MAN_DIR="/usr/local/share/man/man8"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This installer must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# Detect Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
    
    print_info "Detected distribution: $DISTRO"
}

# Get package manager
get_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf check-update || true"
        PKG_INSTALL="dnf install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum check-update || true"
        PKG_INSTALL="yum install -y"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_UPDATE="zypper refresh"
        PKG_INSTALL="zypper install -y"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_UPDATE="pacman -Sy"
        PKG_INSTALL="pacman -S --noconfirm"
    else
        print_error "Could not detect package manager"
        exit 1
    fi
    
    print_info "Using package manager: $PKG_MANAGER"
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Check for iptables
    if ! command -v iptables &> /dev/null; then
        missing_deps+=("iptables")
    fi
    
    # Check for perl and CSV module
    if ! perl -MText::CSV -e 1 &> /dev/null; then
        case $PKG_MANAGER in
            apt-get)
                missing_deps+=("libtext-csv-perl")
                ;;
            dnf|yum)
                missing_deps+=("perl-Text-CSV")
                ;;
            zypper)
                missing_deps+=("perl-Text-CSV")
                ;;
            pacman)
                missing_deps+=("perl-text-csv")
                ;;
        esac
    fi
    
    # Check for xtables-addons
    if ! [ -f /usr/libexec/xtables-addons/xt_geoip_build ] && ! [ -f /usr/lib/xtables-addons/xt_geoip_build ]; then
        case $PKG_MANAGER in
            apt-get)
                missing_deps+=("xtables-addons-common")
                ;;
            dnf|yum)
                missing_deps+=("xtables-addons")
                ;;
            zypper)
                missing_deps+=("xtables-addons")
                ;;
            pacman)
                missing_deps+=("xtables-addons")
                ;;
        esac
    fi
    
    # Check for wget
    if ! command -v wget &> /dev/null; then
        missing_deps+=("wget")
    fi
    
    # Check for gunzip
    if ! command -v gunzip &> /dev/null; then
        missing_deps+=("gzip")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        echo -n "Would you like to install them now? (y/n): "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            install_dependencies "${missing_deps[@]}"
        else
            print_error "Cannot proceed without dependencies"
            exit 1
        fi
    else
        print_success "All dependencies are satisfied"
    fi
}

# Install dependencies
install_dependencies() {
    local deps=("$@")
    
    print_info "Updating package lists..."
    eval $PKG_UPDATE
    
    print_info "Installing dependencies: ${deps[*]}"
    eval $PKG_INSTALL "${deps[@]}"
    
    print_success "Dependencies installed successfully"
}

# Create geoblock main script
create_geoblock_script() {
    print_info "Creating geoblock script..."
    
    cat > "$INSTALL_DIR/geoblock" << 'GEOBLOCK_EOF'
#!/bin/bash
#
# Castle Walls Geoblock - Geographic IP blocking utility
# Author: CYBERACQ
# Website: https://cyberacq.com/geoblock
# GitHub: https://github.com/cyberacq/geoblock
# Version: 1.5
#

VERSION="1.5"
CONFIG_DIR="$HOME/.config/cyberacq/geoblock"
GEOIP_DIR="/usr/share/xt_geoip"
CONFIG_FILE="$CONFIG_DIR/blocked_countries.conf"
LOG_FILE="/var/log/geoblock.log"
HISTORY_FILE="$CONFIG_DIR/history.log"
CHAIN_NAME="castlewalls-geoblock"
MAX_LOG_SIZE=10485760  # 10MB
MAX_LOG_FILES=5
RULES_FILE="$CONFIG_DIR/block.rules"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        echo "Please run: sudo geoblock $*"
        exit 1
    fi
}

# Log rotation
rotate_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi
    
    local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    
    if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
        # Rotate logs
        for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
            if [ -f "${LOG_FILE}.$i" ]; then
                mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))"
            fi
        done
        mv "$LOG_FILE" "${LOG_FILE}.1"
        touch "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
}

# Log action
log_action() {
    local action="$1"
    local country_code="$2"
    local country_name="$3"
    local reason="$4"
    local iptables_cmd="$5"
    local error_msg="$6"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user="${SUDO_USER:-root}"
    
    rotate_logs
    
    # Log to main log file with full iptables syntax
    if [ -n "$error_msg" ]; then
        echo "[$timestamp] USER=$user ACTION=$action COUNTRY=$country_name($country_code) REASON=$reason IPTABLES=[$iptables_cmd] ERROR=$error_msg" >> "$LOG_FILE"
    else
        echo "[$timestamp] USER=$user ACTION=$action COUNTRY=$country_name($country_code) REASON=$reason IPTABLES=[$iptables_cmd]" >> "$LOG_FILE"
    fi
    
    # Log to history file (simple timestamp tracking only)
    if [ -z "$error_msg" ]; then
        echo "[$timestamp] $action $country_name($country_code)" >> "$HISTORY_FILE"
    fi
}

# Initialize custom chain
init_chain() {
    # Check if chain exists
    if ! iptables -L "$CHAIN_NAME" -n &>/dev/null; then
        print_info "Creating iptables chain: $CHAIN_NAME"
        iptables -N "$CHAIN_NAME"
        # Jump to our custom chain from INPUT
        iptables -I INPUT -j "$CHAIN_NAME"
        print_success "Chain $CHAIN_NAME created"
    fi
}

# Save current rules to file
save_rules() {
    check_root
    
    # Save the entire iptables ruleset
    iptables-save > "$RULES_FILE"
    
    if [ $? -eq 0 ]; then
        chmod 600 "$RULES_FILE"
        return 0
    else
        return 1
    fi
}

# Restore rules from file
restore_rules() {
    check_root
    
    if [ ! -f "$RULES_FILE" ]; then
        return 1
    fi
    
    # Restore the iptables ruleset
    iptables-restore < "$RULES_FILE"
    
    return $?
}

# Get full country name from code
get_country_name() {
    local code="$1"
    case "$code" in
        RU) echo "Russia" ;;
        CN) echo "China" ;;
        IR) echo "Iran" ;;
        KP) echo "North Korea" ;;
        US) echo "United States" ;;
        GB) echo "United Kingdom" ;;
        DE) echo "Germany" ;;
        FR) echo "France" ;;
        JP) echo "Japan" ;;
        CA) echo "Canada" ;;
        AU) echo "Australia" ;;
        IN) echo "India" ;;
        BR) echo "Brazil" ;;
        MX) echo "Mexico" ;;
        ES) echo "Spain" ;;
        IT) echo "Italy" ;;
        NL) echo "Netherlands" ;;
        PL) echo "Poland" ;;
        UA) echo "Ukraine" ;;
        TR) echo "Turkey" ;;
        KR) echo "South Korea" ;;
        SE) echo "Sweden" ;;
        NO) echo "Norway" ;;
        DK) echo "Denmark" ;;
        FI) echo "Finland" ;;
        BE) echo "Belgium" ;;
        AT) echo "Austria" ;;
        CH) echo "Switzerland" ;;
        PT) echo "Portugal" ;;
        GR) echo "Greece" ;;
        CZ) echo "Czech Republic" ;;
        RO) echo "Romania" ;;
        HU) echo "Hungary" ;;
        BG) echo "Bulgaria" ;;
        BY) echo "Belarus" ;;
        IE) echo "Ireland" ;;
        NZ) echo "New Zealand" ;;
        SG) echo "Singapore" ;;
        MY) echo "Malaysia" ;;
        TH) echo "Thailand" ;;
        VN) echo "Vietnam" ;;
        PH) echo "Philippines" ;;
        ID) echo "Indonesia" ;;
        PK) echo "Pakistan" ;;
        BD) echo "Bangladesh" ;;
        NG) echo "Nigeria" ;;
        EG) echo "Egypt" ;;
        ZA) echo "South Africa" ;;
        AR) echo "Argentina" ;;
        CL) echo "Chile" ;;
        CO) echo "Colombia" ;;
        PE) echo "Peru" ;;
        VE) echo "Venezuela" ;;
        IL) echo "Israel" ;;
        SA) echo "Saudi Arabia" ;;
        AE) echo "United Arab Emirates" ;;
        IQ) echo "Iraq" ;;
        SY) echo "Syria" ;;
        AF) echo "Afghanistan" ;;
        LB) echo "Lebanon" ;;
        JO) echo "Jordan" ;;
        KW) echo "Kuwait" ;;
        QA) echo "Qatar" ;;
        OM) echo "Oman" ;;
        BH) echo "Bahrain" ;;
        YE) echo "Yemen" ;;
        RS) echo "Serbia" ;;
        HR) echo "Croatia" ;;
        SI) echo "Slovenia" ;;
        SK) echo "Slovakia" ;;
        LT) echo "Lithuania" ;;
        LV) echo "Latvia" ;;
        EE) echo "Estonia" ;;
        AL) echo "Albania" ;;
        MK) echo "North Macedonia" ;;
        BA) echo "Bosnia and Herzegovina" ;;
        ME) echo "Montenegro" ;;
        KZ) echo "Kazakhstan" ;;
        UZ) echo "Uzbekistan" ;;
        AZ) echo "Azerbaijan" ;;
        GE) echo "Georgia" ;;
        AM) echo "Armenia" ;;
        MD) echo "Moldova" ;;
        *) echo "$code" ;;
    esac
}

# Convert country name/code to ISO code
normalize_country_code() {
    local input="$1"
    local code="${input^^}"  # Convert to uppercase
    
    # If already 2-letter code, return it
    if [ ${#code} -eq 2 ]; then
        echo "$code"
        return 0
    fi
    
    # Convert common country names to codes
    case "${input,,}" in
        russia|russian) echo "RU" ;;
        china|chinese) echo "CN" ;;
        iran|iranian) echo "IR" ;;
        "north korea"|northkorea|dprk) echo "KP" ;;
        "united states"|usa|america) echo "US" ;;
        "united kingdom"|uk|britain) echo "GB" ;;
        germany|german) echo "DE" ;;
        france|french) echo "FR" ;;
        japan|japanese) echo "JP" ;;
        canada|canadian) echo "CA" ;;
        australia|australian) echo "AU" ;;
        india|indian) echo "IN" ;;
        brazil|brazilian) echo "BR" ;;
        mexico|mexican) echo "MX" ;;
        spain|spanish) echo "ES" ;;
        italy|italian) echo "IT" ;;
        netherlands|dutch) echo "NL" ;;
        poland|polish) echo "PL" ;;
        ukraine|ukrainian) echo "UA" ;;
        turkey|turkish) echo "TR" ;;
        "south korea"|southkorea) echo "KR" ;;
        sweden|swedish) echo "SE" ;;
        norway|norwegian) echo "NO" ;;
        denmark|danish) echo "DK" ;;
        finland|finnish) echo "FI" ;;
        belgium|belgian) echo "BE" ;;
        austria|austrian) echo "AT" ;;
        switzerland|swiss) echo "CH" ;;
        portugal|portuguese) echo "PT" ;;
        greece|greek) echo "GR" ;;
        "czech republic"|czechia|czech) echo "CZ" ;;
        romania|romanian) echo "RO" ;;
        hungary|hungarian) echo "HU" ;;
        bulgaria|bulgarian) echo "BG" ;;
        belarus|belarusian) echo "BY" ;;
        ireland|irish) echo "IE" ;;
        "new zealand"|newzealand) echo "NZ" ;;
        singapore) echo "SG" ;;
        malaysia|malaysian) echo "MY" ;;
        thailand|thai) echo "TH" ;;
        vietnam|vietnamese) echo "VN" ;;
        philippines|filipino) echo "PH" ;;
        indonesia|indonesian) echo "ID" ;;
        pakistan|pakistani) echo "PK" ;;
        bangladesh|bangladeshi) echo "BD" ;;
        nigeria|nigerian) echo "NG" ;;
        egypt|egyptian) echo "EG" ;;
        "south africa"|southafrica) echo "ZA" ;;
        argentina|argentinian) echo "AR" ;;
        chile|chilean) echo "CL" ;;
        colombia|colombian) echo "CO" ;;
        peru|peruvian) echo "PE" ;;
        venezuela|venezuelan) echo "VE" ;;
        israel|israeli) echo "IL" ;;
        "saudi arabia"|saudiarabia|saudi) echo "SA" ;;
        "united arab emirates"|uae|emirates) echo "AE" ;;
        iraq|iraqi) echo "IQ" ;;
        syria|syrian) echo "SY" ;;
        afghanistan|afghan) echo "AF" ;;
        lebanon|lebanese) echo "LB" ;;
        jordan|jordanian) echo "JO" ;;
        kuwait|kuwaiti) echo "KW" ;;
        qatar|qatari) echo "QA" ;;
        oman|omani) echo "OM" ;;
        bahrain|bahraini) echo "BH" ;;
        yemen|yemeni) echo "YE" ;;
        serbia|serbian) echo "RS" ;;
        croatia|croatian) echo "HR" ;;
        slovenia|slovenian) echo "SI" ;;
        slovakia|slovak|slovakian) echo "SK" ;;
        lithuania|lithuanian) echo "LT" ;;
        latvia|latvian) echo "LV" ;;
        estonia|estonian) echo "EE" ;;
        albania|albanian) echo "AL" ;;
        "north macedonia"|northmacedonia|macedonia) echo "MK" ;;
        "bosnia and herzegovina"|bosnia|bosnian) echo "BA" ;;
        montenegro|montenegrin) echo "ME" ;;
        kazakhstan|kazakh) echo "KZ" ;;
        uzbekistan|uzbek) echo "UZ" ;;
        azerbaijan|azerbaijani) echo "AZ" ;;
        georgia|georgian) echo "GE" ;;
        armenia|armenian) echo "AM" ;;
        moldova|moldovan) echo "MD" ;;
        *)
            print_error "Unknown country: $input"
            echo "Please use 2-letter ISO country code (e.g., RU, CN, US)"
            exit 1
            ;;
    esac
}

# Block country
block_country() {
    local country="$1"
    local code=$(normalize_country_code "$country")
    local country_name=$(get_country_name "$code")
    
    check_root
    init_chain
    
    # Prompt for reason
    echo -n "Reason for blocking $country_name ($code) [Default Block]: "
    read -r reason
    reason="${reason:-Default Block}"
    
    print_info "Blocking all traffic from $country_name ($code)..."
    
    # Check if already blocked
    if iptables -L "$CHAIN_NAME" -n | grep -q "geoip.*$code"; then
        print_error "$country_name ($code) is already blocked"
        return 1
    fi
    
    # Add single iptables rule for all protocols
    local iptables_cmd="iptables -A $CHAIN_NAME -m geoip --src-cc $code -j DROP"
    if iptables -A "$CHAIN_NAME" -m geoip --src-cc "$code" -j DROP; then
        print_success "Blocked all traffic from $country_name ($code)"
        
        # Save to config
        echo "$code" >> "$CONFIG_FILE"
        sort -u "$CONFIG_FILE" -o "$CONFIG_FILE" 2>/dev/null || true
        
        # Save iptables rules
        save_rules
        
        # Log the action with full iptables command
        log_action "BLOCK" "$code" "$country_name" "$reason" "$iptables_cmd"
        
        print_success "Country $country_name ($code) blocked successfully"
    else
        # Log error without removing existing rules
        log_action "BLOCK" "$code" "$country_name" "$reason" "$iptables_cmd" "Failed to add iptables rule"
        print_error "Failed to block $country_name ($code)"
        return 1
    fi
}

# Unblock country (allow)
unblock_country() {
    local country="$1"
    local code=$(normalize_country_code "$country")
    local country_name=$(get_country_name "$code")
    
    check_root
    
    # Prompt for reason
    echo -n "Reason for unblocking $country_name ($code) [Default Unblock]: "
    read -r reason
    reason="${reason:-Default Unblock}"
    
    print_info "Removing block for $country_name ($code)..."
    
    # Check if rule exists before trying to remove
    if ! iptables -L "$CHAIN_NAME" -n 2>/dev/null | grep -q "geoip.*$code"; then
        local iptables_cmd="iptables -D $CHAIN_NAME -m geoip --src-cc $code -j DROP"
        log_action "UNBLOCK" "$code" "$country_name" "$reason" "$iptables_cmd" "Country not currently blocked"
        print_error "No block found for $country_name ($code) - no rules removed"
        return 1
    fi
    
    # Remove rule from custom chain
    local iptables_cmd="iptables -D $CHAIN_NAME -m geoip --src-cc $code -j DROP"
    if iptables -D "$CHAIN_NAME" -m geoip --src-cc "$code" -j DROP 2>/dev/null; then
        print_success "Removed block for $country_name ($code)"
        
        # Remove from config
        if [ -f "$CONFIG_FILE" ]; then
            sed -i "/^$code$/d" "$CONFIG_FILE"
        fi
        
        # Save iptables rules
        save_rules
        
        # Log the action with full iptables command
        log_action "UNBLOCK" "$code" "$country_name" "$reason" "$iptables_cmd"
        
        print_success "Block removed for $country_name ($code)"
    else
        # Log error without removing from config
        log_action "UNBLOCK" "$code" "$country_name" "$reason" "$iptables_cmd" "Failed to remove iptables rule"
        print_error "Failed to remove block for $country_name ($code) - no rules removed"
        return 1
    fi
}

# List blocked countries history
list_blocked() {
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                    CASTLE WALLS GEOBLOCK HISTORY REPORT"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo
    
    if [ ! -f "$HISTORY_FILE" ]; then
        print_info "No blocking history found"
        return
    fi
    
    # Get unique countries that have been blocked
    local countries=$(grep -E "(BLOCK|UNBLOCK)" "$HISTORY_FILE" 2>/dev/null | \
                     sed -E 's/.*\(([A-Z]{2})\)/\1/' | \
                     sort -u)
    
    if [ -z "$countries" ]; then
        print_info "No blocking history found"
        return
    fi
    
    local first=true
    
    # For each country, show last block and last unblock in chronological order
    for code in $countries; do
        local country_name=$(get_country_name "$code")
        
        # Get last BLOCK action
        local last_block=$(grep "BLOCK.*($code)" "$HISTORY_FILE" 2>/dev/null | tail -1)
        
        # Get last UNBLOCK action
        local last_unblock=$(grep "UNBLOCK.*($code)" "$HISTORY_FILE" 2>/dev/null | tail -1)
        
        # Skip if no entries
        if [ -z "$last_block" ] && [ -z "$last_unblock" ]; then
            continue
        fi
        
        # Add separator between countries
        if [ "$first" = false ]; then
            echo "────────────────────────────────────────────────────────────────────────────────"
        fi
        first=false
        
        # Display country name
        echo -e "${BLUE}$country_name ($code)${NC}"
        
        # Build array of entries with timestamps for sorting
        declare -a entries=()
        declare -a timestamps=()
        
        if [ -n "$last_block" ]; then
            local timestamp=$(echo "$last_block" | sed -E 's/\[([^]]+)\].*/\1/')
            entries+=("${GREEN}BLOCKED${NC}: $timestamp")
            timestamps+=("$timestamp")
        fi
        
        if [ -n "$last_unblock" ]; then
            local timestamp=$(echo "$last_unblock" | sed -E 's/\[([^]]+)\].*/\1/')
            entries+=("${YELLOW}UNBLOCKED${NC}: $timestamp")
            timestamps+=("$timestamp")
        fi
        
        # Sort by timestamp and display (simple bubble sort for 2 elements)
        if [ ${#entries[@]} -eq 2 ]; then
            if [[ "${timestamps[0]}" < "${timestamps[1]}" ]]; then
                echo -e "${entries[0]}"
                echo -e "${entries[1]}"
            else
                echo -e "${entries[1]}"
                echo -e "${entries[0]}"
            fi
        elif [ ${#entries[@]} -eq 1 ]; then
            echo -e "${entries[0]}"
        fi
        
        echo
    done
    
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo
}

# List current rules
list_rules() {
    check_root
    
    if ! iptables -L "$CHAIN_NAME" -n &>/dev/null; then
        print_info "Chain $CHAIN_NAME does not exist. No rules configured."
        return
    fi
    
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                          ACTIVE GEOBLOCK RULES"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo
    iptables -L "$CHAIN_NAME" -n -v --line-numbers
    echo
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo
}

# Flush all rules
flush_rules() {
    check_root
    
    echo "This will remove all active geoblock rules from the firewall."
    echo -n "Continue? (y/n): "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    print_info "Flushing all rules from $CHAIN_NAME..."
    
    # Get list of blocked countries from config and log unblock actions
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r code; do
            [ -z "$code" ] && continue
            local country_name=$(get_country_name "$code")
            log_action "UNBLOCK" "$code" "$country_name" "Flushed by --flush command"
        done < "$CONFIG_FILE"
        rm -f "$CONFIG_FILE"
    fi
    
    # Flush the chain
    if iptables -L "$CHAIN_NAME" -n &>/dev/null; then
        iptables -F "$CHAIN_NAME"
        print_success "All rules flushed from $CHAIN_NAME"
        
        # Save iptables rules
        save_rules
    else
        print_info "Chain $CHAIN_NAME does not exist"
    fi
}

# Clean old log files
clean_logs() {
    check_root
    
    echo "This will remove rotated log files (geoblock.log.1, .2, etc.)"
    echo "The main log file and history will be preserved."
    echo -n "Continue? (y/n): "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    local count=0
    for i in $(seq 1 "$MAX_LOG_FILES"); do
        if [ -f "${LOG_FILE}.$i" ]; then
            rm -f "${LOG_FILE}.$i"
            ((count++))
        fi
    done
    
    if [ "$count" -gt 0 ]; then
        print_success "Removed $count rotated log file(s)"
    else
        print_info "No rotated log files found"
    fi
}

# Check compatibility
check_compatibility() {
    print_info "Checking system compatibility..."
    echo
    
    local all_good=true
    
    # Check iptables
    if command -v iptables &> /dev/null; then
        print_success "iptables: installed"
    else
        print_error "iptables: NOT installed"
        all_good=false
    fi
    
    # Check perl Text::CSV
    if perl -MText::CSV -e 1 &> /dev/null; then
        print_success "libtext-csv-perl: installed"
    else
        print_error "libtext-csv-perl: NOT installed"
        all_good=false
    fi
    
    # Check xtables-addons
    if [ -f /usr/libexec/xtables-addons/xt_geoip_build ] || [ -f /usr/lib/xtables-addons/xt_geoip_build ]; then
        print_success "xtables-addons: installed"
    else
        print_error "xtables-addons: NOT installed"
        all_good=false
    fi
    
    # Check geoip data
    if [ -d "$GEOIP_DIR" ] && [ "$(ls -A $GEOIP_DIR/*.iv4 2>/dev/null | wc -l)" -gt 0 ]; then
        print_success "GeoIP data: present"
    else
        print_error "GeoIP data: NOT present (run: sudo geoblock-update)"
        all_good=false
    fi
    
    # Check kernel module
    if lsmod | grep -q xt_geoip; then
        print_success "xt_geoip module: loaded"
    else
        print_error "xt_geoip module: NOT loaded"
        all_good=false
    fi
    
    # Check custom chain
    if iptables -L "$CHAIN_NAME" -n &>/dev/null; then
        print_success "Custom chain $CHAIN_NAME: exists"
    else
        print_info "Custom chain $CHAIN_NAME: will be created when first rule is added"
    fi
    
    echo
    if [ "$all_good" = true ]; then
        print_success "All compatibility checks passed"
    else
        print_error "Some compatibility checks failed"
        echo
        echo "To fix missing dependencies, you may need to reinstall geoblock."
        echo "Please run the geoblock installer again."
        exit 1
    fi
}

# Remove (uninstall)
remove_geoblock() {
    check_root
    
    echo "This will completely uninstall geoblock and remove all rules."
    echo -n "Continue? (y/n): "
    read -r response
    
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled"
        exit 0
    fi
    
    print_info "Uninstalling geoblock..."
    
    # Log all unblock actions
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r code; do
            [ -z "$code" ] && continue
            local country_name=$(get_country_name "$code")
            log_action "UNBLOCK" "$code" "$country_name" "Removed by --remove command"
        done < "$CONFIG_FILE"
    fi
    
    # Remove custom chain if it exists
    if iptables -L "$CHAIN_NAME" -n &>/dev/null; then
        # Remove jump from INPUT chain
        iptables -D INPUT -j "$CHAIN_NAME" 2>/dev/null || true
        # Flush and delete the custom chain
        iptables -F "$CHAIN_NAME" 2>/dev/null || true
        iptables -X "$CHAIN_NAME" 2>/dev/null || true
        print_success "Removed custom chain $CHAIN_NAME"
    fi
    
    # Remove scripts
    rm -f /usr/local/bin/geoblock
    rm -f /usr/local/bin/geoblock-update
    rm -f /usr/local/bin/geoblock-restore
    
    # Remove systemd service and timer
    systemctl stop geoblock-update.timer 2>/dev/null || true
    systemctl disable geoblock-update.timer 2>/dev/null || true
    systemctl stop geoblock-restore.service 2>/dev/null || true
    systemctl disable geoblock-restore.service 2>/dev/null || true
    rm -f /etc/systemd/system/geoblock-update.service
    rm -f /etc/systemd/system/geoblock-update.timer
    rm -f /etc/systemd/system/geoblock-restore.service
    systemctl daemon-reload 2>/dev/null || true
    
    # Remove cron job
    rm -f /etc/cron.d/geoblock-update
    
    # Remove man page
    rm -f /usr/local/share/man/man8/geoblock.8.gz
    
    # Remove GeoIP data
    echo -n "Remove GeoIP data from $GEOIP_DIR? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$GEOIP_DIR"
        print_success "GeoIP data removed"
    fi
    
    # Remove config and logs
    echo -n "Remove all configuration and logs from ~/.config/cyberacq/geoblock and /var/log/geoblock*? (y/n): "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$HOME/.config/cyberacq/geoblock"
        rm -f /var/log/geoblock.log*
        print_success "Configuration and logs removed"
    fi
    
    print_success "geoblock uninstalled successfully"
}

# Show help
show_help() {
    cat << EOF
Castle Walls Geoblock v$VERSION - Geographic IP blocking utility

USAGE:
    geoblock [OPTIONS] <country>

BLOCKING OPTIONS:
    <country>                   Block traffic from specified country (prompts for reason)
    -u, --unblock <country>     Unblock traffic from specified country (prompts for reason)

MANAGEMENT OPTIONS:
    -l, --list                  List current geoblock firewall rules
    -b, --block-history         Show history of blocked/unblocked countries
    -f, --flush                 Remove all active geoblock rules from firewall
    -c, --compatibility         Check system compatibility and dependencies
    --clean-logs                Remove rotated log files (.log.1, .log.2, etc.)
    -r, --remove                Completely uninstall geoblock
    -v, --version               Show version information
    -h, --help                  Show this help message

COUNTRY:
    Can be specified as:
    - 2-letter ISO code (e.g., RU, CN, US)
    - Full country name (e.g., Russia, China, "United States")

EXAMPLES:
    geoblock russia             Block Russia (will prompt for reason)
    geoblock -u RU              Unblock Russia (will prompt for reason)
    geoblock -l                 List current firewall rules
    geoblock -b                 Show block/unblock history
    geoblock -f                 Flush all active rules
    geoblock --compatibility    Check if dependencies are met
    geoblock --clean-logs       Clean rotated log files

FILES:
    Configuration:  ~/.config/cyberacq/geoblock/blocked_countries.conf
    Rules Backup:   ~/.config/cyberacq/geoblock/block.rules (auto-restored on boot)
    History Log:    ~/.config/cyberacq/geoblock/history.log (never rotated)
    Action Log:     /var/log/geoblock.log (rotated at 10MB)
    GeoIP data:     $GEOIP_DIR/

TROUBLESHOOTING:
    If geoblock malfunctions, run:
        geoblock --compatibility
    
    This will check all dependencies and offer to reinstall missing components.

AUTHOR:
    CYBERACQ

WEBSITE:
    https://cyberacq.com/geoblock

GITHUB:
    https://github.com/cyberacq/geoblock

SEE ALSO:
    geoblock-update(8), iptables(8)
EOF
}

# Show version
show_version() {
    echo "Castle Walls Geoblock version $VERSION"
    echo "Author: CYBERACQ"
    echo "Website: https://cyberacq.com/geoblock"
    echo "GitHub: https://github.com/cyberacq/geoblock"
}

# Main execution
main() {
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi
    
    case "$1" in
        -u|--unblock)
            if [ -z "$2" ]; then
                print_error "Country argument required"
                echo "Usage: geoblock --unblock <country>"
                exit 1
            fi
            unblock_country "$2"
            ;;
        -l|--list)
            list_rules
            ;;
        -b|--block-history)
            list_blocked
            ;;
        -f|--flush)
            flush_rules
            ;;
        -c|--compatibility)
            check_compatibility
            ;;
        --clean-logs)
            clean_logs
            ;;
        -r|--remove)
            remove_geoblock
            ;;
        -v|--version)
            show_version
            ;;
        -h|--help)
            show_help
            ;;
        -*)
            print_error "Unknown option: $1"
            echo "Run 'geoblock --help' for usage information"
            exit 1
            ;;
        *)
            # Default to block if no flag specified
            block_country "$1"
            ;;
    esac
}

main "$@"
GEOBLOCK_EOF
    
    chmod +x "$INSTALL_DIR/geoblock"
    print_success "geoblock script created"
}

# Create geoblock-update script
create_update_script() {
    print_info "Creating geoblock-update script..."
    
    cat > "$INSTALL_DIR/geoblock-update" << 'UPDATE_EOF'
#!/bin/bash
#
# geoblock-update - Update GeoIP database
# Author: CYBERACQ
# Website: https://cyberacq.com/geoblock
# GitHub: https://github.com/cyberacq/geoblock
#

GEOIP_DIR="/usr/share/xt_geoip"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "$1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

# Create directory if it doesn't exist
mkdir -p "$GEOIP_DIR"

# Must cd to GeoIP directory before download and extraction
cd /usr/share/xt_geoip || {
    print_error "Failed to change to directory /usr/share/xt_geoip"
    exit 1
}

print_info "Updating GeoIP database..."

# Get current month and year FIRST
MON=$(date +"%m")
YR=$(date +"%Y")

print_info "Downloading database for $YR-$MON..."

# Download latest database with proper variable expansion
if wget https://download.db-ip.com/free/dbip-country-lite-${YR}-${MON}.csv.gz -O dbip-country-lite.csv.gz; then
    print_success "Database downloaded successfully"
else
    print_error "Failed to download database for $YR-$MON"
    print_error "URL attempted: https://download.db-ip.com/free/dbip-country-lite-${YR}-${MON}.csv.gz"
    exit 1
fi

# Verify file exists before attempting to decompress
if [ ! -f dbip-country-lite.csv.gz ]; then
    print_error "Downloaded file not found at /usr/share/xt_geoip/dbip-country-lite.csv.gz"
    exit 1
fi

# Decompress
print_info "Decompressing database..."
if gunzip -f dbip-country-lite.csv.gz; then
    print_success "Database decompressed successfully"
else
    print_error "Failed to decompress database"
    exit 1
fi

# Build GeoIP data
print_info "Building GeoIP data..."

# Find xt_geoip_build location
if [ -f /usr/libexec/xtables-addons/xt_geoip_build ]; then
    GEOIP_BUILD=/usr/libexec/xtables-addons/xt_geoip_build
elif [ -f /usr/lib/xtables-addons/xt_geoip_build ]; then
    GEOIP_BUILD=/usr/lib/xtables-addons/xt_geoip_build
else
    print_error "xt_geoip_build not found"
    exit 1
fi

if $GEOIP_BUILD dbip-country-lite.csv; then
    print_success "GeoIP data built successfully"
else
    print_error "Failed to build GeoIP data"
    exit 1
fi

# Cleanup
rm dbip-country-lite.csv

# Load kernel module
if ! lsmod | grep -q xt_geoip; then
    print_info "Loading xt_geoip kernel module..."
    modprobe xt_geoip || print_error "Failed to load xt_geoip module"
fi

print_success "GeoIP database update complete"
UPDATE_EOF
    
    chmod +x "$INSTALL_DIR/geoblock-update"
    print_success "geoblock-update script created"
}

# Create geoblock-restore script
create_restore_script() {
    print_info "Creating geoblock-restore script..."
    
    cat > "$INSTALL_DIR/geoblock-restore" << 'RESTORE_EOF'
#!/bin/bash
#
# geoblock-restore - Restore geoblock iptables rules on boot
# Author: CYBERACQ
# Website: https://cyberacq.com/geoblock
# GitHub: https://github.com/cyberacq/geoblock
#

RULES_FILE="$HOME/.config/cyberacq/geoblock/block.rules"

# Check if rules file exists
if [ ! -f "$RULES_FILE" ]; then
    exit 0
fi

# Restore iptables rules
iptables-restore < "$RULES_FILE" 2>/dev/null

exit 0
RESTORE_EOF
    
    chmod +x "$INSTALL_DIR/geoblock-restore"
    print_success "geoblock-restore script created"
}

# Create systemd service and timer
create_systemd_service() {
    print_info "Creating systemd service and timer..."
    
    # Clean up old versions if they exist
    systemctl stop geoblock-update.timer 2>/dev/null || true
    systemctl disable geoblock-update.timer 2>/dev/null || true
    systemctl stop geoblock-update.service 2>/dev/null || true
    systemctl disable geoblock-update.service 2>/dev/null || true
    systemctl stop geoblock-restore.service 2>/dev/null || true
    systemctl disable geoblock-restore.service 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/geoblock-update.service" 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/geoblock-update.timer" 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/geoblock-restore.service" 2>/dev/null || true
    systemctl daemon-reload
    
    # Create update service file
    cat > "$SYSTEMD_DIR/geoblock-update.service" << 'SERVICE_EOF'
[Unit]
Description=Update GeoIP database for geoblock
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/geoblock-update
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF
    
    # Create update timer file
    cat > "$SYSTEMD_DIR/geoblock-update.timer" << 'TIMER_EOF'
[Unit]
Description=Update GeoIP database twice daily
Requires=geoblock-update.service

[Timer]
OnCalendar=*-*-* 06,18:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER_EOF
    
    # Create restore service file for boot
    cat > "$SYSTEMD_DIR/geoblock-restore.service" << 'RESTORE_EOF'
[Unit]
Description=Restore geoblock iptables rules on boot
After=network.target iptables.service
Before=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/geoblock-restore
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
RESTORE_EOF
    
    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable geoblock-update.timer
    systemctl start geoblock-update.timer
    systemctl enable geoblock-restore.service
    
    print_success "Systemd services and timer created"
}

# Create cron job (fallback for non-systemd systems)
create_cron_job() {
    print_info "Creating cron job for GeoIP updates..."
    
    cat > "$CRON_DIR/geoblock-update" << 'CRON_EOF'
# Update GeoIP database twice daily (6 AM and 6 PM)
0 6,18 * * * root /usr/local/bin/geoblock-update >/dev/null 2>&1
CRON_EOF
    
    chmod 0644 "$CRON_DIR/geoblock-update"
    print_success "Cron job created"
}

# Create man page
create_manpage() {
    print_info "Creating man page..."
    
    mkdir -p "$MAN_DIR"
    
    cat > "$MAN_DIR/geoblock.8" << 'MANPAGE_EOF'
.TH GEOBLOCK 8 "January 2026" "Castle Walls Geoblock 1.5" "System Administration"
.SH NAME
geoblock \- Castle Walls Geographic IP blocking utility using iptables
.SH SYNOPSIS
.B geoblock
[\fIOPTIONS\fR] <\fICOUNTRY\fR>
.SH DESCRIPTION
.B Castle Walls Geoblock
is a utility for blocking network traffic based on geographic location using iptables and the xt_geoip module. It allows administrators to easily block or allow traffic from specific countries with reason tracking and comprehensive logging.

All geoblock rules are managed in a custom iptables chain named \fBcastlewalls-geoblock\fR, which provides clean organization and easy management of geolocation-based firewall rules.
.SH OPTIONS
.SS Blocking Options
.TP
.B <country>
Block all incoming traffic from the specified country. Will prompt for a reason (default: "Default Block").
.TP
.BR \-u ", " \-\-unblock " " \fICOUNTRY\fR
Unblock traffic from the specified country. Will prompt for a reason (default: "Default Unblock").
.SS Management Options
.TP
.BR \-l ", " \-\-list
List current geoblock firewall rules (equivalent to: iptables -L castlewalls-geoblock -n -v).
.TP
.BR \-b ", " \-\-block\-history
Display history of blocked/unblocked countries with timestamps.
.TP
.BR \-f ", " \-\-flush
Remove all active geoblock rules from the firewall.
.TP
.BR \-c ", " \-\-compatibility
Check system compatibility by verifying all required dependencies and kernel modules.
.TP
.B \-\-clean\-logs
Remove rotated log files (geoblock.log.1, .log.2, etc.). Main log and history are preserved.
.TP
.BR \-r ", " \-\-remove
Completely uninstall geoblock and remove all components.
.TP
.BR \-v ", " \-\-version
Display version information.
.TP
.BR \-h ", " \-\-help
Display help message with usage information.
.SH COUNTRY SPECIFICATION
Countries can be specified in the following formats:
.TP
.B Two-letter ISO code
RU, CN, US, GB, etc.
.TP
.B Full country name
Russia, China, "United States", etc.
.PP
Country names are case-insensitive.
.SH EXAMPLES
.TP
Block all traffic from Russia:
.B geoblock russia
.br
(Will prompt: "Reason for blocking Russia (RU) [Default Block]:")
.TP
Unblock traffic using ISO code:
.B geoblock \-u RU
.br
(Will prompt: "Reason for unblocking Russia (RU) [Default Unblock]:")
.TP
List current firewall rules:
.B geoblock \-l
.TP
Show block/unblock history:
.B geoblock \-b
.TP
Remove all active rules:
.B geoblock \-f
.TP
Check system compatibility:
.B geoblock \-\-compatibility
.TP
Clean rotated logs:
.B geoblock \-\-clean\-logs
.TP
Completely uninstall:
.B geoblock \-\-remove
.SH FILES
.TP
.I /usr/local/bin/geoblock
Main geoblock script
.TP
.I /usr/local/bin/geoblock-update
GeoIP database update script
.TP
.I /usr/local/bin/geoblock-restore
Boot-time rules restore script
.TP
.I ~/.config/cyberacq/geoblock/blocked_countries.conf
Configuration file storing currently blocked countries
.TP
.I ~/.config/cyberacq/geoblock/block.rules
Saved iptables ruleset, automatically restored on boot
.TP
.I ~/.config/cyberacq/geoblock/history.log
Permanent history of all block/unblock actions (never rotated or deleted)
.TP
.I /var/log/geoblock.log
Main action log (rotated at 10MB, keeps up to 5 rotated files)
.TP
.I /usr/share/xt_geoip/
Directory containing GeoIP database files
.SH IPTABLES CHAIN
All geoblock rules are stored in a custom iptables chain named \fBcastlewalls-geoblock\fR. This chain is automatically created on first use and linked to the INPUT chain. You can view all active geoblock rules with:

.B iptables -L castlewalls-geoblock -n -v

Or more simply:

.B geoblock -l
.SH LOGGING
Geoblock maintains two log files:
.TP
.B /var/log/geoblock.log
Records all block and unblock actions with timestamps, users, and reasons. Automatically rotated when it reaches 10MB in size, keeping up to 5 rotated files (.log.1 through .log.5).
.TP
.B ~/.config/cyberacq/geoblock/history.log
Permanent history of all actions. This file is never rotated or automatically deleted, even when using \fB--clean-logs\fR. Only removed when using \fB--remove\fR to uninstall geoblock.
.SH TROUBLESHOOTING
If geoblock malfunctions or produces unexpected results, first check that all dependencies are still properly installed:

.B geoblock --compatibility

This will verify:
.RS
- iptables is installed
.br
- libtext-csv-perl is installed
.br
- xtables-addons-common is installed
.br
- GeoIP database is present
.br
- xt_geoip kernel module is loaded
.br
- Custom iptables chain exists or can be created
.RE

If any dependencies are missing, you may need to reinstall geoblock using the installer, which will offer to install missing components.
.SH DEPENDENCIES
.B geoblock
requires the following packages:
.TP
.B iptables
Firewall administration tool
.TP
.B libtext-csv-perl
Perl module for CSV parsing
.TP
.B xtables-addons-common
Extensions for iptables including xt_geoip module
.SH AUTOMATIC UPDATES
The GeoIP database is automatically updated twice daily (at 6 AM and 6 PM) via systemd timer or cron job, depending on the system configuration.
.SH AUTOMATIC RESTORE ON BOOT
Geoblock automatically saves the current iptables ruleset to \fI~/.config/cyberacq/geoblock/block.rules\fR whenever a block or unblock action is performed. A systemd service (\fBgeoblock-restore.service\fR) is configured to automatically restore these rules on system boot, ensuring your geoblocking configuration persists across reboots.

The restore happens early in the boot process, after the network is available but before network-online.target, ensuring your firewall rules are in place as soon as possible.
.SH AUTHOR
Written by CYBERACQ.
.SH REPORTING BUGS
Report bugs to: https://github.com/cyberacq/geoblock/issues
.SH COPYRIGHT
Copyright \\\\(co 2026 CYBERACQ
.SH SEE ALSO
.BR iptables (8),
.BR geoblock-update (8)
MANPAGE_EOF
    
    # Compress man page
    gzip -f "$MAN_DIR/geoblock.8"
    
    print_success "Man page created"
}

# Initial GeoIP update
initial_geoip_update() {
    print_info "Performing initial GeoIP database update..."
    
    if "$INSTALL_DIR/geoblock-update"; then
        print_success "Initial GeoIP update completed"
    else
        print_warning "Initial GeoIP update failed, but you can run it manually later"
    fi
}

# Main installation
main() {
    echo "================================================"
    echo "  Castle Walls Geoblock $VERSION Installer"
    echo "  Author: CYBERACQ"
    echo "  Website: https://cyberacq.com/geoblock"
    echo "  GitHub: https://github.com/cyberacq/geoblock"
    echo "================================================"
    echo
    
    check_root
    detect_distro
    get_package_manager
    check_dependencies
    
    echo
    print_info "Installing geoblock..."
    
    create_geoblock_script
    create_update_script
    create_restore_script
    
    # Set up automatic updates
    if command -v systemctl &> /dev/null; then
        create_systemd_service
    else
        print_info "systemd not detected, using cron for automatic updates"
        create_cron_job
    fi
    
    create_manpage
    initial_geoip_update
    
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    
    echo
    print_success "Installation completed successfully!"
    echo
    echo "Usage examples:"
    echo "  geoblock -b russia        # Block traffic from Russia"
    echo "  geoblock --allow CN       # Remove block for China"
    echo "  geoblock --compatibility  # Check system compatibility"
    echo "  geoblock --help           # Show help message"
    echo
    echo "GeoIP database will be updated automatically twice daily."
    echo "Man page available: man geoblock"
    echo
}

main "$@"
