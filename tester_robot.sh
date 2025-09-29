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
URLVALUE=""

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
        
        # Pulisci key e value
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | sed 's/#.*//' | sed 's/^"//;s/"$//' | xargs)
        
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
    
    # Esegui la richiesta
    curl -s "$url" "${curl_options[@]}" 2>/dev/null || echo "ERROR"
}

#======================================
# FUNZIONI HTTP
#======================================

#======================================
# FUNZIONI DI ANALISI METRICHE
#======================================

http_parse_metrics() {
    local response="$1"
    local -n metrics_result=$2
    
    # Inizializza l'array associativo
    declare -A temp_metrics
    
    # Estrai la riga delle metriche e parseala usando awk
    local metrics_line=$(echo "$response" | grep "^METRICS||" | tail -n1)
    
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
    status_code=$(echo "${page_content}" | head -n 1 | grep -oP "[0-9]{3}")
    echo "$status_code"
}

http_extract_links() {
    local page_content="$1"
    local url="$2"
    local -n result_array=$3
    
    local base_domain=$(echo "$url" | grep -oP 'https?://[^/]+' | sed 's|https\?://||')
    
    # Reset dell'array
    result_array=()
    
    # Estrai tutti i link href
    local raw_links
    raw_links=$(echo "${page_content}" | grep -oP 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')
    
    if [[ -n "$raw_links" ]]; then
        # Filtra via le estensioni di file
        local filtered_links
        filtered_links=$(echo "$raw_links" | grep -vE '\.(css|js|jpg|jpeg|png|gif|svg|ico|woff|woff2|ttf|eot|pdf|zip|rar|tar|gz|mp3|mp4|avi|mov|webm|webp)(\?.*)?$')
        
        # Filtra per dominio e popola l'array rimuovendo duplicati
        declare -A seen_links
        while IFS= read -r link; do
            if [[ -n "$link" ]] && [[ $link =~ ^(/|$base_domain|https?://$base_domain) ]]; then
                # Normalizza il link per il controllo duplicati
                local normalized_link="$link"
                
                # Converte link relativi in assoluti per normalizzazione
                if [[ $link =~ ^/ ]]; then
                    local base_url=$(echo "$url" | grep -oP 'https?://[^/]+')
                    normalized_link="${base_url}${link}"
                fi
                
                # Aggiungi solo se non già visto
                if [[ -z "${seen_links[$normalized_link]:-}" ]]; then
                    seen_links["$normalized_link"]=1
                    result_array+=("$link")
                fi
            fi
        done <<< "$filtered_links"
    fi
}

#======================================
# FUNZIONI WORKER PARALLELI
#======================================

# Funzione per testare un URL in un processo separato
worker_test_url() {
    local url="$1"
    local worker_id="$2"
    local base_domain="$3"
    
    # Costruisci URL completo se necessario
    if [[ $url =~ ^/ ]]; then
        local base_url=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+')
        full_url="${base_url}${url}"
    else
        full_url="$url"
    fi
    
    # Esegui la richiesta
    local page_result=$(http_request "$full_url" "false")
    
    # Gestisci timeout e errori
    if [[ "$page_result" == "ERROR" ]] || [[ -z "$page_result" ]]; then
        log_message "ERROR" "Worker-${worker_id}: $full_url ERROR" "$(log_get_filename "$URLVALUE")"
        echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [ERROR]"
    else
        # Parse delle metriche di performance
        declare -A metrics
        http_parse_metrics "$page_result" metrics
        
        local status_code="${metrics[status_code]}"
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
        echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [${status_code}] ${metrics[time_total]}s"
    fi
}

#======================================
# FUNZIONI DI GESTIONE PROCESSI
#======================================

# Funzione per gestire i job paralleli
process_manage_parallel_jobs() {
    local max_jobs="$1"
    shift
    local urls=("$@")
    local -a pids=()
    local worker_id=1
    
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
        worker_test_url "$url" "$worker_id" "$base_domain" &
        pids+=("$!")
        ((worker_id++))
        
        # Breve pausa tra i job per evitare sovraccarico
        sleep 0.05
    done
    
    # Aspetta che tutti i job finiscano
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
        fi
    done
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
    echo "  -u URL        URL da testare (obbligatorio)"
    echo "  -d SECONDI    Delay tra le chiamate in secondi (default: 0.5)"
    echo "  -f            Segui tutti i link trovati nella pagina"
    echo "  -j NUMERO     Numero di processi paralleli (default: 1)"
    echo "  -t            Modalità test: mostra i link trovati ed esce"
    echo "  -h            Mostra questa guida"
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

    echo "CONFIGURAZIONE:"
    echo "  File di configurazione: .headers.env"
    echo "  • Headers HTTP personalizzabili"
    echo "  • Token di autenticazione configurabili"
    echo "  • Opzioni curl dinamiche"
    echo "  • Copia .headers.env per personalizzare la configurazione"
    echo ""
    echo "FUNZIONALITÀ:"
    echo "  • Estrazione automatica dei link dalla pagina"
    echo "  • Filtraggio di file CSS, JS, immagini e risorse statiche"
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
    
    # Carica la configurazione prima di processare gli argomenti
    config_load_headers_env "$CONFIG_FILE"

    while getopts d:u:j:hft OPTIONS; do
        case "${OPTIONS}" in
            h) HELP=1;;
            d) DELAY=${OPTARG};;
            u) URLVALUE=${OPTARG};;
            j) PARALLEL_JOBS=${OPTARG};;
            f) FOLLOW=1;;
            t) TEST=1;;
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
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_message "INFO" "Configurazione caricata da: $CONFIG_FILE"
    else
        log_message "INFO" "Usando configurazione di default (file $CONFIG_FILE non trovato)"
    fi
    
    # Configurazione dinamica degli headers HTTP basata sull'URL target
    http_setup_headers "$URLVALUE"

    if [[ $TEST -eq 1 ]]; then
        
        page=$(http_request "$URLVALUE" "true")

        status_code=$(http_extract_status_code "$page")
        
        base_domain=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+' | sed 's|https\?://||')
        echo "Dominio rilevato: $base_domain"
        
        links_array=()
        http_extract_links "$page" "$URLVALUE" links_array
    
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
        
        # Parse delle metriche di performance
        declare -A main_metrics
        http_parse_metrics "$page" main_metrics
        
        local status_code="${main_metrics[status_code]}"
        local performance_msg=$(http_format_performance_log main_metrics "$URLVALUE" "Main")
        
        # Log usando la funzione logger centralizzata con metriche
        log_file=$(log_get_filename "$URLVALUE")
        if [[ $status_code -ge 400 ]]; then
            log_message "ERROR" "$performance_msg" "$log_file"
        elif [[ $status_code -ge 300 ]]; then
            log_message "WARNING" "$performance_msg" "$log_file"
        else
            log_message "INFO" "$performance_msg" "$log_file"
        fi
        
        echo -ne "$(date +"%Y%m%d.%H%M%S%3N") URL: $URLVALUE [$status_code] ${main_metrics[time_total]}s  \033[0K\r"
        
        # Se FOLLOW è attivo, testa i link in parallelo
        if [[ $FOLLOW -eq 1 ]]; then
            links_array=()
            http_extract_links "$page" "$URLVALUE" links_array
            
            if [[ ${#links_array[@]} -gt 0 ]]; then
                echo -e "\n[FOLLOW] Testando ${#links_array[@]} link con $PARALLEL_JOBS processi paralleli..."
                
                # Esegui test paralleli sui link
                base_domain=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+' | sed 's|https\?://||')
                process_manage_parallel_jobs "$PARALLEL_JOBS" "${links_array[@]}"
                
                echo "[FOLLOW] Test paralleli completati."
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
