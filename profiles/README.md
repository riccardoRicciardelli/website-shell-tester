# Profili di Configurazione - Tester Robot

I profili di configurazione permettono di utilizzare impostazioni ottimizzate per diversi tipi di applicazioni web senza dover configurare manualmente tutti i parametri.

## 📁 Profili Disponibili

### `generic` - Profilo Generico
- **Uso**: Applicazioni web standard, siti statici, API REST
- **Caratteristiche**: Configurazione bilanciata e compatibile
- **Timeout**: 10s connessione, 30s totale
- **Jobs paralleli**: 2 (conservativo)
- **Delay**: 1.0s tra richieste

```bash
./tester_robot.sh --profile generic -u https://mywebsite.com
```

### `laravel` - Laravel/Filament
- **Uso**: Applicazioni Laravel, Filament Admin Panel
- **Caratteristiche**: Support per CSRF tokens, Livewire, headers moderni
- **Timeout**: 10s connessione, 45s totale
- **Jobs paralleli**: 2 (ottimizzato per Laravel)
- **Delay**: 1.0s tra richieste
- **Log Level**: DEBUG (per sviluppo)

```bash
./tester_robot.sh --profile laravel -f -j 3 -u https://mylaravelapp.com
```

### `wordpress` - WordPress/WooCommerce
- **Uso**: Siti WordPress, WooCommerce, blog
- **Caratteristiche**: Headers per plugin comuni, cache headers, WP REST API
- **Timeout**: 15s connessione, 60s totale
- **Jobs paralleli**: 3 (WordPress può essere più lento)
- **Delay**: 2.0s tra richieste (più gentile)
- **Log Level**: INFO

```bash
./tester_robot.sh --profile wordpress -f -a -u https://myblog.com
```

## 🛠️ Come Creare un Profilo Personalizzato

1. **Copia il template**:
   ```bash
   cp templates/custom-template.env profiles/mio-profilo.env
   ```

2. **Personalizza i valori** nel file `profiles/mio-profilo.env`

3. **Usa il profilo**:
   ```bash
   ./tester_robot.sh --profile mio-profilo -u https://myapp.com
   ```

## 📋 Esempi di Uso

### Testing Laravel con autenticazione
```bash
# 1. Configura tokens nel profilo
vim profiles/laravel.env
# Imposta XSRF_TOKEN e SESSION_TOKEN

# 2. Testa con autenticazione
./tester_robot.sh --profile laravel -f -j 2 -u https://admin.myapp.com
```

### Testing WordPress con assets
```bash
# Test completo includendo CSS, JS, immagini
./tester_robot.sh --profile wordpress -f -a -j 3 -u https://myblog.com
```

### Stress test generico
```bash
# Test di carico con profilo generico
./tester_robot.sh --profile generic -j 10 -d 0.5 -u https://api.myservice.com
```

## 🔧 Parametri Principali dei Profili

| Parametro | Generic | Laravel | WordPress | Descrizione |
|-----------|---------|---------|-----------|-------------|
| `CONNECT_TIMEOUT` | 10s | 10s | 15s | Timeout connessione |
| `MAX_TIME` | 30s | 45s | 60s | Timeout totale richiesta |
| `DEFAULT_DELAY` | 1.0s | 1.0s | 2.0s | Delay tra richieste |
| `DEFAULT_PARALLEL_JOBS` | 2 | 2 | 3 | Jobs paralleli default |
| `MIN_LOG_LEVEL` | INFO | DEBUG | INFO | Livello logging |
| `INSECURE` | false | false | false | SSL verificato |

## 🎯 Quando Usare Quale Profilo

### Usa `generic` quando:
- Testi API REST standard
- Siti web semplici
- Non conosci la tecnologia specifica
- Vuoi iniziare con impostazioni sicure

### Usa `laravel` quando:
- Testi applicazioni Laravel
- Usi Filament Admin Panel
- Hai bisogno di CSRF token support
- Lavori con Livewire components

### Usa `wordpress` quando:
- Testi siti WordPress
- Lavori con WooCommerce
- Ti serve compatibilità con plugin comuni
- Il sito potrebbe essere più lento

## 💡 Suggerimenti

1. **Inizia sempre con il profilo più specifico** per la tua applicazione
2. **Personalizza i timeout** se la tua app è particolarmente lenta o veloce
3. **Usa log DEBUG** durante lo sviluppo, INFO in produzione
4. **Crea profili personalizzati** per le tue app più utilizzate
5. **Condividi profili** con il team per standardizzare i test

## 🔍 Debug

Per vedere esattamente quali headers vengono inviati:
```bash
./tester_robot.sh --profile laravel -t -u https://httpbin.org/headers
```

Per vedere tutti i profili disponibili:
```bash
./tester_robot.sh --list-profiles
```