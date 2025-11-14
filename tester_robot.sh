#!/bin/bash
#======================================
# TESTER ROBOT - Website Monitoring Tool
# Author: Riccardo
# Version: 2.0.0
#======================================

set -euo pipefail  # Strict mode

#======================================
# CONFIGURAZIONE E COSTANTI
#======================================

readonly SCRIPT_NAME="tester_robot"
readonly SCRIPT_VERSION="2.0.0"
readonly LOG_DIR="logs"
readonly CONFIG_FILE=".headers.env"

# Valori di default (saranno sovrascritti dal file .headers.env se presente)
DEFAULT_DELAY=0.5
DEFAULT_PARALLEL_JOBS=1
MIN_LOG_LEVEL="INFO"

# Variabili per autenticazione (caricate da .headers.env)
XSRF_TOKEN=""
SESSION_TOKEN=""

# Variabili per headers HTTP (caricate da .headers.env)
USER_AGENT=""
ACCEPT=""
ACCEPT_ENCODING=""
ACCEPT_LANGUAGE=""
CONNECTION=""
SEC_FETCH_DEST=""
SEC_FETCH_MODE=""
SEC_FETCH_SITE=""
SEC_FETCH_USER=""
UPGRADE_INSECURE_REQUESTS=""
SEC_CH_UA=""
SEC_CH_UA_MOBILE=""
SEC_CH_UA_PLATFORM=""

# Variabili per opzioni curl
CONNECT_TIMEOUT="10"
MAX_TIME="30"
INSECURE="true"
FOLLOW_REDIRECTS="true"
MAX_REDIRECTS="10"
LOG_HEADERS="false"

# REFERER_URL sarà impostato dinamicamente basato sull'URL target
REFERER_URL=""

# Array dinamico per gli headers HTTP che verrà popolato in runtime
declare -a HTTP_HEADERS=()

#======================================
# VARIABILI GLOBALI
#======================================

# Variabili di configurazione runtime
DOMAIN=""
LOG_FILE=""
DELAY=$DEFAULT_DELAY
PARALLEL_JOBS=$DEFAULT_PARALLEL_JOBS
VERBOSE=""

# Variabili per le opzioni della riga di comando
HELP=0
FOLLOW=0
TEST=0
INCLUDE_ASSETS=0
URLVALUE=""
PROFILE=""

# Array per i processi in background
declare -a g_background_pids=()

#======================================
# FUNZIONI DI CONFIGURAZIONE
#======================================

config_load_headers_env() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        echo "WARNING: File di configurazione $config_file non trovato. Usando valori di default."
        config_set_defaults
        return 1
    fi
    
    echo "INFO: Caricamento configurazione da: $config_file"
    
    # Disabilita temporaneamente strict mode
    set +euo pipefail
    
    # Carica la configurazione facendo source del file filtrato (più sicuro)
    while IFS='=' read -r key value; do
        # Ignora commenti e righe vuote
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # Pulisci key e value (senza xargs per evitare problemi con quotes)
        key=$(echo "$key" | tr -d ' \t')
        value=$(echo "$value" | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Rimuovi doppi apici esterni se presenti
        if [[ "$value" =~ ^\".*\"$ ]]; then
            value="${value#\"}"
            value="${value%\"}"
        fi
        
        # Assegna il valore alla variabile
        case "$key" in
            XSRF_TOKEN) XSRF_TOKEN="$value" ;;
            SESSION_TOKEN) SESSION_TOKEN="$value" ;;
            USER_AGENT) USER_AGENT="$value" ;;
            ACCEPT) ACCEPT="$value" ;;
            ACCEPT_ENCODING) ACCEPT_ENCODING="$value" ;;
            ACCEPT_LANGUAGE) ACCEPT_LANGUAGE="$value" ;;
            CONNECTION) CONNECTION="$value" ;;
            SEC_FETCH_DEST) SEC_FETCH_DEST="$value" ;;
            SEC_FETCH_MODE) SEC_FETCH_MODE="$value" ;;
            SEC_FETCH_SITE) SEC_FETCH_SITE="$value" ;;
            SEC_FETCH_USER) SEC_FETCH_USER="$value" ;;
            UPGRADE_INSECURE_REQUESTS) UPGRADE_INSECURE_REQUESTS="$value" ;;
            SEC_CH_UA) SEC_CH_UA="$value" ;;
            SEC_CH_UA_MOBILE) SEC_CH_UA_MOBILE="$value" ;;
            SEC_CH_UA_PLATFORM) SEC_CH_UA_PLATFORM="$value" ;;
            CONNECT_TIMEOUT) CONNECT_TIMEOUT="$value" ;;
            MAX_TIME) MAX_TIME="$value" ;;
            INSECURE) INSECURE="$value" ;;
            FOLLOW_REDIRECTS) FOLLOW_REDIRECTS="$value" ;;
            MAX_REDIRECTS) MAX_REDIRECTS="$value" ;;
            MIN_LOG_LEVEL) MIN_LOG_LEVEL="$value" ;;
            LOG_HEADERS) LOG_HEADERS="$value" ;;
            DEFAULT_DELAY) DEFAULT_DELAY="$value" ;;
            DEFAULT_PARALLEL_JOBS) DEFAULT_PARALLEL_JOBS="$value" ;;
        esac
    done < <(grep -E '^[[:space:]]*[A-Z_]+=' "$config_file" 2>/dev/null)
    
    # Riabilita strict mode
    set -euo pipefail
    
    # Imposta valori di default per quelli non trovati
    config_set_defaults
    
    # Valida i valori caricati
    # config_validate_values
    
    echo "DEBUG: Configurazione caricata con successo"
    return 0
}

