#!/bin/bash
#======================================
# LITE ROBOT - Simple Website Testing Tool
# Author: Riccardo
# Version: 1.0.0
#======================================

set -euo pipefail  # Strict mode

#======================================
# CONFIGURAZIONE E COSTANTI
#======================================

readonly SCRIPT_NAME="lite_robot"
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_DIR="logs"
readonly CONFIG_FILE=".headers.env"

# Valori di default
DEFAULT_DELAY=0.5
DEFAULT_PARALLEL_JOBS=1
MIN_LOG_LEVEL="INFO"

# Variabili per autenticazione (caricate da .headers.env)
# Formato supportato: "nome_cookie=valore" o solo "valore" (legacy)
XSRF_TOKEN=""
SESSION_TOKEN=""

# Variabili per headers HTTP (caricate da headers.env)
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

# Array dinamico per gli headers HTTP
declare -a HTTP_HEADERS=()

#======================================
# VARIABILI GLOBALI
#======================================

# Variabili di configurazione runtime
DOMAIN=""
LOG_FILE=""
DELAY=$DEFAULT_DELAY
PARALLEL_JOBS=$DEFAULT_PARALLEL_JOBS

# Variabili per le opzioni della riga di comando
HELP=0
FOLLOW=0
TEST=0
INCLUDE_ASSETS=0
URLVALUE=""

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
    
    # Carica la configurazione
    while IFS='=' read -r key value; do
        # Ignora commenti e righe vuote
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        
        # Pulisci key e value
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

#======================================
# FUNZIONI DI LOGGING
#======================================

log_message() {
    local LEVEL="$1"
    local MESSAGE="$2"
    local FILENAME="${3:-$(log_get_filename "$URLVALUE")}"
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
    
    # Popola l'array HTTP_HEADERS
    HTTP_HEADERS=()
    
    # Aggiungi headers solo se definiti
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
    
    # Aggiungi il header Referer
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
    
    # Costruisci opzioni curl
    local curl_options=()
    
    # Timeout options
    curl_options+=(--connect-timeout "$CONNECT_TIMEOUT")
    curl_options+=(--max-time "$MAX_TIME")
    
    # Metriche di performance
    curl_options+=(--write-out "METRICS||%{http_code}||%{time_total}||%{time_connect}||%{time_starttransfer}||%{size_download}||%{speed_download}||%{url_effective}\n")
    
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
    
    # Cookies per autenticazione
    local cookie_string=""
    
    # Se i token contengono già il nome del cookie (formato: nome=valore), usali direttamente
    if [[ -n "$XSRF_TOKEN" ]]; then
        if [[ "$XSRF_TOKEN" == *"="* ]]; then
            # Formato: XSRF-TOKEN=eyJ... (con nome incluso)
            cookie_string+="${XSRF_TOKEN};"
        else
            # Formato legacy: solo valore
            cookie_string+="XSRF-TOKEN=${XSRF_TOKEN};"
        fi
    fi
    
    if [[ -n "$SESSION_TOKEN" ]]; then
        if [[ "$SESSION_TOKEN" == *"="* ]]; then
            # Formato: tera_pa_session=eyJ... (con nome incluso)
            cookie_string+=" ${SESSION_TOKEN};"
        else
            # Formato legacy: solo valore
            cookie_string+=" tera_pa_session=${SESSION_TOKEN};"
        fi
    fi
    
    [[ -n "$cookie_string" ]] && curl_options+=(-b "${cookie_string%;}")
    
    # Esegui la richiesta
    curl -s "$url" "${curl_options[@]}" 2>/dev/null | tr -d '\0' || echo "ERROR"
}

