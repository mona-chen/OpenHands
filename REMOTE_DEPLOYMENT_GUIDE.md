# OpenHands Enterprise Remote Deployment Guide

## Overview

This guide provides a complete solution for deploying OpenHands Enterprise on a remote Docker server with proper error handling, health checks, and troubleshooting.

## Prerequisites

### Remote Server Requirements
- **OS**: Ubuntu 20.04+ / CentOS 8+ / RHEL 8+
- **Docker**: 20.10+ with Docker Compose V2
- **Memory**: 8GB+ RAM
- **Storage**: 50GB+ available space
- **Network**: Ports 80, 443, 3000 accessible

### Local Machine Requirements
- SSH access to remote server
- SSH key (recommended) or password authentication

## Quick Start

### 1. Configure Remote Server Connection

```bash
# Set environment variables for your remote server
export REMOTE_SERVER="your-server-ip"
export SSH_USER="root"  # or your sudo user
export SSH_KEY="/path/to/your/ssh-key"  # optional, use password if not set
export REMOTE_DIR="/opt/openhands-enterprise"
```

### 2. One-Command Deployment

```bash
# Make deployment script executable
chmod +x deploy-remote.sh

# Deploy to remote server
./deploy-remote.sh
```

## Detailed Deployment Process

### Step 1: Remote Server Setup

The deployment script automatically handles:

1. **SSH Connection Testing**
2. **Directory Creation**
3. **File Transfer**
4. **Environment Configuration**
5. **Docker Service Management**
6. **Health Checks**
7. **Error Recovery**

### Step 2: Environment Configuration

The script creates `.env` from template if needed:

```bash
# Required Configuration
LLM_API_KEY="your-zai-api-key-here"
POSTGRES_PASSWORD="secure_database_password"

# Optional Enterprise Features
GITHUB_APP_CLIENT_ID="your-github-app-client-id"
GITHUB_APP_WEBHOOK_SECRET="your-webhook-secret"
GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."

# ZAI Configuration (Updated with correct endpoints)
LLM_MODEL="glm-4.6"
LLM_BASE_URL="https://api.z.ai/api/paas/v4/"
LLM_CUSTOM_LLM_PROVIDER="zai"
LLM_TEMPERATURE="0.6"
```

### Step 3: Docker Compose Configuration

The `docker-compose.enterprise.yml` includes fixes for common issues:

#### Database Improvements
- **Increased SHM**: `shm_size: 256mb` (prevents memory issues)
- **Extended Health Checks**: More retries and longer timeout
- **Proper Init Scripts**: Database initialization handled correctly

#### Redis Improvements
- **Password Handling**: Works with or without Redis password
- **Better Health Checks**: Proper ping command with authentication
- **Graceful Startup**: Handles configuration variations

#### Application Improvements
- **Dependency Management**: Proper service startup order
- **Health Check Delays**: Adequate time for services to initialize
- **Resource Limits**: Reasonable memory and CPU constraints

### Step 4: Service Management

The deployment script includes:

1. **Cleanup**: Removes old containers and images
2. **Build**: Fresh build without cache issues
3. **Startup**: Services start in correct order
4. **Migration**: Database schema updates applied
5. **Verification**: Comprehensive health checks

## Troubleshooting Common Issues

### Issue 1: Database Health Check Fails

**Symptoms**: PostgreSQL container shows unhealthy status

**Solutions**:
```bash
# Check database logs
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml logs postgres"

# Manual database check
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml exec postgres pg_isready -U openhands_user -d openhands_enterprise"

# Reset database if needed
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml down -v && docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml up -d postgres"
```

### Issue 2: Redis Health Check Fails

**Symptoms**: Redis container shows unhealthy status

**Solutions**:
```bash
# Check Redis logs
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml logs redis"

# Test Redis manually
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml exec redis redis-cli ping"

# Restart Redis service
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml restart redis"
```

### Issue 3: Application Fails to Start

**Symptoms**: OpenHands Enterprise container exits or shows errors

**Solutions**:
```bash
# Check application logs
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml logs openhands-enterprise"

# Check environment variables
ssh $SSH_USER@$REMOTE_SERVER "cd $REMOTE_DIR && cat .env"

# Rebuild application
ssh $SSH_USER@$REMOTE_SERVER "cd $REMOTE_DIR && docker compose -f docker-compose.enterprise.yml build --no-cache openhands-enterprise"
```

