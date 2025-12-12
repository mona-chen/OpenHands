#!/bin/bash

set -e

echo "🚀 OpenHands Enterprise Remote Deployment"
echo "======================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Remote server configuration
REMOTE_SERVER=${REMOTE_SERVER:-""}
SSH_USER=${SSH_USER:-"root"}
SSH_KEY=${SSH_KEY:-""}
REMOTE_DIR=${REMOTE_DIR:-"/opt/openhands-enterprise"}

# Check if remote server is configured
if [ -z "$REMOTE_SERVER" ]; then
    print_error "Remote server not configured!"
    print_info "Please set environment variables:"
    echo "  export REMOTE_SERVER='your-server-ip'"
    echo "  export SSH_USER='your-ssh-user'"
    echo "  export SSH_KEY='/path/to/your/ssh-key'"
    echo "  export REMOTE_DIR='/deployment/directory'"
    echo ""
    print_info "Or run with:"
    echo "  REMOTE_SERVER=your-server-ip ./deploy-remote.sh"
    exit 1
fi

print_info "Deploying to remote server: $REMOTE_SERVER"
print_info "SSH User: $SSH_USER"
print_info "Remote Directory: $REMOTE_DIR"

# Create SSH command
SSH_CMD="ssh"
if [ -n "$SSH_KEY" ]; then
    SSH_CMD="$SSH_CMD -i $SSH_KEY"
fi
SSH_CMD="$SSH_CMD $SSH_USER@$REMOTE_SERVER"

# Function to execute command on remote server
remote_exec() {
    $SSH_CMD "$1"
}

# Function to copy files to remote server
remote_copy() {
    if [ -n "$SSH_KEY" ]; then
        scp -i $SSH_KEY -r "$1" $SSH_USER@$REMOTE_SERVER:$2
    else
        scp -r "$1" $SSH_USER@$REMOTE_SERVER:$2
    fi
}

print_info "Connecting to remote server and setting up environment..."

# Test SSH connection
print_info "Testing SSH connection..."
if ! $SSH_CMD "echo 'SSH connection successful'"; then
    print_error "SSH connection failed!"
    print_info "Please check:"
    echo "  - Server IP: $REMOTE_SERVER"
    echo "  - SSH user: $SSH_USER"
    echo "  - SSH key: $SSH_KEY"
    echo "  - Network connectivity"
    exit 1
fi

print_status "SSH connection successful"

# Create remote directory
print_info "Creating deployment directory on remote server..."
remote_exec "sudo mkdir -p $REMOTE_DIR && sudo chown $SSH_USER:$SSH_USER $REMOTE_DIR"

# Copy files to remote server
print_info "Copying deployment files to remote server..."
remote_copy ".env.enterprise.example" "$REMOTE_DIR/"
remote_copy "docker-compose.enterprise.yml" "$REMOTE_DIR/"
remote_copy "deploy.sh" "$REMOTE_DIR/"
remote_copy "nginx/" "$REMOTE_DIR/" 2>/dev/null || true
remote_copy "init-scripts/" "$REMOTE_DIR/" 2>/dev/null || true

# Create .env file on remote server if it doesn't exist
print_info "Setting up environment configuration..."
remote_exec "
cd $REMOTE_DIR
if [ ! -f .env ]; then
    cp .env.enterprise.example .env
    echo 'Created .env from template'
    echo 'Please edit .env file with your configuration:'
    echo '  - ZAI_API_KEY (your ZAI API key)'
    echo '  - POSTGRES_PASSWORD (secure database password)'
    echo '  - GITHUB_APP_CLIENT_ID (GitHub OAuth)'
    echo '  - GITHUB_APP_WEBHOOK_SECRET'
    echo '  - GITHUB_APP_PRIVATE_KEY'
    echo ''
    echo 'Edit with: nano $REMOTE_DIR/.env'
    echo 'Or set environment variables before deployment'
else
    echo '.env file already exists'
fi
"