http_parse_metrics() {
    local response="$1"
    local -n metrics_result=$2
    
    # Inizializza l'array associativo
    declare -A temp_metrics
    
    # Estrai la riga delle metriche
    local clean_response=$(echo "$response" | tr -d '\0')
    local metrics_line=$(echo "$clean_response" | grep "^METRICS||" | tail -n1)
    
    if [[ -n "$metrics_line" ]]; then
        temp_metrics["status_code"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $2}')
        temp_metrics["time_total"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $3}')
        temp_metrics["time_connect"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $4}')
        temp_metrics["time_starttransfer"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $5}')
        temp_metrics["size_download"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $6}')
        temp_metrics["speed_download"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $7}')
        temp_metrics["url_effective"]=$(echo "$metrics_line" | awk -F'\\|\\|' '{print $8}')
    else
        # Valori di default
        temp_metrics["status_code"]="ERROR"
        temp_metrics["time_total"]="0"
        temp_metrics["time_connect"]="0"
        temp_metrics["time_starttransfer"]="0"
        temp_metrics["size_download"]="0"
        temp_metrics["speed_download"]="0"
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
    
    # Converti i valori per lettura più facile
    local time_total_ms=$(echo "$time_total" | awk '{printf "%.0f", $1 * 1000}')
    local time_connect_ms=$(echo "$time_connect" | awk '{printf "%.0f", $1 * 1000}')
    local time_starttransfer_ms=$(echo "$time_starttransfer" | awk '{printf "%.0f", $1 * 1000}')
    local size_kb=$(echo "$size_download" | awk '{printf "%.1f", $1 / 1024}')
    local speed_kbps=$(echo "$speed_download" | awk '{printf "%.1f", $1 / 1024}')
    
    # Formato del messaggio di log
    local performance_msg="${worker_id}: ${url} [${status_code}] ${time_total_ms}ms (conn:${time_connect_ms}ms ttfb:${time_starttransfer_ms}ms) ${size_kb}KB @${speed_kbps}KB/s"
    
    echo "$performance_msg"
}

http_extract_status_code() {
    local page_content="$1"
    
    # Estrai status code dalla riga METRICS
    local clean_content=$(printf '%s' "$page_content" | tr -d '\0')
    local metrics_line=$(printf '%s' "$clean_content" | grep "^METRICS||" | tail -n1)
    
    if [[ -n "$metrics_line" ]]; then
        echo "$metrics_line" | awk -F'\\|\\|' '{print $2}'
    else
        if [[ "$page_content" == "ERROR" ]]; then
            echo "ERROR"
        else
            echo "200"
        fi
    fi
}