### Issue 4: Port Access Issues

**Symptoms**: Cannot access services via browser

**Solutions**:
```bash
# Check firewall status
ssh $SSH_USER@$REMOTE_SERVER "sudo ufw status"

# Open required ports
ssh $SSH_USER@$REMOTE_SERVER "sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw allow 3000/tcp"

# Check if ports are listening
ssh $SSH_USER@$REMOTE_SERVER "sudo netstat -tlnp | grep -E ':(80|443|3000)'"
```

## Advanced Configuration

### SSL/HTTPS Setup

For production deployment with SSL:

```bash
# On remote server, create SSL directory
ssh $SSH_USER@$REMOTE_SERVER "mkdir -p $REMOTE_DIR/ssl"

# Copy SSL certificates
scp -i $SSH_KEY ./ssl/cert.pem $SSH_USER@$REMOTE_SERVER:$REMOTE_DIR/ssl/
scp -i $SSH_KEY ./ssl/key.pem $SSH_USER@$REMOTE_SERVER:$REMOTE_DIR/ssl/

# Update Nginx configuration for HTTPS
ssh $SSH_USER@$REMOTE_SERVER "cd $REMOTE_DIR && sed -i 's/# return 301/return 301/' nginx/conf.d/default.conf"
ssh $SSH_USER@$REMOTE_SERVER "cd $REMOTE_DIR && sed -i 's/# server {/server {/' nginx/conf.d/default.conf"
ssh $SSH_USER@$REMOTE_SERVER "cd $REMOTE_DIR && sed -i 's/# }/}/' nginx/conf.d/default.conf"

# Restart Nginx
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml restart nginx"
```

### Performance Optimization

```bash
# Optimize Docker for production
ssh $SSH_USER@$REMOTE_SERVER "
# Optimize Docker daemon
echo '{
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"10m\",
    \"max-file\": \"3\"
  }
}' | sudo tee /etc/docker/daemon.json

# Restart Docker service
sudo systemctl restart docker

# Optimize system parameters
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
"
```

### Monitoring Setup

```bash
# Install monitoring tools
ssh $SSH_USER@$REMOTE_SERVER "
# Install basic monitoring
sudo apt update && sudo apt install -y htop iotop nethogs

# Create monitoring script
cat > $REMOTE_DIR/monitor.sh << 'EOF'
#!/bin/bash
echo \"=== OpenHands Enterprise Status ===\"
echo \"Time: \$(date)\"
echo \"\"
echo \"Container Status:\"
docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml ps
echo \"\"
echo \"Resource Usage:\"
echo \"Memory:\"
free -h
echo \"\"
echo \"Disk Usage:\"
df -h | grep -E '(/$|/opt)'
echo \"\"
echo \"Network Connections:\"
netstat -an | grep ESTABLISHED | wc -l
EOF

chmod +x $REMOTE_DIR/monitor.sh
"
```

## Security Hardening

### Basic Security

```bash
# Security hardening on remote server
ssh $SSH_USER@$REMOTE_SERVER "
# Update system
sudo apt update && sudo apt upgrade -y

# Configure firewall
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

# Disable root SSH (optional)
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Set up automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
"
```

### Backup Configuration

```bash
# Set up automated backups
ssh $SSH_USER@$REMOTE_SERVER "
# Create backup script
cat > $REMOTE_DIR/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=\"/opt/backups/openhands-enterprise\"
DATE=\$(date +%Y%m%d_%H%M%S)

mkdir -p \$BACKUP_DIR

# Backup volumes
docker run --rm -v openhands_postgres_data:/data -v \$BACKUP_DIR:/backup alpine tar czf /backup/postgres_\$DATE.tar.gz -C /data .
docker run --rm -v openhands_redis_data:/data -v \$BACKUP_DIR:/backup alpine tar czf /backup/redis_\$DATE.tar.gz -C /data .

# Backup configuration
cp $REMOTE_DIR/.env \$BACKUP_DIR/env_\$DATE
cp -r $REMOTE_DIR/nginx \$BACKUP_DIR/nginx_\$DATE

# Clean old backups (keep 7 days)
find \$BACKUP_DIR -name \"*.tar.gz\" -mtime +7 -delete
find \$BACKUP_DIR -name \"env_*\" -mtime +7 -delete
find \$BACKUP_DIR -name \"nginx_*\" -mtime +7 -delete

echo \"Backup completed: \$DATE\"
EOF

chmod +x $REMOTE_DIR/backup.sh

# Add to crontab for daily backups at 2 AM
(crontab -l 2>/dev/null; echo \"0 2 * * * $REMOTE_DIR/backup.sh\") | crontab -
"
```

