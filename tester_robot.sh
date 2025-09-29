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
readonly DEFAULT_DELAY=0.5
readonly DEFAULT_PARALLEL_JOBS=1
readonly LOG_DIR="logs"

# autenticazione
readonly XSRF_TOKEN="eyJpdiI6ImZXNE9CdjBob1B0bUEvbzZuSDRnTWc9PSIsInZhbHVlIjoiZmZzYnl3Z01hZ0xHOHBHai9sRlhVR1I2NlpzMGRGdzFRbHdySFYrbU9FNGpVMXFLdEM0YXJNNFdERlREYTZPQXVpMGoxbnFuUExBVTBOSVpoYkM3UHdvMm01b05zWnNlU0pLQ0dGSlRpSnFScUFWbzZ0aDVTdEZPclA3VkYxOTIiLCJtYWMiOiI4OTY5ZTRkZTljOWVlMTZiNTY3ODEyMjIxMzA1NDNlNDI3MmRmZWY2YTk1YmJjYzBkYjA1NmZiMmY1YTg4NzY5IiwidGFnIjoiIn0%3D"
readonly SESSION_TOKEN="eyJpdiI6IkZSN2V0QzZaK3VNM0E1WlRSNE1SOVE9PSIsInZhbHVlIjoiaHdtQzkzcWFmUnR5d0VLMlNrU1J3NklHYVJGb1BRdSsxRHVpSlMzZ1g0RjVFK21TU2hHbjRHKzdkUGl1U0J1bmkrdm1RVDBneWFQMzcxZWsyVHp2NTM0SFA0SHpWYzhEMWRyVkZBSFRZZW12TnFKZE5FS3VnZDIvQnlvcjZMUmEiLCJtYWMiOiI3MjVhOWVmYzZiMmQ4NzRmMWEyMmU4YzM0NTdlZjZhZGUxMDljNzU2ZDI0NDlmMjUzNTY4YjBhNjk1YTcwZjkxIiwidGFnIjoiIn0%3D"

# logging
MIN_LOG_LEVEL="INFO"  # DEBUG, INFO, WARNING, ERROR, CRITICAL

# REFERER_URL sarà impostato dinamicamente basato sull'URL target
REFERER_URL=""

# Template per headers HTTP (aggiornati con i valori dalla tua richiesta)
readonly -a HTTP_HEADERS_TEMPLATE=(
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    "Accept-Encoding: gzip, deflate, br, zstd"
    "Accept-Language: it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7"
    "Connection: keep-alive"
    "Sec-Fetch-Dest: document"
    "Sec-Fetch-Mode: navigate"
    "Sec-Fetch-Site: same-origin"
    "Sec-Fetch-User: ?1"
    "Upgrade-Insecure-Requests: 1"
    "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    "sec-ch-ua: \"Chromium\";v=\"140\", \"Not=A?Brand\";v=\"24\", \"Google Chrome\";v=\"140\""
    "sec-ch-ua-mobile: ?0"
    "sec-ch-ua-platform: \"Windows\""
)

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
    REFERER_URL="$base_domain/"
    
    # Popola l'array HTTP_HEADERS con il referer dinamico
    HTTP_HEADERS=()
    for header in "${HTTP_HEADERS_TEMPLATE[@]}"; do
        HTTP_HEADERS+=("$header")
    done
    
    # Aggiungi il header Referer con il dominio corretto
    HTTP_HEADERS+=("Referer: $REFERER_URL")
    
    log_message "DEBUG" "Headers configurati con Referer: $REFERER_URL"
}

http_request() {
    local url="$1"
    local use_headers="${2:-true}"
    
    # Usa curl per tutte le richieste HTTP
    if [[ "$use_headers" == "true" ]]; then
        local curl_headers=()
        for header in "${HTTP_HEADERS[@]}"; do
            curl_headers+=("-H" "$header")
        done
        
        curl -kfis "$url" \
            --connect-timeout 10 \
            --max-time 30 \
            "${curl_headers[@]}" \
            -b "XSRF-TOKEN=${XSRF_TOKEN}; tera_pa_session=${SESSION_TOKEN}" 2>/dev/null || echo "ERROR"
    else
        curl -kfis "$url" \
            --connect-timeout 10 \
            --max-time 30 \
            -b "XSRF-TOKEN=${XSRF_TOKEN}; tera_pa_session=${SESSION_TOKEN}" 2>/dev/null || echo "ERROR"
    fi
}

#======================================
# FUNZIONI HTTP
#======================================

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
        status_code="ERROR"
        log_message "ERROR" "Worker-${worker_id}: $full_url ERROR" "$(log_get_filename "$URLVALUE")"
    else
        local status_code=$(http_extract_status_code "$page_result")
        
        # Log usando la funzione logger centralizzata
        local log_filename=$(log_get_filename "$URLVALUE")
        if [[ $status_code -ge 400 ]]; then
            log_message "ERROR" "Worker-${worker_id}: $full_url $status_code" "$log_filename"
        elif [[ $status_code -ge 300 ]]; then
            log_message "WARNING" "Worker-${worker_id}: $full_url $status_code" "$log_filename"
        else
            log_message "INFO" "Worker-${worker_id}: $full_url $status_code" "$log_filename"
        fi
    fi
    
    # Output per il processo principale
    echo "$(date +"%Y%m%d.%H%M%S%3N") [W${worker_id}] $full_url [$status_code]"
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

    echo "FUNZIONALITÀ:"
    echo "  • Estrazione automatica dei link dalla pagina"
    echo "  • Filtraggio di file CSS, JS, immagini e risorse statiche"
    echo "  • Filtraggio per mantenere solo i link del dominio principale"
    echo "  • Esecuzione parallela su più core CPU"
    echo "  • Logging centralizzato in formato: dominio-YYYY-MM-DD.log"
    echo "  • Gestione di autenticazione con XSRF token e cookie di sessione"
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
    
    # Log del tool utilizzato
    log_message "INFO" "Utilizzando curl per le richieste HTTP"
    
    # Configurazione dinamica degli headers HTTP basata sull'URL target
    http_setup_headers "$URLVALUE"
    
    # Preparazione headers per curl
    local curl_headers=()
    for header in "${HTTP_HEADERS[@]}"; do
        curl_headers+=("-H" "$header")
    done

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
        status_code=$(http_extract_status_code "$page")
        
        # Log usando la funzione logger centralizzata
        log_file=$(log_get_filename "$URLVALUE")
        if [[ $status_code -ge 400 ]]; then
            log_message "ERROR" "Main: $URLVALUE $status_code" "$log_file"
        elif [[ $status_code -ge 300 ]]; then
            log_message "WARNING" "Main: $URLVALUE $status_code" "$log_file"
        else
            log_message "INFO" "Main: $URLVALUE $status_code" "$log_file"
        fi
        
        echo -ne "$(date +"%Y%m%d.%H%M%S%3N") URL: $URLVALUE statuscode $status_code  \033[0K\r"
        
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