# Check if .env is configured
print_info "Checking if .env is configured..."
ENV_CHECK=$(remote_exec "
cd $REMOTE_DIR
if grep -q 'your-zai-api-key-here' .env; then
    echo 'needs_config'
else
    echo 'configured'
fi
")

if [ "$ENV_CHECK" = "needs_config" ]; then
    print_warning ".env file needs configuration!"
    print_info "Please configure your ZAI API key and other settings:"
    echo ""
    echo "Edit on remote server:"
    echo "  ssh $SSH_USER@$REMOTE_SERVER 'nano $REMOTE_DIR/.env'"
    echo ""
    echo "Or configure locally and copy:"
    echo "  cp .env.enterprise.example .env"
    echo "  # Edit .env with your settings"
    echo "  scp -i $SSH_KEY .env $SSH_USER@$REMOTE_SERVER:$REMOTE_DIR/"
    echo ""
    read -p "Press Enter after configuring .env file, or 'q' to quit: " choice
    if [ "$choice" = "q" ]; then
        exit 0
    fi
fi

# Deploy on remote server
print_info "Starting deployment on remote server..."

# Execute deployment commands on remote server
remote_exec "
cd $REMOTE_DIR

# Stop existing services
echo 'Stopping existing services...'
docker compose -f docker-compose.enterprise.yml down 2>/dev/null || true

# Clean up old containers
echo 'Cleaning up old containers...'
docker system prune -f

# Build and start services
echo 'Building OpenHands Enterprise image...'
docker compose -f docker-compose.enterprise.yml build --no-cache

echo 'Starting services...'
docker compose -f docker-compose.enterprise.yml up -d

# Wait for services to be ready
echo 'Waiting for services to be ready...'
sleep 30

# Run database migrations
echo 'Running database migrations...'
docker compose -f docker-compose.enterprise.yml run --rm migrate

# Wait a bit more for application to start
echo 'Waiting for application to fully start...'
sleep 20

# Health checks
echo 'Performing health checks...'

# Check if main application is healthy
if curl -f http://localhost:3000/api/readiness > /dev/null 2>&1; then
    echo '✅ Main application is healthy'
else
    echo '❌ Main application health check failed'
fi

# Check if Nginx is responding
if curl -f http://localhost:80/health > /dev/null 2>&1; then
    echo '✅ Nginx reverse proxy is healthy'
else
    echo '❌ Nginx health check failed'
fi

# Check database connectivity
if docker compose -f docker-compose.enterprise.yml exec -T postgres pg_isready -U openhands_user -d openhands_enterprise > /dev/null 2>&1; then
    echo '✅ Database is healthy'
else
    echo '❌ Database health check failed'
fi

# Check Redis connectivity
if docker compose -f docker-compose.enterprise.yml exec -T redis redis-cli ping > /dev/null 2>&1; then
    echo '✅ Redis is healthy'
else
    echo '❌ Redis health check failed'
fi

# Display service status
echo ''
echo 'Service Status:'
docker compose -f docker-compose.enterprise.yml ps

echo ''
echo 'Access Information:'
echo '  🌐 Main Application: http://$REMOTE_SERVER:3000'
echo '  🔗 Nginx Proxy: http://$REMOTE_SERVER:80'
echo '  📊 Health Check: http://$REMOTE_SERVER:80/health'
echo '  📚 API Documentation: http://$REMOTE_SERVER:3000/docs'
echo ''
echo 'Useful Commands:'
echo '  📋 View logs: docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml logs -f openhands-enterprise'
echo '  🛠️  Enter container: docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml exec openhands-enterprise bash'
echo '  🔄 Restart services: docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml restart'
echo '  🛑 Stop services: docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml down'
echo '  🧹 Clean up: docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml down -v'
echo ''
echo '🔒 Telemetry Status:'
echo '  All external telemetry is DISABLED by default'
echo '  Only ZAI integration is active (if configured)'
echo ''
echo '🎉 OpenHands Enterprise deployed successfully on remote server!'
"

print_status "🎉 Remote deployment completed!"
echo ""
print_info "Access your OpenHands Enterprise at:"
echo "  🌐 http://$REMOTE_SERVER:3000"
echo "  🔗 http://$REMOTE_SERVER:80"
echo ""
print_info "To connect to the server for management:"
echo "  ssh $SSH_USER@$REMOTE_SERVER"
echo ""
print_info "To view logs in real-time:"
echo "  ssh $SSH_USER@$REMOTE_SERVER 'docker compose -f $REMOTE_DIR/docker-compose.enterprise.yml logs -f'"
echo ""
print_warning "Important Notes:"
echo "  🔒 All external telemetry is DISABLED by default"
echo "  🔑 ZAI integration is configured with your API key"
echo "  📝 Database migrations have been applied automatically"
echo "  🐳 All services are running in Docker containers"
echo "  🌐 Services are accessible via the server IP: $REMOTE_SERVER"
echo ""
print_info "For production deployment:"
echo "  1. Configure SSL certificates"
echo "  2. Update firewall rules (ports 80, 443, 3000)"
echo "  3. Set up regular backups"
echo "  4. Configure monitoring and alerting"
echo "  5. Set up log rotation"
echo ""
echo "🚀 Your remote OpenHands Enterprise is ready to use!"