## Service Management Commands

### Remote Management

```bash
# Connect to remote server
ssh $SSH_USER@$REMOTE_SERVER

# View real-time logs
docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml logs -f

# Enter application container
docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml exec openhands-enterprise bash

# Restart specific service
docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml restart postgres

# Scale services (if needed)
docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml up -d --scale openhands-enterprise=2
```

### Local Management Scripts

Create local management scripts for convenience:

```bash
# logs.sh - View remote logs
#!/bin/bash
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml logs -f openhands-enterprise"

# status.sh - Check service status
#!/bin/bash
ssh $SSH_USER@$REMOTE_SERVER "docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml ps"

# restart.sh - Restart services
#!/bin/bash
ssh $SSH_USER@$REMOTE_SERVER "cd $REMOTE_DIR && docker compose -f docker-compose.enterprise.yml restart"

# update.sh - Update and redeploy
#!/bin/bash
scp -i $SSH_KEY -r . $SSH_USER@$REMOTE_SERVER:$REMOTE_DIR/
ssh $SSH_USER@$REMOTE_SERVER "cd $REMOTE_DIR && docker compose -f docker-compose.enterprise.yml down && docker compose -f docker-compose.enterprise.yml up -d"
```

## Production Deployment Checklist

### Pre-Deployment
- [ ] Remote server meets requirements
- [ ] SSH access configured and tested
- [ ] Firewall rules configured
- [ ] SSL certificates obtained (if using HTTPS)
- [ ] Domain DNS configured
- [ ] Backup strategy planned
- [ ] Monitoring solution ready

### Post-Deployment
- [ ] All services healthy
- [ ] Database migrations applied
- [ ] ZAI integration working
- [ ] External access verified
- [ ] SSL certificate valid (if applicable)
- [ ] Monitoring active
- [ ] Backup schedule configured
- [ ] Log rotation configured
- [ ] Security hardening applied

## Emergency Procedures

### Full Service Recovery

```bash
# Complete service reset
ssh $SSH_USER@$REMOTE_SERVER "
cd $REMOTE_DIR
docker compose -f docker-compose.enterprise.yml down -v
docker system prune -af
docker compose -f docker-compose.enterprise.yml up -d
sleep 60
docker compose -f docker-compose.enterprise.yml run --rm migrate
"
```

### Data Recovery

```bash
# Restore from backup
ssh $SSH_USER@$REMOTE_SERVER "
BACKUP_DIR=\"/opt/backups/openhands-enterprise\"
LATEST_BACKUP=\$(ls -t \$BACKUP_DIR/postgres_*.tar.gz | head -1)

# Stop services
cd $REMOTE_DIR
docker compose -f docker-compose.enterprise.yml down

# Restore database
docker run --rm -v openhands_postgres_data:/data -v \$BACKUP_DIR:/backup alpine tar xzf \$LATEST_BACKUP -C /data

# Restart services
docker compose -f docker-compose.enterprise.yml up -d
"
```

## Support

### Debug Information Collection

```bash
# Collect comprehensive debug information
ssh $SSH_USER@$REMOTE_SERVER "
cd $REMOTE_DIR
echo '=== System Information ===' > debug-info.txt
date >> debug-info.txt
uname -a >> debug-info.txt
docker --version >> debug-info.txt
docker compose version >> debug-info.txt
echo '' >> debug-info.txt

echo '=== Service Status ===' >> debug-info.txt
docker compose -f docker-compose.enterprise.yml ps >> debug-info.txt
echo '' >> debug-info.txt

echo '=== Resource Usage ===' >> debug-info.txt
free -h >> debug-info.txt
df -h >> debug-info.txt
echo '' >> debug-info.txt

echo '=== Recent Logs ===' >> debug-info.txt
docker compose -f docker-compose.enterprise.yml logs --tail=50 openhands-enterprise >> debug-info.txt

echo 'Debug information saved to debug-info.txt'
"

# Download debug information
scp -i $SSH_KEY $SSH_USER@$REMOTE_SERVER:$REMOTE_DIR/debug-info.txt ./
```

This comprehensive remote deployment solution handles all the issues you encountered and provides a robust, production-ready deployment process for OpenHands Enterprise.