config_set_defaults() {
    # Imposta valori di default se non caricati da file
    XSRF_TOKEN="${XSRF_TOKEN:-}"
    SESSION_TOKEN="${SESSION_TOKEN:-}"
    USER_AGENT="${USER_AGENT:-Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36}"
    ACCEPT="${ACCEPT:-text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7}"
    ACCEPT_ENCODING="${ACCEPT_ENCODING:-gzip, deflate, br, zstd}"
    ACCEPT_LANGUAGE="${ACCEPT_LANGUAGE:-it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7}"
    CONNECTION="${CONNECTION:-keep-alive}"
    SEC_FETCH_DEST="${SEC_FETCH_DEST:-document}"
    SEC_FETCH_MODE="${SEC_FETCH_MODE:-navigate}"
    SEC_FETCH_SITE="${SEC_FETCH_SITE:-same-origin}"
    SEC_FETCH_USER="${SEC_FETCH_USER:-?1}"
    UPGRADE_INSECURE_REQUESTS="${UPGRADE_INSECURE_REQUESTS:-1}"
    SEC_CH_UA="${SEC_CH_UA:-\"Chromium\";v=\"140\", \"Not=A?Brand\";v=\"24\", \"Google Chrome\";v=\"140\"}"
    SEC_CH_UA_MOBILE="${SEC_CH_UA_MOBILE:-?0}"
    SEC_CH_UA_PLATFORM="${SEC_CH_UA_PLATFORM:-\"Windows\"}"
}

config_validate_values() {
    # Validazione base dei valori numerici
    [[ ! "$CONNECT_TIMEOUT" =~ ^[0-9]+$ ]] && CONNECT_TIMEOUT=10
    [[ ! "$MAX_TIME" =~ ^[0-9]+$ ]] && MAX_TIME=30
    [[ ! "$MAX_REDIRECTS" =~ ^[0-9]+$ ]] && MAX_REDIRECTS=10
    [[ ! "$DEFAULT_DELAY" =~ ^[0-9]+\.?[0-9]*$ ]] && DEFAULT_DELAY=0.5
    [[ ! "$DEFAULT_PARALLEL_JOBS" =~ ^[0-9]+$ ]] && DEFAULT_PARALLEL_JOBS=1
    
    # Validazione valori booleani
    [[ ! "$INSECURE" =~ ^(true|false)$ ]] && INSECURE="true"
    [[ ! "$FOLLOW_REDIRECTS" =~ ^(true|false)$ ]] && FOLLOW_REDIRECTS="true"
    [[ ! "$LOG_HEADERS" =~ ^(true|false)$ ]] && LOG_HEADERS="false"
    
    # Validazione log level
    local valid_levels=("DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL")
    local level_valid=false
    for level in "${valid_levels[@]}"; do
        [[ "$MIN_LOG_LEVEL" == "$level" ]] && level_valid=true && break
    done
    [[ "$level_valid" == false ]] && MIN_LOG_LEVEL="INFO"
}

#======================================
# GESTIONE PROFILI CONFIGURAZIONE
#======================================

# Directory per profili e template
readonly PROFILES_DIR="profiles"
readonly TEMPLATES_DIR="templates"

config_load_profile() {
    local profile="$1"
    local profile_file="$PROFILES_DIR/${profile}.env"
    
    if [[ ! -f "$profile_file" ]]; then
        echo "ERROR: Profilo '$profile' non trovato in $profile_file"
        echo "INFO: Profili disponibili:"
        config_list_profiles
        return 1
    fi
    
    echo "INFO: Caricamento profilo: $profile"
    
    # Prima imposta i default, poi carica il profilo specifico
    config_set_defaults
    
    # Carica il profilo specifico
    config_load_headers_env "$profile_file"
    
    echo "INFO: Profilo '$profile' caricato con successo"
    return 0
}

config_list_profiles() {
    echo "Profili disponibili:"
    if [[ -d "$PROFILES_DIR" ]]; then
        for profile_file in "$PROFILES_DIR"/*.env; do
            if [[ -f "$profile_file" ]]; then
                local profile_name=$(basename "$profile_file" .env)
                local description=""
                
                # Cerca una descrizione nel profilo
                if grep -q "^# DESCRIPTION:" "$profile_file" 2>/dev/null; then
                    description=$(grep "^# DESCRIPTION:" "$profile_file" | cut -d: -f2- | sed 's/^ *//')
                fi
                
                if [[ -n "$description" ]]; then
                    echo "  - $profile_name: $description"
                else
                    echo "  - $profile_name"
                fi
            fi
        done
    else
        echo "  Nessun profilo trovato (directory $PROFILES_DIR non esistente)"
    fi
}

config_create_profile_template() {
    local profile="$1"
    local profile_file="$PROFILES_DIR/${profile}.env"
    
    if [[ -f "$profile_file" ]]; then
        echo "WARNING: Il profilo '$profile' esiste già in $profile_file"
        return 1
    fi
    
    # Crea il profilo basato sul .headers.env attuale o sui default
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$profile_file"
    else
        config_generate_default_profile > "$profile_file"
    fi
    
    echo "INFO: Template profilo '$profile' creato in $profile_file"
    echo "INFO: Modifica il file per personalizzare la configurazione"
    return 0
}

config_generate_default_profile() {
    cat <<EOF
# DESCRIPTION: Profilo personalizzato generato automaticamente
# Created: $(date)

# Authentication tokens
XSRF_TOKEN=""
SESSION_TOKEN=""

# Browser emulation headers
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
ACCEPT="text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
ACCEPT_ENCODING="gzip, deflate, br, zstd"
ACCEPT_LANGUAGE="it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7"
CONNECTION="keep-alive"
UPGRADE_INSECURE_REQUESTS="1"

# Connection settings
CONNECT_TIMEOUT="15"
MAX_TIME="60"
INSECURE="true"
FOLLOW_REDIRECTS="true"
MAX_REDIRECTS="10"

# Default execution parameters
DEFAULT_DELAY="0.5"
DEFAULT_PARALLEL_JOBS="1"

# Logging configuration
MIN_LOG_LEVEL="INFO"
LOG_HEADERS="false"
EOF
}

