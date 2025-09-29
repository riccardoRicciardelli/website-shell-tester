# Tester Robot 🤖

**Website Monitoring Tool with Parallel Processing**

Version: 2.0.0  
Author: Riccardo

## 📋 Description

Tester Robot is a powerful Bash script designed for continuous website monitoring with advanced features including parallel processing, automatic link following, and comprehensive logging. Perfect for stress testing, availability monitoring, and automated quality assurance.

## ✨ Features

- **Parallel Processing**: Execute multiple concurrent requests using configurable worker processes
- **Link Following**: Automatically discover and test all links found on target pages
- **Smart Filtering**: Automatically filters out static resources (CSS, JS, images, etc.)
- **Domain Filtering**: Tests only links belonging to the target domain
- **Authentication Support**: Built-in support for XSRF tokens and session cookies
- **Comprehensive Logging**: Structured logging with multiple severity levels
- **Real-time Monitoring**: Live status updates with timestamps
- **Graceful Shutdown**: Proper cleanup of all background processes with Ctrl+C

## 🚀 Installation

1. Clone or download the script:
```bash
wget https://path-to-your-script/tester_robot.sh
# or
git clone <repository-url>
cd tester-robot
```

2. Make it executable:
```bash
chmod +x tester_robot.sh
```

3. Ensure required dependencies are installed:
```bash
# curl (usually pre-installed on most systems)
sudo apt-get install curl  # Ubuntu/Debian
# or
sudo yum install curl      # CentOS/RHEL
```

## 📖 Usage

### Basic Syntax
```bash
./tester_robot.sh [OPTIONS]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-u URL` | Target URL to test (required) | - |
| `-d SECONDS` | Delay between requests in seconds | 0.5 |
| `-f` | Follow all links found on the page | disabled |
| `-j NUMBER` | Number of parallel processes | 1 |
| `-t` | Test mode: show found links and exit | disabled |
| `-h` | Show help message | - |

### Examples

#### Single URL Test
```bash
./tester_robot.sh -t -u https://example.com
```

#### Continuous Monitoring
```bash
./tester_robot.sh -u https://example.com -d 2
```

#### Follow Links with Parallel Processing
```bash
./tester_robot.sh -f -j 4 -u https://example.com
```

#### Stress Testing
```bash
./tester_robot.sh -j 10 -u https://example.com -d 0.1
```

## 📊 Logging

### Log Files
Logs are automatically saved in the `logs/` directory with the format:
```
logs/[domain]-YYYY-MM-DD.log
```

### Log Format
```
[TIMESTAMP] LEVEL [[MESSAGE]]
```

### Log Levels
- **DEBUG**: Detailed debugging information
- **INFO**: General information and successful requests
- **WARNING**: 3xx HTTP status codes
- **ERROR**: 4xx/5xx HTTP status codes and connection errors
- **CRITICAL**: System-level errors

### Sample Log Output
```
[2025-09-29T10:30:15] INFO [[Main: https://example.com 200]]
[2025-09-29T10:30:15] INFO [[Worker-1: https://example.com/about 200]]
[2025-09-29T10:30:16] ERROR [[Worker-2: https://example.com/missing 404]]
```

## 🔧 Configuration

### HTTP Headers
The script uses realistic browser headers to avoid detection:
- User-Agent: Chrome 140.0.0.0
- Accept headers for HTML, images, and other content types
- Security headers (Sec-Fetch-*)
- Dynamic Referer based on target domain

### Authentication
Built-in support for:
- XSRF tokens
- Session cookies
- Custom authentication headers

Edit the script to modify these constants:
```bash
readonly XSRF_TOKEN="your_token_here"
readonly SESSION_TOKEN="your_session_token_here"
```

## 🏗️ Architecture

### Core Components

1. **HTTP Request Engine**: Uses `curl` for reliable HTTP requests
2. **Link Extractor**: Parses HTML to find and filter relevant links
3. **Parallel Worker Manager**: Manages concurrent request execution
4. **Logging System**: Centralized logging with multiple output levels
5. **Process Manager**: Handles background processes and cleanup

### Workflow

1. **Initialization**: Setup logging, configure headers, validate parameters
2. **Main Loop**: Test primary URL continuously with specified delay
3. **Link Discovery**: Extract and filter links from page content (if `-f` enabled)
4. **Parallel Execution**: Distribute tests across worker processes
5. **Result Logging**: Record all results with timestamps and status codes

## 🎯 Use Cases

### Website Monitoring
```bash
# Monitor site availability every 30 seconds
./tester_robot.sh -u https://mysite.com -d 30
```

### Load Testing
```bash
# Stress test with 20 concurrent connections
./tester_robot.sh -j 20 -u https://mysite.com -d 0.1
```

### Site Crawling
```bash
# Test all discoverable links
./tester_robot.sh -f -j 5 -u https://mysite.com
```

### Quality Assurance
```bash
# Test mode to check for broken links
./tester_robot.sh -t -f -u https://mysite.com
```

## ⚠️ Important Notes

### Performance Considerations
- Start with low parallel job counts (1-5) and increase gradually
- Monitor system resources when using high concurrency
- Adjust delays to respect target server capabilities

### Responsible Usage
- Respect robots.txt and terms of service
- Use appropriate delays to avoid overwhelming target servers
- Monitor your requests to avoid being blocked

### Network Requirements
- Stable internet connection
- Proper DNS resolution for target domains
- Firewall rules allowing outbound HTTP/HTTPS traffic

## 🐛 Troubleshooting

### Common Issues

**"ERROR" status codes in output**
- Check network connectivity
- Verify URL accessibility
- Review authentication tokens if required

**High CPU usage**
- Reduce parallel job count (`-j` parameter)
- Increase delay between requests (`-d` parameter)

**Permission denied errors**
- Ensure script has execute permissions: `chmod +x tester_robot.sh`
- Check write permissions for logs directory

**No links found in test mode**
- Verify the target page contains HTML links
- Check if authentication is required

## 📝 Development

### Requirements
- Bash 4.0+
- curl
- Standard Unix utilities (grep, sed, awk)

### Code Structure
- Strict error handling with `set -euo pipefail`
- Modular function organization
- Comprehensive error handling and logging
- Signal handling for graceful shutdown

## 📄 License

This project is provided as-is for educational and monitoring purposes. Use responsibly and in accordance with target website terms of service.

## 🤝 Contributing

Feel free to submit issues, feature requests, or improvements. Please ensure any contributions maintain the existing code style and include appropriate documentation.

---

**⚡ Quick Start:**
```bash
chmod +x tester_robot.sh
./tester_robot.sh -u https://example.com -t
```

For more information, use: `./tester_robot.sh -h`