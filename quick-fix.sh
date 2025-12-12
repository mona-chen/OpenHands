#!/bin/bash

set -e

echo "🔧 Quick Fix for OpenHands Enterprise Deployment"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

if [ -z "$REMOTE_SERVER" ]; then
    print_error "Remote server not configured!"
    print_info "Usage: REMOTE_SERVER=your-server-ip ./quick-fix.sh"
    exit 1
fi

print_info "Connecting to remote server: $REMOTE_SERVER"

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

print_info "Fixing Redis password issue..."

# Fix 1: Set REDIS_PASSWORD in environment
print_info "Setting REDIS_PASSWORD environment variable..."
remote_exec "
cd $REMOTE_DIR
# Set REDIS_PASSWORD for current session
export REDIS_PASSWORD='your_redis_password_here'

# Update .env file if it exists
if [ -f .env ]; then
    if grep -q '^REDIS_PASSWORD=' .env; then
        sed -i 's/^REDIS_PASSWORD=.*/REDIS_PASSWORD=your_redis_password_here/' .env
    else
        echo 'REDIS_PASSWORD=your_redis_password_here' >> .env
    fi
else
    cp .env.enterprise.example .env
    sed -i 's/your_redis_password_here/your_redis_password_here/' .env
fi

echo 'REDIS_PASSWORD set to: your_redis_password_here'
"

# Fix 2: Restart Redis service
print_info "Restarting Redis service..."
remote_exec "
cd $REMOTE_DIR
export REDIS_PASSWORD='your_redis_password_here'
docker compose -f docker-compose.enterprise.yml restart redis
sleep 10
"

# Fix 3: Check Redis health
print_info "Checking Redis health..."
REDIS_HEALTH=$(remote_exec "
cd $REMOTE_DIR
export REDIS_PASSWORD='your_redis_password_here'
if docker compose -f docker-compose.enterprise.yml exec redis redis-cli ping > /dev/null 2>&1; then
    echo 'healthy'
else
    echo 'unhealthy'
fi
")

if [ "$REDIS_HEALTH" = "healthy" ]; then
    print_status "Redis is now healthy!"
else
    print_error "Redis is still unhealthy"
    print_info "Manual Redis check:"
    echo "ssh $SSH_USER@$REMOTE_SERVER 'cd $REMOTE_DIR && docker compose -f docker-compose.enterprise.yml logs redis'"
fi

# Fix 4: Restart all services
print_info "Restarting all services..."
remote_exec "
cd $REMOTE_DIR
export REDIS_PASSWORD='your_redis_password_here'
docker compose -f docker-compose.enterprise.yml down
sleep 5
docker compose -f docker-compose.enterprise.yml up -d
sleep 30
"

# Fix 5: Run migrations
print_info "Running database migrations..."
remote_exec "
cd $REMOTE_DIR
export REDIS_PASSWORD='your_redis_password_here'
docker compose -f docker-compose.enterprise.yml run --rm migrate
"

# Fix 6: Final health check
print_info "Performing final health checks..."

# Check application health
APP_HEALTH=$(remote_exec "
cd $REMOTE_DIR
export REDIS_PASSWORD='your_redis_password_here'
if curl -f http://localhost:3000/api/readiness > /dev/null 2>&1; then
    echo 'healthy'
else
    echo 'unhealthy'
fi
")

if [ "$APP_HEALTH" = "healthy" ]; then
    print_status "Application is healthy!"
else
    print_error "Application is unhealthy"
fi

# Check database health
DB_HEALTH=$(remote_exec "
cd $REMOTE_DIR
export REDIS_PASSWORD='your_redis_password_here'
if docker compose -f docker-compose.enterprise.yml exec postgres pg_isready -U openhands_user -d openhands_enterprise > /dev/null 2>&1; then
    echo 'healthy'
else
    echo 'unhealthy'
fi
")

if [ "$DB_HEALTH" = "healthy" ]; then
    print_status "Database is healthy!"
else
    print_error "Database is unhealthy"
fi

# Check Redis health again
REDIS_HEALTH=$(remote_exec "
cd $REMOTE_DIR
export REDIS_PASSWORD='your_redis_password_here'
if docker compose -f docker-compose.enterprise.yml exec redis redis-cli ping > /dev/null 2>&1; then
    echo 'healthy'
else
    echo 'unhealthy'
fi
")

if [ "$REDIS_HEALTH" = "healthy" ]; then
    print_status "Redis is healthy!"
else
    print_error "Redis is still unhealthy"
fi

# Display final status
echo ""
print_info "Service Status:"
remote_exec "cd $REMOTE_DIR && export REDIS_PASSWORD='your_redis_password_here' && docker compose -f docker-compose.enterprise.yml ps"

echo ""
print_info "Access Information:"
echo "  🌐 Main Application: http://$REMOTE_SERVER:3000"
echo "  🔗 Nginx Proxy: http://$REMOTE_SERVER:80"
echo "  📊 Health Check: http://$REMOTE_SERVER:80/health"

echo ""
if [ "$APP_HEALTH" = "healthy" ] && [ "$DB_HEALTH" = "healthy" ] && [ "$REDIS_HEALTH" = "healthy" ]; then
    print_status "🎉 All services are healthy! Deployment successful!"
else
    print_warning "Some services may still need attention. Check logs above."
    print_info "To view logs:"
    echo "ssh $SSH_USER@$REMOTE_SERVER 'cd $REMOTE_DIR && docker compose -f docker-compose.enterprise.yml logs -f'"
fi

echo ""
print_info "To make this permanent, update your .env file:"
echo "ssh $SSH_USER@$REMOTE_SERVER 'cd $REMOTE_DIR && nano .env'"
echo ""
print_info "Change: REDIS_PASSWORD=your_redis_password_here"
echo "To any secure password you prefer."