#======================================
# FUNZIONI DI LOGGING
#======================================

log_message() {
    local LEVEL="$1"
    local MESSAGE="$2"
    local FILENAME="${3:-$(log_get_filename "$URLVALUE")}"  # Usa il 3° parametro o default
    local LOG_LEVELS=("DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL")
    local MIN_LOG_LEVEL="${MIN_LOG_LEVEL:-INFO}"
    local TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")
    local CLEAN_MESSAGE=$(echo "$MESSAGE" | sed -E 's/\x1B\[[0-9;]*[mK]//g')
    local LEVEL_INDEX
    local MIN_INDEX

    for i in "${!LOG_LEVELS[@]}"; do
        if [[ "${LOG_LEVELS[$i]}" == "$LEVEL" ]]; then
            LEVEL_INDEX=$i
        fi
        if [[ "${LOG_LEVELS[$i]}" == "$MIN_LOG_LEVEL" ]]; then
            MIN_INDEX=$i
        fi
    done
    
    if [[ -n "$LEVEL_INDEX" && -n "$MIN_INDEX" && $LEVEL_INDEX -ge $MIN_INDEX ]]; then
        echo "[$TIMESTAMP] $LEVEL [[$CLEAN_MESSAGE]]" | tee -a "logs/$FILENAME"
    fi
}

log_get_filename() {
    local url="${1:-$DOMAIN}"
    local domain=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
    local date=$(date '+%Y-%m-%d')
    echo "${domain}-${date}.log"
}

log_setup() {
    mkdir -p "$LOG_DIR"
    if [[ -n "$DOMAIN" ]]; then
        LOG_FILE=$(log_get_filename "$DOMAIN")
        log_message "INFO" "Log inizializzato: $LOG_FILE"
    fi
}

#======================================
# FUNZIONI HTTP
#======================================

http_setup_headers() {
    local target_url="$1"
    
    # Estrai il dominio base dall'URL target
    local base_domain=$(echo "$target_url" | grep -oP 'https?://[^/]+')
    local host_header=$(echo "$target_url" | grep -oP 'https?://\K[^/]+')
    REFERER_URL="$base_domain/"
    
    # Popola l'array HTTP_HEADERS con le variabili dinamiche
    HTTP_HEADERS=()
    
    # Aggiungi headers solo se definiti (non vuoti)
    [[ -n "$ACCEPT" ]] && HTTP_HEADERS+=("Accept: $ACCEPT")
    [[ -n "$ACCEPT_ENCODING" ]] && HTTP_HEADERS+=("Accept-Encoding: $ACCEPT_ENCODING")
    [[ -n "$ACCEPT_LANGUAGE" ]] && HTTP_HEADERS+=("Accept-Language: $ACCEPT_LANGUAGE")
    [[ -n "$CONNECTION" ]] && HTTP_HEADERS+=("Connection: $CONNECTION")
    [[ -n "$host_header" ]] && HTTP_HEADERS+=("Host: $host_header")
    [[ -n "$SEC_FETCH_DEST" ]] && HTTP_HEADERS+=("Sec-Fetch-Dest: $SEC_FETCH_DEST")
    [[ -n "$SEC_FETCH_MODE" ]] && HTTP_HEADERS+=("Sec-Fetch-Mode: $SEC_FETCH_MODE")
    [[ -n "$SEC_FETCH_SITE" ]] && HTTP_HEADERS+=("Sec-Fetch-Site: $SEC_FETCH_SITE")
    [[ -n "$SEC_FETCH_USER" ]] && HTTP_HEADERS+=("Sec-Fetch-User: $SEC_FETCH_USER")
    [[ -n "$UPGRADE_INSECURE_REQUESTS" ]] && HTTP_HEADERS+=("Upgrade-Insecure-Requests: $UPGRADE_INSECURE_REQUESTS")
    [[ -n "$USER_AGENT" ]] && HTTP_HEADERS+=("User-Agent: $USER_AGENT")
    [[ -n "$SEC_CH_UA" ]] && HTTP_HEADERS+=("sec-ch-ua: $SEC_CH_UA")
    [[ -n "$SEC_CH_UA_MOBILE" ]] && HTTP_HEADERS+=("sec-ch-ua-mobile: $SEC_CH_UA_MOBILE")
    [[ -n "$SEC_CH_UA_PLATFORM" ]] && HTTP_HEADERS+=("sec-ch-ua-platform: $SEC_CH_UA_PLATFORM")
    
    # Aggiungi il header Referer con il dominio corretto
    HTTP_HEADERS+=("Referer: $REFERER_URL")
    
    if [[ "$LOG_HEADERS" == "true" ]]; then
        log_message "DEBUG" "Headers configurati: ${#HTTP_HEADERS[@]} headers"
        for header in "${HTTP_HEADERS[@]}"; do
            log_message "DEBUG" "  -> $header"
        done
    else
        log_message "DEBUG" "Headers configurati con Referer: $REFERER_URL (${#HTTP_HEADERS[@]} headers totali)"
    fi
}

