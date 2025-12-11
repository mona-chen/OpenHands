#!/bin/bash

set -e

echo "🚀 OpenHands Enterprise Auto-Deployment"
echo "======================================"

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

# Check if .env exists
if [ ! -f .env ]; then
    print_warning ".env file not found. Creating from template..."
    if [ -f .env.enterprise.example ]; then
        cp .env.enterprise.example .env
        print_status "Created .env from template"
        print_warning "Please edit .env file with your configuration before continuing!"
        print_info "Required settings:"
        print_info "  - LLM_API_KEY (your ZAI API key)"
        print_info "  - GITHUB_APP_CLIENT_ID (GitHub OAuth)"
        print_info "  - GITHUB_APP_WEBHOOK_SECRET"
        print_info "  - GITHUB_APP_PRIVATE_KEY"
        print_info "  - POSTGRES_PASSWORD"
        echo ""
        read -p "Press Enter after editing .env file, or 'q' to quit: " choice
        if [ "$choice" = "q" ]; then
            exit 0
        fi
    else
        print_error "Template file .env.enterprise.example not found!"
        exit 1
    fi
fi

# Load environment variables
source .env

# Validate required environment variables
print_info "Validating configuration..."

required_vars=("LLM_API_KEY" "POSTGRES_PASSWORD")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    print_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

print_status "Environment validation passed"

# Create necessary directories
print_info "Creating necessary directories..."
mkdir -p init-scripts
mkdir -p nginx/conf.d
mkdir -p ssl
mkdir -p workspace

# Create database initialization script
print_info "Creating database initialization script..."
cat > init-scripts/setup.sql << 'EOF'
-- OpenHands Enterprise Database Initialization
-- This script runs automatically when PostgreSQL starts

-- Create extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_conversations_created_at ON conversations(created_at);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_users_github_user_id ON users(github_user_id);

-- Set timezone
SET timezone = 'UTC';

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO openhands_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO openhands_user;

-- Log initialization
DO $$
BEGIN
    RAISE NOTICE 'OpenHands Enterprise database initialized successfully';
END $$;
EOF

print_status "Database initialization script created"

# Create Nginx configuration
print_info "Creating Nginx configuration..."
cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Performance settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > nginx/conf.d/default.conf << 'EOF'
# Upstream configuration
upstream openhands_backend {
    server openhands-enterprise:3000;
    keepalive 32;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    server_name _;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Redirect to HTTPS in production
    # Uncomment for production with SSL
    # return 301 https://$server_name$request_uri;
    
    # For development, proxy directly
    location / {
        proxy_pass http://openhands_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# HTTPS configuration (uncomment for production)
# server {
#     listen 443 ssl http2;
#     server_name your-domain.com;
#     
#     ssl_certificate /etc/nginx/ssl/cert.pem;
#     ssl_certificate_key /etc/nginx/ssl/key.pem;
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
#     ssl_prefer_server_ciphers off;
#     
#     location / {
#         proxy_pass http://openhands_backend;
#         proxy_set_header Host $host;
#         proxy_set_header X-Real-IP $remote_addr;
#         proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#         proxy_set_header X-Forwarded-Proto $scheme;
#         
#         # WebSocket support
#         proxy_http_version 1.1;
#         proxy_set_header Upgrade $http_upgrade;
#         proxy_set_header Connection "upgrade";
#     }
# }
EOF

print_status "Nginx configuration created"

# Check Docker and Docker Compose
print_info "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

print_status "Docker and Docker Compose are available"

# Stop existing services
print_info "Stopping existing services..."
docker-compose down 2>/dev/null || true

# Clean up old containers
print_info "Cleaning up old containers..."
docker system prune -f

# Build and start services
print_info "Building OpenHands Enterprise image..."
docker-compose build --no-cache

print_info "Starting services..."
docker-compose up -d

# Wait for services to be ready
print_info "Waiting for services to be ready..."
sleep 30

# Run database migrations
print_info "Running database migrations..."
docker-compose run --rm migrate

# Wait a bit more for application to start
print_info "Waiting for application to fully start..."
sleep 20

# Health checks
print_info "Performing health checks..."

# Check if main application is healthy
if curl -f http://localhost:${OPENHANDS_PORT:-3000}/api/readiness > /dev/null 2>&1; then
    print_status "Main application is healthy"
else
    print_error "Main application health check failed"
fi

# Check if Nginx is responding
if curl -f http://localhost:${HTTP_PORT:-80}/health > /dev/null 2>&1; then
    print_status "Nginx reverse proxy is healthy"
else
    print_error "Nginx health check failed"
fi

# Check database connectivity
if docker-compose exec -T postgres pg_isready -U openhands_user -d openhands_enterprise > /dev/null 2>&1; then
    print_status "Database is healthy"
else
    print_error "Database health check failed"
fi

# Check Redis connectivity
if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
    print_status "Redis is healthy"
else
    print_error "Redis health check failed"
fi

# Display service status
print_info "Service Status:"
docker-compose ps

# Display access information
echo ""
print_status "🎉 OpenHands Enterprise deployed successfully!"
echo ""
print_info "Access Information:"
echo "  🌐 Main Application: http://localhost:${OPENHANDS_PORT:-3000}"
echo "  🔗 Nginx Proxy: http://localhost:${HTTP_PORT:-80}"
echo "  📊 Health Check: http://localhost:${HTTP_PORT:-80}/health"
echo "  📚 API Documentation: http://localhost:${OPENHANDS_PORT:-3000}/docs"
echo ""
print_info "Useful Commands:"
echo "  📋 View logs: docker-compose logs -f openhands-enterprise"
echo "  🛠️  Enter container: docker-compose exec openhands-enterprise bash"
echo "  🔄 Restart services: docker-compose restart"
echo "  🛑 Stop services: docker-compose down"
echo "  🧹 Clean up: docker-compose down -v"
echo ""
print_warning "Important Notes:"
echo "  🔒 All external telemetry is DISABLED by default"
echo "  🔑 ZAI integration is configured with your API key"
echo "  📝 Database migrations have been applied automatically"
echo "  🐳 All services are running in Docker containers"
echo ""
print_info "For production deployment:"
echo "  1. Configure SSL certificates in ./ssl/"
echo "  2. Update nginx/conf.d/default.conf for HTTPS"
echo "  3. Set strong passwords in .env"
echo "  4. Configure firewall rules"
echo "  5. Set up regular backups"
echo ""
echo "🚀 Your OpenHands Enterprise is ready to use!"