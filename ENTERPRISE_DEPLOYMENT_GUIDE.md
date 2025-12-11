# OpenHands Enterprise Deployment Guide

## Overview

This guide covers deploying OpenHands Enterprise with all external telemetry disabled by default, ensuring complete data privacy and control. The enterprise module provides advanced features like OAuth authentication, multi-tenant support, and integrations while maintaining zero external data transmission.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Telemetry Control](#telemetry-control)
3. [Database Setup](#database-setup)
4. [Configuration](#configuration)
5. [Building the Enterprise Image](#building-the-enterprise-image)
6. [Deployment Options](#deployment-options)
7. [ZAI Code Plan Integration](#zai-code-plan-integration)
8. [Security Considerations](#security-considerations)
9. [Monitoring and Logging](#monitoring-and-logging)
10. [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements
- **CPU**: 4+ cores recommended
- **Memory**: 8GB+ RAM recommended
- **Storage**: 50GB+ available space
- **Docker**: 20.10+ with Docker Compose
- **PostgreSQL**: 13+ (if using external database)

### Required Services
- PostgreSQL database
- Redis (optional, for caching)
- GitHub App (for OAuth integration)
- SSL certificates (for production)

## Telemetry Control

### Default Configuration (Privacy-First)

All external telemetry is **DISABLED BY DEFAULT**:

```bash
# Disabled by default - no external data transmission
ENABLE_POSTHOG_TELEMETRY=false          # PostHog analytics
ENABLE_EXTERNAL_TELEMETRY=false          # ddtrace, posthog packages
ENABLE_PROMETHEUS_METRICS=false          # Prometheus metrics collection
ENABLE_DATADOG_TELEMETRY=false          # Datadog monitoring
ENABLE_TELEMETRY_INFRASTRUCTURE=false    # Telemetry database tables
```

### Enabling Your Own Analytics

If you want to enable your own analytics:

```bash
# Enable PostHog for your own analytics
ENABLE_POSTHOG_TELEMETRY=true
POSTHOG_CLIENT_KEY="your-posthog-key"

# Enable external monitoring packages
ENABLE_EXTERNAL_TELEMETRY=true

# Enable Prometheus metrics
ENABLE_PROMETHEUS_METRICS=true
```

### What Gets Controlled

| Component | Control Variable | Default | Data Sent |
|-----------|------------------|----------|-----------|
| PostHog Analytics | `ENABLE_POSTHOG_TELEMETRY` | `false` | User events, authentication |
| External Packages | `ENABLE_EXTERNAL_TELEMETRY` | `false` | ddtrace, posthog |
| Prometheus Metrics | `ENABLE_PROMETHEUS_METRICS` | `false` | System metrics |
| Datadog Monitoring | `ENABLE_DATADOG_TELEMETRY` | `false` | APM, logs |
| Telemetry Infrastructure | `ENABLE_TELEMETRY_INFRASTRUCTURE` | `false` | Database tables |

## Database Setup

### PostgreSQL Configuration

1. **Create Database**:
```sql
CREATE DATABASE openhands_enterprise;
CREATE USER openhands_user WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE openhands_enterprise TO openhands_user;
```

2. **Run Migrations**:
```bash
cd enterprise
alembic upgrade head
```

### Database URL Format
```bash
# Format: postgresql://user:password@host:port/database
DATABASE_URL="postgresql://openhands_user:secure_password@localhost:5432/openhands_enterprise"
```

### Migration Control

Telemetry migrations are controlled by `ENABLE_TELEMETRY_INFRASTRUCTURE`:
- `false` (default): Skips telemetry table creation
- `true`: Creates telemetry infrastructure tables

## Configuration

### Environment Configuration

Copy the example configuration:
```bash
cp .env.enterprise.example .env
```

### Required Configuration

#### GitHub OAuth Setup
1. **Create GitHub App**:
   - Go to GitHub Settings → Developer settings → GitHub Apps
   - Create new app with webhook URL: `https://your-domain.com/api/github/webhook`
   - Set permissions: Repository access (read/write)
   - Generate private key

2. **Configure Environment**:
```bash
GITHUB_APP_CLIENT_ID="your-github-app-client-id"
GITHUB_APP_WEBHOOK_SECRET="your-webhook-secret"
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"
```

#### Database Configuration
```bash
DATABASE_URL="postgresql://user:password@localhost:5432/openhands_enterprise"
```

### Optional Features

#### Billing Integration
```bash
ENABLE_BILLING=true
STRIPE_SECRET_KEY="sk_test_..."
STRIPE_WEBHOOK_SECRET="whsec_..."
```

#### Integrations
```bash
# Jira
ENABLE_JIRA=true
JIRA_CLIENT_ID="your-jira-client-id"

# GitLab
GITLAB_APP_CLIENT_ID="your-gitlab-client-id"

# Slack
SLACK_BOT_TOKEN="xoxb-..."
```

## Building the Enterprise Image

### Build Command
```bash
# Build with telemetry disabled (default)
docker build -f enterprise/Dockerfile -t openhands-enterprise:latest .

# Build with specific telemetry controls
docker build \
  --build-arg ENABLE_EXTERNAL_TELEMETRY=false \
  --build-arg ENABLE_PROMETHEUS_METRICS=false \
  -f enterprise/Dockerfile \
  -t openhands-enterprise:latest .
```

### Build Process
The Dockerfile:
1. Starts from base OpenHands image
2. Installs enterprise dependencies
3. Conditionally installs telemetry packages based on environment variables
4. Copies enterprise code
5. Sets up proper permissions

## Deployment Options

### Option 1: Docker Compose (Recommended for Development)

Create `docker-compose.yml`:
```yaml
version: '3.8'

services:
  openhands-enterprise:
    build:
      context: .
      dockerfile: enterprise/Dockerfile
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgresql://openhands_user:password@postgres:5432/openhands_enterprise
      - GITHUB_APP_CLIENT_ID=${GITHUB_APP_CLIENT_ID}
      - GITHUB_APP_WEBHOOK_SECRET=${GITHUB_APP_WEBHOOK_SECRET}
      - GITHUB_APP_PRIVATE_KEY=${GITHUB_APP_PRIVATE_KEY}
      - ENABLE_POSTHOG_TELEMETRY=false
      - ENABLE_EXTERNAL_TELEMETRY=false
      - ENABLE_PROMETHEUS_METRICS=false
    depends_on:
      - postgres
    volumes:
      - ./workspace:/app/workspace

  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: openhands_enterprise
      POSTGRES_USER: openhands_user
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

volumes:
  postgres_data:
```

Deploy:
```bash
docker-compose up -d
```

### Option 2: Kubernetes (Production)

Create `k8s-deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openhands-enterprise
spec:
  replicas: 3
  selector:
    matchLabels:
      app: openhands-enterprise
  template:
    metadata:
      labels:
        app: openhands-enterprise
    spec:
      containers:
      - name: openhands-enterprise
        image: openhands-enterprise:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: openhands-secrets
              key: database-url
        - name: GITHUB_APP_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: openhands-secrets
              key: github-client-id
        - name: ENABLE_POSTHOG_TELEMETRY
          value: "false"
        - name: ENABLE_EXTERNAL_TELEMETRY
          value: "false"
        - name: ENABLE_PROMETHEUS_METRICS
          value: "false"
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: openhands-enterprise-service
spec:
  selector:
    app: openhands-enterprise
  ports:
  - port: 80
    targetPort: 3000
  type: LoadBalancer
```

Deploy:
```bash
kubectl apply -f k8s-deployment.yaml
```

### Option 3: Standalone Docker

```bash
# Run with environment file
docker run -d \
  --name openhands-enterprise \
  -p 3000:3000 \
  --env-file .env \
  -v $(pwd)/workspace:/app/workspace \
  openhands-enterprise:latest
```

## ZAI Code Plan Integration

### Option 1: Environment Variables (Recommended)

```bash
# ZAI Configuration
export LLM_MODEL="zai-code-planner"
export LLM_API_KEY="your-zai-api-key"
export LLM_BASE_URL="https://api.zai-code.com/v1"
export LLM_CUSTOM_LLM_PROVIDER="zai"
```

### Option 2: Configuration File

Create or update `config.toml`:
```toml
[llm]
model = "zai-code-planner"
api_key = "your-zai-api-key"
base_url = "https://api.zai-code.com/v1"
custom_llm_provider = "zai"
temperature = 0.1
max_input_tokens = 128000
max_output_tokens = 4096

[llm.zai]
# ZAI-specific configuration
model = "zai-code-planner"
api_key = "your-zai-api-key"
base_url = "https://api.zai-code.com/v1"
custom_llm_provider = "zai"
```

### Option 3: Runtime Configuration

The enterprise module supports runtime LLM configuration through the web interface:

1. Navigate to Settings → LLM Configuration
2. Set Model: `zai-code-planner`
3. Set API Key: `your-zai-api-key`
4. Set Base URL: `https://api.zai-code.com/v1`
5. Set Custom Provider: `zai`

### ZAI Integration Testing

Test your ZAI configuration:
```bash
# Test configuration loading
python -c "
from openhands.core.config import load_openhands_config
config = load_openhands_config()
llm_config = config.get_llm_config()
print(f'Model: {llm_config.model}')
print(f'Base URL: {llm_config.base_url}')
print(f'API Key set: {llm_config.api_key is not None}')
print(f'Custom Provider: {llm_config.custom_llm_provider}')
"
```

### ZAI Model Registration

To register ZAI models in the system, add them to:
```python
# openhands/utils/llm.py
SUPPORTED_MODELS = [
    # ... existing models ...
    "zai-code-planner",
    "zai/gpt-4",
    "zai/claude-sonnet",
]
```

## Security Considerations

### API Key Management

1. **Use Kubernetes Secrets**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: openhands-secrets
type: Opaque
data:
  github-client-id: <base64-encoded>
  github-webhook-secret: <base64-encoded>
  github-private-key: <base64-encoded>
  database-url: <base64-encoded>
  zai-api-key: <base64-encoded>
```

2. **Use Docker Secrets** (Swarm mode):
```yaml
version: '3.7'
services:
  openhands-enterprise:
    secrets:
      - github_client_id
      - github_webhook_secret
      - zai_api_key
    environment:
      GITHUB_APP_CLIENT_ID: /run/secrets/github_client_id
      GITHUB_APP_WEBHOOK_SECRET: /run/secrets/github_webhook_secret
      LLM_API_KEY: /run/secrets/zai_api_key

secrets:
  github_client_id:
    external: true
  github_webhook_secret:
    external: true
  zai_api_key:
    external: true
```

### Network Security

1. **Firewall Rules**:
```bash
# Only allow necessary ports
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw enable
```

2. **SSL/TLS Configuration**:
```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Container Security

1. **Non-root User**: Enterprise Dockerfile runs as `openhands` user
2. **Read-only Filesystem**: Consider adding `--read-only` flag with tmpfs mounts
3. **Resource Limits**: Set memory and CPU limits
4. **Security Scanning**: Regular vulnerability scans

## Monitoring and Logging

### Internal Monitoring (No External Transmission)

With telemetry disabled, you can still monitor locally:

1. **Application Logs**:
```bash
# View logs
docker logs openhands-enterprise

# Follow logs
docker logs -f openhands-enterprise
```

2. **Health Checks**:
```bash
# Readiness check
curl http://localhost:3000/api/readiness

# Liveness check
curl http://localhost:3000/api/health
```

3. **Local Metrics** (if enabled):
```bash
# Enable local Prometheus metrics
ENABLE_PROMETHEUS_METRICS=true

# Access metrics
curl http://localhost:3000/internal/metrics/
```

### Log Management

Configure log levels and outputs:
```bash
# Log level configuration
LOG_LEVEL="INFO"  # DEBUG, INFO, WARNING, ERROR

# Log format
LOG_FORMAT="json"  # json, text
```

## Troubleshooting

### Common Issues

1. **Database Connection Errors**:
```bash
# Check database connectivity
docker exec -it openhands-enterprise python -c "
from sqlalchemy import create_engine
engine = create_engine('postgresql://user:pass@host:5432/db')
print(engine.execute('SELECT 1').scalar())
"
```

2. **GitHub OAuth Issues**:
```bash
# Verify GitHub App configuration
curl -H "Authorization: Bearer $GITHUB_JWT" \
     https://api.github.com/app
```

3. **ZAI Integration Issues**:
```bash
# Test ZAI API connectivity
curl -H "Authorization: Bearer $ZAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"zai-code-planner","messages":[{"role":"user","content":"test"}]}' \
     https://api.zai-code.com/v1/chat/completions
```

### Debug Mode

Enable debug logging:
```bash
DEBUG=true
LOG_LEVEL="DEBUG"
```

### Performance Issues

1. **Resource Monitoring**:
```bash
# Container resource usage
docker stats openhands-enterprise

# System resources
htop
iostat -x 1
```

2. **Database Performance**:
```sql
-- Check active connections
SELECT * FROM pg_stat_activity;

-- Check slow queries
SELECT query, mean_time, calls 
FROM pg_stat_statements 
ORDER BY mean_time DESC 
LIMIT 10;
```

## Production Checklist

### Pre-Deployment
- [ ] All telemetry controls set to `false`
- [ ] Database migrations applied
- [ ] GitHub OAuth configured and tested
- [ ] ZAI credentials tested
- [ ] SSL certificates configured
- [ ] Firewall rules configured
- [ ] Backup strategy implemented
- [ ] Monitoring setup (internal)
- [ ] Log rotation configured

### Post-Deployment
- [ ] Verify all services are running
- [ ] Test authentication flow
- [ ] Test ZAI integration
- [ ] Verify no external connections (except ZAI)
- [ ] Performance baseline established
- [ ] Documentation updated

## Support

For issues with:
- **Enterprise Features**: Check enterprise module logs
- **ZAI Integration**: Verify API credentials and connectivity
- **Database Issues**: Check PostgreSQL logs and migrations
- **Authentication**: Verify GitHub App configuration

Remember: With default telemetry settings, no data is transmitted to external services except your explicitly configured integrations (like ZAI).