http_request() {
    local url="$1"
    local use_headers="${2:-true}"
    
    # Costruisci opzioni curl dinamicamente
    local curl_options=()
    
    # Timeout options
    curl_options+=(--connect-timeout "$CONNECT_TIMEOUT")
    curl_options+=(--max-time "$MAX_TIME")
    
    # Aggiungi metriche dettagliate di timing e performance
    curl_options+=(--write-out "METRICS||%{http_code}||%{time_total}||%{time_namelookup}||%{time_connect}||%{time_appconnect}||%{time_pretransfer}||%{time_redirect}||%{time_starttransfer}||%{size_download}||%{size_upload}||%{size_header}||%{speed_download}||%{speed_upload}||%{num_connects}||%{num_redirects}||%{url_effective}\n")
    
    # SSL options
    [[ "$INSECURE" == "true" ]] && curl_options+=(-k)
    
    # Redirect options
    if [[ "$FOLLOW_REDIRECTS" == "true" ]]; then
        curl_options+=(-L --max-redirs "$MAX_REDIRECTS")
    fi
    
    # Headers
    if [[ "$use_headers" == "true" ]]; then
        for header in "${HTTP_HEADERS[@]}"; do
            curl_options+=("-H" "$header")
        done
    fi
    
    # Cookies per autenticazione (solo se definiti)
    local cookie_string=""
    [[ -n "$XSRF_TOKEN" ]] && cookie_string+="XSRF-TOKEN=${XSRF_TOKEN};"
    [[ -n "$SESSION_TOKEN" ]] && cookie_string+=" tera_pa_session=${SESSION_TOKEN};"
    
    [[ -n "$cookie_string" ]] && curl_options+=(-b "${cookie_string%;}")
    
    # Esegui la richiesta e pulisci null bytes per evitare warning bash
    curl -s "$url" "${curl_options[@]}" 2>/dev/null | tr -d '\0' || echo "ERROR"
}

#======================================
# FUNZIONI DI ANALISI METRICHE
#======================================

http_identify_asset_type() {
    local url="$1"
    
    # Rimuovi parametri di query per analisi più pulita
    local clean_url=$(echo "$url" | sed 's/\?.*$//')
    
    # Identifica il tipo basato sull'estensione
    case "$clean_url" in
        *.css) echo "CSS stylesheet" ;;
        *.js) echo "JavaScript" ;;
        *.png) echo "PNG image" ;;
        *.jpg|*.jpeg) echo "JPEG image" ;;
        *.gif) echo "GIF image" ;;
        *.svg) echo "SVG image" ;;
        *.ico) echo "Icon" ;;
        *.woff|*.woff2) echo "Web font" ;;
        *.ttf|*.eot) echo "Font file" ;;
        *.pdf) echo "PDF document" ;;
        *.mp3|*.wav) echo "Audio file" ;;
        *.mp4|*.avi|*.mov|*.webm) echo "Video file" ;;
        *.zip|*.rar|*.tar|*.gz) echo "Archive file" ;;
        *.json) echo "JSON data" ;;
        *.xml) echo "XML data" ;;
        *.webp) echo "WebP image" ;;
        *) echo "HTML page" ;;
    esac
}

http_is_asset() {
    local url="$1"
    local asset_type=$(http_identify_asset_type "$url")
    [[ "$asset_type" != "HTML page" ]]
}

http_parse_metrics() {
    local response="$1"
    local -n metrics_result=$2
    
    # Inizializza l'array associativo
    declare -A temp_metrics
    
    # Pulisci il response dai null bytes e estrai la riga delle metriche
    local clean_response=$(echo "$response" | tr -d '\0')
    local metrics_line=$(echo "$clean_response" | grep "^METRICS||" | tail -n1)
    
    if [[ -n "$metrics_line" ]]; then
        # Usa awk per parsing più robusto
        temp_metrics["status_code"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $2}')
        temp_metrics["time_total"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $3}')
        temp_metrics["time_namelookup"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $4}')
        temp_metrics["time_connect"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $5}')
        temp_metrics["time_appconnect"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $6}')
        temp_metrics["time_pretransfer"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $7}')
        temp_metrics["time_redirect"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $8}')
        temp_metrics["time_starttransfer"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $9}')
        temp_metrics["size_download"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $10}')
        temp_metrics["size_upload"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $11}')
        temp_metrics["size_header"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $12}')
        temp_metrics["speed_download"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $13}')
        temp_metrics["speed_upload"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $14}')
        temp_metrics["num_connects"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $15}')
        temp_metrics["num_redirects"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $16}')
        temp_metrics["url_effective"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $17}')
    else
        # Valori di default in caso di errore
        temp_metrics["status_code"]="ERROR"
        temp_metrics["time_total"]="0"
        temp_metrics["time_namelookup"]="0"
        temp_metrics["time_connect"]="0"
        temp_metrics["time_appconnect"]="0"
        temp_metrics["time_pretransfer"]="0"
        temp_metrics["time_redirect"]="0"
        temp_metrics["time_starttransfer"]="0"
        temp_metrics["size_download"]="0"
        temp_metrics["size_upload"]="0"
        temp_metrics["size_header"]="0"
        temp_metrics["speed_download"]="0"
        temp_metrics["speed_upload"]="0"
        temp_metrics["num_connects"]="0"
        temp_metrics["num_redirects"]="0"
        temp_metrics["url_effective"]=""
    fi
    
    # Copia nell'array di output
    for key in "${!temp_metrics[@]}"; do
        metrics_result["$key"]="${temp_metrics[$key]}"
    done
}