http_extract_links() {
    local page_content="$1"
    local url="$2"
    local -n result_array=$3
    
    # Pulisci il contenuto
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
        local href_links=$(echo "${page_content}" | grep -oP 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')
        local src_links=$(echo "${page_content}" | grep -oP 'src="[^"]*"' | sed 's/src="//g' | sed 's/"//g')
        raw_links=$(printf "%s\n%s" "$href_links" "$src_links" | grep -v '^$')
    else
        raw_links=$(echo "${page_content}" | grep -oP 'href="[^"]*"' | sed 's/href="//g' | sed 's/"//g')
    fi
    
    if [[ -n "$raw_links" ]]; then
        # Filtra estensioni se assets NON inclusi
        local filtered_links
        if [[ $INCLUDE_ASSETS -eq 1 ]]; then
            filtered_links="$raw_links"
        else
            filtered_links=$(echo "$raw_links" | grep -vE '\.(css|js|jpg|jpeg|png|gif|svg|ico|woff|woff2|ttf|eot|pdf|zip|rar|tar|gz|mp3|mp4|avi|mov|webm|webp)(\?.*)?$')
        fi
        
        # Filtra per dominio
        while IFS= read -r link; do
            [[ -n "$link" ]] || continue
            if [[ "$link" =~ ^/ ]] || 
               [[ "$link" =~ ^https?://[^/]*$base_domain_no_www ]] || 
               [[ "$link" =~ ^https?://[^/]*$base_domain_with_www ]] || 
               [[ "$link" =~ $base_domain_no_www ]] || 
               [[ "$link" =~ $base_domain_with_www ]]; then
                result_array+=("$link")
            fi
        done <<< "$filtered_links"
        
        # Rimuovi duplicati
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

worker_test_url() {
    local url="$1"
    local worker_id="$2"
    
    # Costruisci URL completo se necessario
    if [[ $url =~ ^/ ]]; then
        local base_url=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+')
        full_url="${base_url}${url}"
    else
        full_url="$url"
    fi

    # Esegui la richiesta
    local page_result=$(http_request "$full_url" "false")
    page_result=$(echo "$page_result" | tr -d '\0')
    
    if [[ "$page_result" == "ERROR" ]] || [[ -z "$page_result" ]]; then
        log_message "ERROR" "Worker-${worker_id}: $full_url ERROR" "$(log_get_filename "$URLVALUE")"
        echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [ERROR]"
    else
        # Parse delle metriche
        declare -A metrics
        http_parse_metrics "$page_result" metrics
        
        local status_code="${metrics[status_code]:-ERROR}"
        
        if [[ "$status_code" == "ERROR" ]] || [[ -z "$status_code" ]]; then
            if [[ "$page_result" == "ERROR" ]]; then
                log_message "ERROR" "Worker-${worker_id}: $full_url CONNECTION_ERROR" "$(log_get_filename "$URLVALUE")"
                echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [CONNECTION_ERROR]"
            else
                log_message "INFO" "Worker-${worker_id}: $full_url OK" "$(log_get_filename "$URLVALUE")"
                echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [OK]"
            fi
        else
            local performance_msg=$(http_format_performance_log metrics "$full_url" "Worker-${worker_id}")
            
            local log_filename=$(log_get_filename "$URLVALUE")
            if [[ $status_code -ge 400 ]]; then
                log_message "ERROR" "$performance_msg" "$log_filename"
            elif [[ $status_code -ge 300 ]]; then
                log_message "WARNING" "$performance_msg" "$log_filename"
            else
                log_message "INFO" "$performance_msg" "$log_filename"
            fi
            
            echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [${status_code}] ${metrics[time_total]:-0}s"
        fi
    fi
}

process_manage_parallel_jobs() {
    local max_jobs="$1"
    shift
    local urls=("$@")
    local -a pids=()
    local worker_id=1
    
    for url in "${urls[@]}"; do
        # Aspetta se abbiamo raggiunto il limite
        while [[ ${#pids[@]} -ge $max_jobs ]]; do
            local -a new_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            pids=("${new_pids[@]}")
            
            if [[ ${#pids[@]} -ge $max_jobs ]]; then
                sleep 0.1
            fi
        done
        
        # Avvia nuovo job
        worker_test_url "$url" "$worker_id" &
        local new_pid=$!
        pids+=("$new_pid")
        ((worker_id++))
        
        sleep 0.05
    done
    
    # Aspetta che tutti finiscano
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
    echo "          LITE ROBOT"
    echo "=================================="
    echo ""
    echo "DESCRIZIONE:"
    echo "  Script semplificato per il monitoraggio di siti web"
    echo "  Versione lite senza profili e template complessi"
    echo ""
    echo "SINTASSI:"
    echo "  $0 [OPZIONI]"
    echo ""
    echo "OPZIONI:"
    echo "  -u URL           URL da testare (obbligatorio)"
    echo "  -d SECONDI       Delay tra le chiamate (default: 0.5)"
    echo "  -f               Segui tutti i link trovati nella pagina"
    echo "  -a               Includi assets (CSS, JS, immagini)"
    echo "  -j NUMERO        Numero di processi paralleli (default: 1)"
    echo "  -t               Modalità test: mostra i link ed esce"
    echo "  -h               Mostra questa guida"
    echo ""
    echo "ESEMPI:"
    echo "  # Test singolo"
    echo "  $0 -t -u https://example.com"
    echo ""
    echo "  # Monitoraggio continuo"
    echo "  $0 -u https://example.com -d 2"
    echo ""
    echo "  # Follow con processi paralleli"
    echo "  $0 -f -j 4 -u https://example.com"
    echo ""
    echo "CONFIGURAZIONE:"
    echo "  File: .headers.env (configurazione headers HTTP e autenticazione)"
    echo "  • Headers HTTP personalizzabili"
    echo "  • Cookie di autenticazione con nome parametrizzabile"
    echo "  • Formato cookie: NOME_COOKIE=valore (es: XSRF_TOKEN=\"XSRF-TOKEN=abc123\")"
    echo "  • Supporto formato legacy: solo valore"
    echo ""
    echo "LOGGING:"
    echo "  I risultati vengono salvati in: logs/[dominio]-YYYY-MM-DD.log"
    echo ""
    echo "CONTROLLI:"
    echo "  Ctrl+C        Termina lo script"
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
    
    # Carica la configurazione dal file headers.env
    config_load_headers_env "$CONFIG_FILE"

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

    # Imposta valori di default
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
    log_message "INFO" "Lite Robot avviato - Configurazione da: $CONFIG_FILE"
    
    # Configurazione headers HTTP
    http_setup_headers "$URLVALUE"

    if [[ $TEST -eq 1 ]]; then
        page=$(http_request "$URLVALUE" "true")
        page=$(printf '%s' "$page" | tr -d '\0' | LC_ALL=C tr -cd '\11\12\15\40-\176\200-\377')

        status_code=$(http_extract_status_code "$page")
        
        base_domain=$(echo "$URLVALUE" | grep -oP 'https?://[^/]+' | sed 's|https\?://||')
        echo "Dominio rilevato: $base_domain"
        echo "Status code estratto: $status_code"
        
        links_array=()
        echo "Inizio estrazione link..."
        
        http_extract_links "$page" "$URLVALUE" links_array
        
        echo "Estrazione completata. Link trovati: ${#links_array[@]}"
    
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

    # Cleanup function per Ctrl+C
    process_cleanup() {
        echo -e "\nTerminazione in corso..."
        kill $(jobs -p) 2>/dev/null
        exit 0
    }
    trap process_cleanup INT TERM

    while :; do
        # Testa URL principale
        page=$(http_request "$URLVALUE" "true")
        page=$(echo "$page" | tr -d '\0')
        
        # Parse delle metriche
        declare -A main_metrics
        http_parse_metrics "$page" main_metrics
        
        local status_code="${main_metrics[status_code]:-ERROR}"
        local performance_msg=$(http_format_performance_log main_metrics "$URLVALUE" "Main")
        
        # Log usando la funzione logger centralizzata
        log_file=$(log_get_filename "$URLVALUE")
        if [[ "$status_code" == "ERROR" ]] || [[ -z "$status_code" ]]; then
            if [[ "$page" == "ERROR" ]]; then
                log_message "ERROR" "Main: $URLVALUE CONNECTION_ERROR" "$log_file"
                echo -ne "$(date +"%Y%m%d.%H%M%S%3N") URL: $URLVALUE [CONNECTION_ERROR]  \033[0K\r"
            else
                log_message "INFO" "Main: $URLVALUE OK" "$log_file"
                echo -ne "$(date +"%Y%m%d.%H%M%S%3N") URL: $URLVALUE [OK]  \033[0K\r"
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
                echo "[FOLLOW] Testando ${#links_array[@]} link con $PARALLEL_JOBS processi..."
                
                process_manage_parallel_jobs "$PARALLEL_JOBS" "${links_array[@]}"
                
                echo "[FOLLOW] Test paralleli completati."
            else
                echo -e "\n[FOLLOW] Nessun link trovato nella pagina."
            fi
        fi
    
        # Se PARALLEL_JOBS > 1, processi paralleli per URL principale
        if [[ $PARALLEL_JOBS -gt 1 ]] && [[ $FOLLOW -eq 0 ]]; then
            echo -e "\n[PARALLEL] Avvio $PARALLEL_JOBS processi paralleli..."
            
            # Array con URL principale ripetuto
            parallel_urls=()
            for ((i=1; i<=PARALLEL_JOBS; i++)); do
                parallel_urls+=("$URLVALUE")
            done
            
            process_manage_parallel_jobs "$PARALLEL_JOBS" "${parallel_urls[@]}"
            
            echo "[PARALLEL] Test paralleli completati."
        fi
        
        sleep $DELAY
    done
}

#======================================
# AVVIO SCRIPT
#======================================

main "$@"