http_format_performance_log() {
    local -n metrics_data=$1
    local url="$2"
    local worker_id="${3:-Main}"
    
    local status_code="${metrics_data[status_code]}"
    local time_total="${metrics_data[time_total]}"
    local time_connect="${metrics_data[time_connect]}"
    local time_starttransfer="${metrics_data[time_starttransfer]}"
    local size_download="${metrics_data[size_download]}"
    local speed_download="${metrics_data[speed_download]}"
    local num_redirects="${metrics_data[num_redirects]}"
    
    # Converti i valori per una lettura più facile usando awk
    local time_total_ms=$(echo "$time_total" | awk '{printf "%.0f", $1 * 1000}')
    local time_connect_ms=$(echo "$time_connect" | awk '{printf "%.0f", $1 * 1000}')
    local time_starttransfer_ms=$(echo "$time_starttransfer" | awk '{printf "%.0f", $1 * 1000}')
    local size_kb=$(echo "$size_download" | awk '{printf "%.1f", $1 / 1024}')
    local speed_kbps=$(echo "$speed_download" | awk '{printf "%.1f", $1 / 1024}')
    
    # Formato del messaggio di log dettagliato
    local performance_msg="${worker_id}: ${url} [${status_code}] ${time_total_ms}ms (conn:${time_connect_ms}ms ttfb:${time_starttransfer_ms}ms) ${size_kb}KB @${speed_kbps}KB/s"
    
    # Aggiungi informazioni sui redirect se presenti
    if [[ "$num_redirects" != "0" ]]; then
        performance_msg+=" redirects:${num_redirects}"
    fi
    
    echo "$performance_msg"
}

http_extract_status_code() {
    local page_content="$1"
    local status_code
    
    # Pulisci il content dai null bytes e estrai status code dalla riga METRICS
    local clean_content=$(printf '%s' "$page_content" | tr -d '\0')
    local metrics_line=$(printf '%s' "$clean_content" | grep "^METRICS||" | tail -n1)
    
    if [[ -n "$metrics_line" ]]; then
        status_code=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $2}')
    else
        # Se non c'è la riga METRICS, verifica se è un errore di connessione
        if [[ "$page_content" == "ERROR" ]]; then
            status_code="ERROR"
        else
            status_code="200"  # Assumiamo successo se non specificato
        fi
    fi
    
    echo "$status_code"
}

http_extract_links() {
    local page_content="$1"
    local url="$2"
    local -n result_array=$3
    
    # Pulisci il contenuto dai null bytes
    page_content=$(printf '%s' "$page_content" | tr -d '\0')
    
    local base_url=$(echo "$url" | grep -oP 'https?://[^/]+')
    local base_domain=$(echo "$base_url" | sed 's|https\?://||')
    local base_domain_no_www=$(echo "$base_domain" | sed 's/^www\.//')
    local base_domain_with_www="www.$base_domain_no_www"
    
    # Reset dell'array
    result_array=()
    
    # Estrai tutti i link href e src (se assets inclusi)
    local raw_links
    if [[ $INCLUDE_ASSETS -eq 1 ]]; then
        # Includi sia href che src per assets completi
        local href_links=$(echo "${page_content}" | grep -oP 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')
        local src_links=$(echo "${page_content}" | grep -oP 'src="[^"]*"' | sed 's/src="//g' | sed 's/"//g')
        raw_links=$(printf "%s\n%s" "$href_links" "$src_links" | grep -v '^$')
    else
        # Solo href come prima
        raw_links=$(echo "${page_content}" | grep -oP 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')
    fi
    
    if [[ -n "$raw_links" ]]; then
        # Filtra via le estensioni di file solo se assets NON inclusi
        local filtered_links
        if [[ $INCLUDE_ASSETS -eq 1 ]]; then
            # Se assets inclusi, non filtrare le estensioni
            filtered_links="$raw_links"
        else
            # Se assets NON inclusi, filtra le estensioni come prima
            filtered_links=$(echo "$raw_links" | grep -vE '\.(css|js|jpg|jpeg|png|gif|svg|ico|woff|woff2|ttf|eot|pdf|zip|rar|tar|gz|mp3|mp4|avi|mov|webm|webp)(\?.*)?$')
        fi
        
        # Filtra per dominio e popola l'array (versione più permissiva)
        while IFS= read -r link; do
            [[ -n "$link" ]] || continue
            # Controlla per link relativi o domini del sito (inclusi sottodomini)
            if [[ "$link" =~ ^/ ]] || 
               [[ "$link" =~ ^https?://[^/]*$base_domain_no_www ]] || 
               [[ "$link" =~ ^https?://[^/]*$base_domain_with_www ]] || 
               [[ "$link" =~ $base_domain_no_www ]] || 
               [[ "$link" =~ $base_domain_with_www ]]; then
                result_array+=("$link")
            fi
        done <<< "$filtered_links"
        
        # Rimuovi duplicati usando sort (più veloce per molti elementi)
        if [[ ${#result_array[@]} -gt 0 ]]; then
            local unique_links
            IFS=$'\n' unique_links=($(printf '%s\n' "${result_array[@]}" | sort -u))
            result_array=("${unique_links[@]}")
        fi
    fi
}

#======================================
# FUNZIONI WORKER PARALLELI
#======================================

# Funzione per testare un URL in un processo separato
worker_test_url() {
    echo "[DEBUG] === WORKER $2 STARTED ===" >&2
    local url="$1"
    local worker_id="$2"
    local base_domain="$3"
    
    echo "[DEBUG] Worker $worker_id ricevuto URL: $url" >&2
    
    # Costruisci URL completo se necessario
    if [[ $url =~ ^/ ]]; then
        local base_url=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+')
        full_url="${base_url}${url}"
    else
        full_url="$url"
    fi

    # DEBUG: stampa il link che viene testato
    stdbuf -oL echo "[DEBUG][W${worker_id}] Testo link: $full_url"
    
    # Esegui la richiesta
    local page_result=$(http_request "$full_url" "false")
    
    # Rimuovi null bytes che possono causare problemi
    page_result=$(echo "$page_result" | tr -d '\0')
    
    # Gestisci timeout e errori
    if [[ "$page_result" == "ERROR" ]] || [[ -z "$page_result" ]]; then
        log_message "ERROR" "Worker-${worker_id}: $full_url ERROR" "$(log_get_filename "$URLVALUE")"
        echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [ERROR]"
    else
        # Parse delle metriche di performance
        declare -A metrics
        http_parse_metrics "$page_result" metrics
        
        # Controllo di sicurezza per status_code
        local status_code="${metrics[status_code]:-ERROR}"
        
        # Se il parsing delle metriche è fallito, gestisci in base al tipo di risorsa
        if [[ "$status_code" == "ERROR" ]] || [[ -z "$status_code" ]]; then
            # Identifica se è un asset o una pagina HTML
            if http_is_asset "$full_url"; then
                local asset_type=$(http_identify_asset_type "$full_url")
                log_message "INFO" "Worker-${worker_id}: $full_url OK ($asset_type downloaded)" "$(log_get_filename "$URLVALUE")"
                echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [ASSET_OK] $asset_type"
            else
                # Per pagine HTML, verifica se è un errore di connessione o semplicemente nessun link
                if [[ "$page_result" == "ERROR" ]]; then
                    log_message "ERROR" "Worker-${worker_id}: $full_url CONNECTION_ERROR" "$(log_get_filename "$URLVALUE")"
                    echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [CONNECTION_ERROR]"
                else
                    log_message "INFO" "Worker-${worker_id}: $full_url OK (no links found)" "$(log_get_filename "$URLVALUE")"
                    echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [NO_LINKS]"
                fi
            fi
        else
            local performance_msg=$(http_format_performance_log metrics "$full_url" "Worker-${worker_id}")
            
            # Log usando la funzione logger centralizzata con metriche
            local log_filename=$(log_get_filename "$URLVALUE")
            if [[ $status_code -ge 400 ]]; then
                log_message "ERROR" "$performance_msg" "$log_filename"
            elif [[ $status_code -ge 300 ]]; then
                log_message "WARNING" "$performance_msg" "$log_filename"
            else
                log_message "INFO" "$performance_msg" "$log_filename"
            fi
            
            # Output per il processo principale
            echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [${status_code}] ${metrics[time_total]:-0}s"
        fi
    fi
}

#======================================
# FUNZIONI DI GESTIONE PROCESSI
#======================================

# Funzione per gestire i job paralleli
process_manage_parallel_jobs() {
    echo "[DEBUG] === INIZIO process_manage_parallel_jobs ==="
    local max_jobs="$1"
    echo "[DEBUG] max_jobs ricevuto: '$max_jobs'"
    shift
    local urls=("$@")
    echo "[DEBUG] Numero di URL ricevuti: ${#urls[@]}"
    local -a pids=()
    local worker_id=1
    
    echo "[DEBUG] Avvio di ${#urls[@]} job con max $max_jobs processi paralleli"
    
    for url in "${urls[@]}"; do
        # Aspetta se abbiamo raggiunto il limite massimo di job
        while [[ ${#pids[@]} -ge $max_jobs ]]; do
            # Controlla quali processi sono ancora attivi
            local -a new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            pids=("${new_pids[@]}")
            
            # Se abbiamo ancora troppi processi, aspetta un po'
            if [[ ${#pids[@]} -ge $max_jobs ]]; then
                sleep 0.1
            fi
        done
        
        # Avvia nuovo job in background  
        echo "[DEBUG] Avvio worker $worker_id per URL: $url"
        worker_test_url "$url" "$worker_id" "$base_domain" &
        local new_pid=$!
        pids+=("$new_pid")
        echo "[DEBUG] Worker $worker_id avviato con PID: $new_pid"
        ((worker_id++))
        
        # Breve pausa tra i job per evitare sovraccarico
        sleep 0.05
    done
    
    echo "[DEBUG] Tutti i worker avviati. In attesa di ${#pids[@]} processi..."
    
    # Aspetta che tutti i job finiscano
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "[DEBUG] In attesa del PID: $pid"
            wait "$pid" 2>/dev/null || true
            echo "[DEBUG] PID $pid completato"
        fi
    done
    
    echo "[DEBUG] Tutti i processi worker completati"
}

#======================================
# FUNZIONI DI UTILITÀ
#======================================

util_show_help(){
    echo "=================================="
    echo "          TESTER ROBOT"
    echo "=================================="
    echo ""
    echo "DESCRIZIONE:"
    echo "  Script per il monitoraggio continuo di siti web con supporto"
    echo "  parallelo e seguimento automatico dei link trovati."
    echo ""
    echo "SINTASSI:"
    echo "  $0 [OPZIONI]"
    echo ""
    echo "OPZIONI:"
    echo "  -u URL           URL da testare (obbligatorio)"
    echo "  -d SECONDI       Delay tra le chiamate in secondi (default: 0.5)"
    echo "  -f               Segui tutti i link trovati nella pagina"
    echo "  -a               Includi assets (CSS, JS, immagini) nei test"
    echo "  -j NUMERO        Numero di processi paralleli (default: 1)"
    echo "  -t               Modalità test: mostra i link trovati ed esce"
    echo "  -h               Mostra questa guida"
    echo ""
    echo "OPZIONI AVANZATE:"
    echo "  --profile NOME   Usa profilo di configurazione predefinito"
    echo "  --list-profiles  Mostra tutti i profili disponibili"
    echo "  --help           Mostra questa guida (stesso di -h)"
    echo ""
    echo "ESEMPI:"
    echo "  # Test singolo"
    echo "  $0 -t -u https://example.com"
    echo ""
    echo "  # Monitoraggio continuo ogni 2 secondi"
    echo "  $0 -u https://example.com -d 2"
    echo ""
    echo "  # FOLLOW con 4 processi paralleli"
    echo "  $0 -f -j 4 -u https://example.com"
    echo ""
    echo "  # Stress test con 10 processi paralleli"
    echo "  $0 -j 10 -u https://example.com -d 0.1"
    echo ""
    echo "  # Performance test completo con assets inclusi"
    echo "  $0 -f -a -j 5 -u https://example.com"
    echo ""
    echo "  # Test assets per debugging performance"
    echo "  $0 -t -a -u https://example.com"
    echo ""
    echo "  # Usa profilo Laravel per testing applicazione"
    echo "  $0 --profile laravel -u https://mylaravelapp.com"
    echo ""
    echo "  # Usa profilo WordPress con follow links"
    echo "  $0 --profile wordpress -f -j 3 -u https://myblog.com"
    echo ""
    echo "  # Lista tutti i profili disponibili"
    echo "  $0 --list-profiles"
    echo ""

    echo "CONFIGURAZIONE:"
    echo "  File di configurazione: .headers.env (configurazione di base)"
    echo "  Directory profili: profiles/ (configurazioni predefinite)"
    echo "  • Headers HTTP personalizzabili per tipo di applicazione"
    echo "  • Token di autenticazione configurabili"
    echo "  • Profili ottimizzati per Laravel, WordPress, ecc."
    echo "  • Opzioni curl dinamiche per ogni profilo"
    echo "  • Usa --profile NOME per caricare configurazioni predefinite"
    echo ""
    echo "FUNZIONALITÀ:"
    echo "  • Estrazione automatica dei link dalla pagina"
    echo "  • Filtraggio configurabile di assets (CSS, JS, immagini) con opzione -a"
    echo "  • Filtraggio per mantenere solo i link del dominio principale"
    echo "  • Esecuzione parallela su più core CPU"
    echo "  • Logging centralizzato in formato: dominio-YYYY-MM-DD.log"
    echo "  • Gestione dinamica di autenticazione tramite file .headers.env"
    echo ""
    echo "LOGGING:"
    echo "  I risultati vengono salvati in:"
    echo "  logs/[dominio]-YYYY-MM-DD.log"
    echo ""
    echo "  Formato log: [TIMESTAMP] LEVEL [[MESSAGE]]"
    echo "  Livelli: DEBUG, INFO, WARNING, ERROR, CRITICAL"
    echo ""
    echo "CONTROLLI:"
    echo "  Ctrl+C        Termina lo script e tutti i processi paralleli"
    echo ""
    echo "AUTORE: Riccardo"
    echo "=================================="
}

#======================================
# FUNZIONE PRINCIPALE
#======================================

main() {
    if [[ $# -eq 0 ]]; then
        util_show_help
        exit 1
    fi
    
    # Gestione opzioni lunghe (prima di getopts)
    local args=("$@")
    local filtered_args=()
    local i=0
    
    while [[ $i -lt ${#args[@]} ]]; do
        case "${args[i]}" in
            --profile)
                if [[ $((i + 1)) -lt ${#args[@]} ]]; then
                    PROFILE="${args[$((i + 1))]}"
                    i=$((i + 2))
                else
                    echo "Errore: --profile richiede un valore"
                    exit 1
                fi
                ;;
            --profile=*)
                PROFILE="${args[i]#*=}"
                i=$((i + 1))
                ;;
            --list-profiles)
                echo "Profili disponibili:"
                config_list_profiles
                exit 0
                ;;
            --help)
                util_show_help
                exit 0
                ;;
            *)
                filtered_args+=("${args[i]}")
                i=$((i + 1))
                ;;
        esac
    done
    
    # Imposta i parametri filtrati per getopts
    set -- "${filtered_args[@]}"
    
    # Carica profilo se specificato (prima della configurazione standard)
    if [[ -n "$PROFILE" ]]; then
        config_load_profile "$PROFILE" || exit 1
    else
        # Carica la configurazione standard
        config_load_headers_env "$CONFIG_FILE"
    fi

    while getopts d:u:j:hfta OPTIONS; do
        case "${OPTIONS}" in
            h) HELP=1;;
            d) DELAY=${OPTARG};;
            u) URLVALUE=${OPTARG};;
            j) PARALLEL_JOBS=${OPTARG};;
            f) FOLLOW=1;;
            t) TEST=1;;
            a) INCLUDE_ASSETS=1;;
        esac
    done

    if [[ $HELP -eq 1 ]]; then
        util_show_help
        exit 0
    fi

    # Imposta valori di default (potenzialmente sovrascritti da .headers.env)
    DELAY=${DELAY:-$DEFAULT_DELAY}
    PARALLEL_JOBS=${PARALLEL_JOBS:-$DEFAULT_PARALLEL_JOBS}

    # Validazione URL obbligatorio
    if [[ -z "$URLVALUE" ]]; then
        echo "Errore: URL è obbligatorio. Usa -u per specificarlo."
        util_show_help
        exit 1
    fi

    # Setup del logging
    log_setup
    
    # Log delle informazioni di configurazione
    log_message "INFO" "Utilizzando curl per le richieste HTTP"
    
    if [[ -n "$PROFILE" ]]; then
        log_message "INFO" "Configurazione attiva: profilo '$PROFILE' (profiles/$PROFILE.env)"
    elif [[ -f "$CONFIG_FILE" ]]; then
        log_message "INFO" "Configurazione caricata da: $CONFIG_FILE"
    else
        log_message "INFO" "Usando configurazione di default (file $CONFIG_FILE non trovato)"
    fi
    
    # Configurazione dinamica degli headers HTTP basata sull'URL target
    http_setup_headers "$URLVALUE"

    if [[ $TEST -eq 1 ]]; then
        
        page=$(http_request "$URLVALUE" "true")
        
        # Pulisci caratteri problematici (null bytes e altri caratteri di controllo)
        page=$(printf '%s' "$page" | tr -d '\0' | LC_ALL=C tr -cd '\11\12\15\40-\176\200-\377')

        status_code=$(http_extract_status_code "$page")
        
        base_domain=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+' | sed 's|https\?://||')
        echo "Dominio rilevato: $base_domain"
        echo "Status code estratto: $status_code"
        
        links_array=()
        echo "Inizio estrazione link..."
        
        # Usa la funzione http_request per includere autenticazione
        local test_page=$(http_request "$URLVALUE" "true")
        local base_domain_check=$(echo "$URLVALUE" | sed 's|https\?://||' | sed 's|/.*||')
        local raw_links=$(echo "$test_page" | grep -oP 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')
        
        # Usa grep per filtrare direttamente
        local filtered_links=$(echo "$raw_links" | grep -E "^/|$base_domain_check")
        links_array=()
        while IFS= read -r link; do
            [[ -n "$link" ]] && links_array+=("$link")
        done <<< "$filtered_links"
        
        # Rimuovi duplicati velocemente
        if [[ ${#links_array[@]} -gt 0 ]]; then
            IFS=$'\n' links_array=($(printf '%s\n' "${links_array[@]}" | sort -u))
        fi
        
        echo "Estrazione completata. Link array size: ${#links_array[@]}"
    
    echo "=== ESTRAZIONE LINK ==="
    if [[ ${#links_array[@]} -gt 0 ]]; then
        echo "Link trovati (${#links_array[@]}):"
        printf '%s\n' "${links_array[@]}"
    else
        echo "Nessun link trovato nella pagina"
    fi
    echo "===================="
    echo "STATUS CODE: ${status_code}"
    exit 0
fi

echo "Ctrl+c per stoppare"
echo "Modalità parallela: $PARALLEL_JOBS processi"
echo "Usando: curl (client HTTP)"

    # Mostra il file di log utilizzato
    log_filename=$(log_get_filename "$URLVALUE")
    echo "Log file: $PWD/logs/$log_filename"

    # Funzione di cleanup per gestire Ctrl+C
    process_cleanup() {
        echo -e "\nTerminazione in corso..."
        kill $(jobs -p) 2>/dev/null
        exit 0
    }
    trap process_cleanup INT TERM

    while :; do
        # Testa URL principale
        page=$(http_request "$URLVALUE" "true")
        
        # Rimuovi null bytes che possono causare problemi
        page=$(echo "$page" | tr -d '\0')
        
        # Parse delle metriche di performance
        declare -A main_metrics
        http_parse_metrics "$page" main_metrics
        
        local status_code="${main_metrics[status_code]:-ERROR}"
        local performance_msg=$(http_format_performance_log main_metrics "$URLVALUE" "Main")
        
        # Log usando la funzione logger centralizzata con metriche
        log_file=$(log_get_filename "$URLVALUE")
        if [[ "$status_code" == "ERROR" ]] || [[ -z "$status_code" ]]; then
            # Verifica se è un errore di connessione o semplicemente nessun link
            if [[ "$page" == "ERROR" ]]; then
                log_message "ERROR" "Main: $URLVALUE CONNECTION_ERROR" "$log_file"
                echo -ne "$(date +"%Y%m%d.%H%M%S%3N") URL: $URLVALUE [CONNECTION_ERROR]  \033[0K\r"
            else
                log_message "INFO" "Main: $URLVALUE OK (no links found)" "$log_file"
                echo -ne "$(date +"%Y%m%d.%H%M%S%3N") URL: $URLVALUE [NO_LINKS]  \033[0K\r"
            fi
        else
            if [[ $status_code -ge 400 ]]; then
                log_message "ERROR" "$performance_msg" "$log_file"
            elif [[ $status_code -ge 300 ]]; then
                log_message "WARNING" "$performance_msg" "$log_file"
            else
                log_message "INFO" "$performance_msg" "$log_file"
            fi
            
            echo -ne "$(date +"%Y%m%d.%H%M%S%3N") URL: $URLVALUE [$status_code] ${main_metrics[time_total]:-0}s  \033[0K\r"
        fi
        
        # Se FOLLOW è attivo, testa i link in parallelo
        if [[ $FOLLOW -eq 1 ]]; then
            links_array=()
            http_extract_links "$page" "$URLVALUE" links_array
            
            if [[ ${#links_array[@]} -gt 0 ]]; then
                echo -e "\n[FOLLOW] Trovati ${#links_array[@]} link:"
                printf '  -> %s\n' "${links_array[@]}"
                echo "[FOLLOW] Testando ${#links_array[@]} link con $PARALLEL_JOBS processi paralleli..."
                
                # Esegui test paralleli sui link
                local base_domain=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+' | sed 's|https\?://||')
                echo "[DEBUG] Base domain estratto: '$base_domain'"
                echo "[DEBUG] Chiamata process_manage_parallel_jobs con $PARALLEL_JOBS job"
                process_manage_parallel_jobs "$PARALLEL_JOBS" "${links_array[@]}"
                local exit_code=$?
                echo "[DEBUG] process_manage_parallel_jobs terminato con exit code: $exit_code"
                
                echo "[FOLLOW] Test paralleli completati."
            else
                echo -e "\n[FOLLOW] Nessun link trovato nella pagina per il follow."
            fi
    fi
    
    # Se PARALLEL_JOBS > 1, crea processi paralleli per l'URL principale
    if [[ $PARALLEL_JOBS -gt 1 ]] && [[ $FOLLOW -eq 0 ]]; then
            echo -e "\n[PARALLEL] Avvio $PARALLEL_JOBS processi paralleli per URL principale..."
            
            # Crea array con l'URL principale ripetuto
            parallel_urls=()
            for ((i=1; i<=PARALLEL_JOBS; i++)); do
                parallel_urls+=("$URLVALUE")
            done
            
            base_domain=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+' | sed 's|https\?://||')
            process_manage_parallel_jobs "$PARALLEL_JOBS" "${parallel_urls[@]}"
            
            echo "[PARALLEL] Test paralleli completati."
        fi
        
        sleep $DELAY
    done
}

#======================================
# AVVIO SCRIPT
#======================================

# Esegui la funzione principale con tutti gli argomenti
main "$@"
