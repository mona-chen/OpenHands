# ZAI Code Plan Integration Guide

## Overview

This guide explains how to integrate ZAI Code Plan credentials with OpenHands Enterprise. ZAI provides specialized code planning and generation capabilities that can be seamlessly integrated into the OpenHands platform.

## Prerequisites

- ZAI Code Plan API credentials
- OpenHands Enterprise deployment
- Network access to ZAI API endpoints

## ZAI Integration Methods

### Method 1: Environment Variables (Recommended)

Set these environment variables in your `.env` file or deployment configuration:

```bash
# ZAI Configuration (using OpenAI-compatible SDK)
LLM_MODEL="glm-4.6"
LLM_API_KEY="your-zai-api-key-here"
LLM_BASE_URL="https://api.z.ai/api/paas/v4/"
LLM_CUSTOM_LLM_PROVIDER="zai"

# Optional ZAI-specific settings
LLM_TEMPERATURE="0.6"
LLM_MAX_INPUT_TOKENS="128000"
LLM_MAX_OUTPUT_TOKENS="4096"

# For coding-specific tasks, you can also use:
# LLM_MODEL="glm-4.5" (balanced performance)
# LLM_MODEL="glm-4.32b-0414-128k" (large context)
```

### Method 2: Configuration File

Add to your `config.toml`:

```toml
[llm]
model = "glm-4.6"
api_key = "your-zai-api-key-here"
base_url = "https://api.z.ai/api/paas/v4/"
custom_llm_provider = "zai"
temperature = 0.6
max_input_tokens = 128000
max_output_tokens = 4096

# Alternative: Dedicated ZAI section
[llm.zai]
model = "glm-4.6"
api_key = "your-zai-api-key-here"
base_url = "https://api.z.ai/api/paas/v4/"
custom_llm_provider = "zai"
temperature = 0.6

# For coding tasks, you might prefer:
[llm.zai-coding]
model = "glm-4.5"
api_key = "your-zai-api-key-here"
base_url = "https://api.z.ai/api/paas/v4/"
custom_llm_provider = "zai"
temperature = 0.1  # Lower temperature for more deterministic code
```

### Method 3: Runtime Configuration (Web UI)

1. Access OpenHands Enterprise web interface
2. Navigate to **Settings** → **LLM Configuration**
3. Configure the following:
   - **Model**: `glm-4.6` (or `glm-4.5` for coding)
   - **API Key**: Your ZAI API key
   - **Base URL**: `https://api.z.ai/api/paas/v4/`
   - **Custom Provider**: `zai`
   - **Temperature**: `0.6` (recommended) or `0.1` for deterministic code
4. Save configuration

### Method 4: Docker Environment

```bash
docker run -d \
  --name openhands-enterprise \
  -p 3000:3000 \
  -e LLM_MODEL="glm-4.6" \
  -e LLM_API_KEY="your-zai-api-key-here" \
  -e LLM_BASE_URL="https://api.z.ai/api/paas/v4/" \
  -e LLM_CUSTOM_LLM_PROVIDER="zai" \
  -v $(pwd)/workspace:/app/workspace \
  openhands-enterprise:latest
```

## ZAI Model Configuration

### Supported ZAI Models

Z.AI provides OpenAI-compatible models. Here are the recommended models for OpenHands:

```python
# In openhands/utils/llm.py (if needed)
SUPPORTED_MODELS.extend([
    "glm-4.6",           # Latest model with enhanced reasoning
    "glm-4.5",           # Balanced performance model
    "glm-4.32b-0414-128k", # Large context model
])
```

### Model-Specific Settings

#### GLM-4.6 (Latest & Recommended)
```toml
[llm.zai-latest]
model = "glm-4.6"
temperature = 0.6          # Default temperature for balanced responses
max_input_tokens = 128000  # Large context for complex projects
max_output_tokens = 4096   # Standard output length
top_p = 0.95
```

#### GLM-4.5 (Coding Optimized)
```toml
[llm.zai-coding]
model = "glm-4.5"
temperature = 0.1          # Lower temperature for consistent code generation
max_input_tokens = 128000
max_output_tokens = 4096
top_p = 0.95
```

#### GLM-4.32B-0414-128K (Large Context)
```toml
[llm.zai-large-context]
model = "glm-4.32b-0414-128k"
temperature = 0.6
max_input_tokens = 128000  # Full 128K context
max_output_tokens = 8192   # Larger output for complex tasks
top_p = 0.95
```

## Authentication Setup

### API Key Configuration

1. **Obtain ZAI API Key**:
   - Sign up at ZAI Code platform
   - Navigate to API credentials
   - Generate new API key
   - Copy the key securely

2. **Configure API Key**:
```bash
# Method 1: Environment variable
export ZAI_API_KEY="your-api-key-here"

# Method 2: Docker secret
echo "your-api-key-here" | docker secret create zai_api_key -

# Method 3: Kubernetes secret
kubectl create secret generic zai-secrets \
  --from-literal=api-key="your-api-key-here"
```

### API Endpoint Configuration

ZAI API endpoints typically follow this pattern:

```bash
# Production endpoint
https://api.zai-code.com/v1

# Development endpoint (if available)
https://dev-api.zai-code.com/v1

# Custom endpoint (for enterprise deployments)
https://your-custom-zai-endpoint.com/v1
```

## Testing ZAI Integration

### 1. Configuration Test

```python
# Test script: test_zai_config.py
from openhands.core.config import load_openhands_config

def test_zai_configuration():
    config = load_openhands_config()
    llm_config = config.get_llm_config()
    
    print("=== ZAI Configuration Test ===")
    print(f"Model: {llm_config.model}")
    print(f"Base URL: {llm_config.base_url}")
    print(f"API Key Set: {llm_config.api_key is not None}")
    print(f"Custom Provider: {llm_config.custom_llm_provider}")
    print(f"Temperature: {llm_config.temperature}")
    
    # Verify ZAI-specific settings
    if llm_config.custom_llm_provider == "zai":
        print("✅ ZAI provider configured correctly")
    else:
        print("❌ ZAI provider not configured")
    
    if "zai" in llm_config.model.lower():
        print("✅ ZAI model configured")
    else:
        print("❌ ZAI model not configured")

if __name__ == "__main__":
    test_zai_configuration()
```

### 2. API Connectivity Test

```bash
# Test ZAI API directly
curl -X POST "https://api.z.ai/api/paas/v4/chat/completions" \
  -H "Authorization: Bearer your-zai-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-4.6",
    "messages": [
      {
        "role": "user",
        "content": "Create a simple Python function that adds two numbers"
      }
    ],
    "temperature": 0.6
  }'
```

### 3. OpenHands Integration Test

```python
# Test script: test_zai_integration.py
from openai import OpenAI

def test_zai_direct_integration():
    """Test direct ZAI API integration using OpenAI SDK"""
    client = OpenAI(
        api_key="your-zai-api-key",
        base_url="https://api.z.ai/api/paas/v4/"
    )
    
    try:
        response = client.chat.completions.create(
            model="glm-4.6",
            messages=[
                {"role": "user", "content": "Create a Python function to calculate factorial"}
            ],
            temperature=0.6
        )
        print("✅ ZAI direct integration successful")
        print(f"Response: {response.choices[0].message.content[:200]}...")
        return True
    except Exception as e:
        print(f"❌ ZAI direct integration failed: {e}")
        return False

def test_zai_openhands_integration():
    """Test ZAI through OpenHands LLM layer"""
    from openhands.llm.llm import LLM
    
    llm = LLM()
    test_prompt = "Create a Python function to calculate factorial"
    
    try:
        response = llm.completion(test_prompt)
        print("✅ ZAI OpenHands integration successful")
        print(f"Response: {response[:200]}...")
        return True
    except Exception as e:
        print(f"❌ ZAI OpenHands integration failed: {e}")
        return False

if __name__ == "__main__":
    print("=== ZAI Integration Test ===")
    test_zai_direct_integration()
    test_zai_openhands_integration()
```

## Advanced Configuration

### Custom Model Routing

Configure ZAI for specific tasks:

```toml
[model_routing]
router_name = "task_based_router"

# Route code planning tasks to ZAI
[[model_routing.rules]]
task_pattern = "plan|design|architecture"
target_model = "zai-code-planner"

# Route code generation to ZAI
[[model_routing.rules]]
task_pattern = "implement|generate|create"
target_model = "zai-code-generator"

# Route code review to ZAI
[[model_routing.rules]]
task_pattern = "review|analyze|audit"
target_model = "zai-code-reviewer"
```

### Multi-Provider Setup

Use ZAI alongside other providers:

```toml
[llm]
# Default to ZAI
model = "zai-code-planner"
api_key = "your-zai-api-key"
base_url = "https://api.zai-code.com/v1"
custom_llm_provider = "zai"

# Fallback provider
[llm.fallback]
model = "gpt-4"
api_key = "your-openai-key"
base_url = "https://api.openai.com/v1"
```

### Enterprise ZAI Configuration

For enterprise ZAI deployments:

```toml
[llm.zai-enterprise]
model = "glm-4.6"
api_key = "your-enterprise-zai-key"
base_url = "https://api.z.ai/api/paas/v4/"
custom_llm_provider = "zai"
# Enterprise-specific settings
temperature = 0.6
max_tokens = 4096
```

### Advanced ZAI Features

#### Thinking Mode (Enhanced Reasoning)
```python
from openai import OpenAI

client = OpenAI(
    api_key="your-zai-api-key",
    base_url="https://api.z.ai/api/paas/v4/"
)

response = client.chat.completions.create(
    model="glm-4.6",
    messages=[
        {"role": "user", "content": "Solve this complex math problem: ..."}
    ],
    extra_body={
        "thinking": {
            "type": "enabled",  # Enable thinking mode
        },
    }
)
```

#### Function Calling
```python
tools = [
    {
        "type": "function",
        "function": {
            "name": "execute_code",
            "description": "Execute Python code and return results",
            "parameters": {
                "type": "object",
                "properties": {
                    "code": {
                        "type": "string",
                        "description": "Python code to execute"
                    }
                },
                "required": ["code"]
            }
        }
    }
]

response = client.chat.completions.create(
    model="glm-4.6",
    messages=[
        {"role": "user", "content": "Calculate fibonacci(10)"}
    ],
    tools=tools,
    tool_choice="auto"
)
```

## Performance Optimization

### Caching Configuration

```toml
[llm.zai]
model = "zai-code-planner"
# Enable response caching for similar prompts
enable_caching = true
cache_ttl = 3600  # 1 hour
cache_max_size = 1000  # Maximum cached responses
```

### Rate Limiting

```toml
[llm.zai]
model = "zai-code-planner"
# Rate limiting to prevent API quota exhaustion
rate_limit_requests_per_minute = 60
rate_limit_tokens_per_minute = 100000
```

### Batch Processing

```toml
[llm.zai]
model = "zai-code-planner"
# Batch multiple requests for efficiency
enable_batch_processing = true
batch_size = 5
batch_timeout = 30  # seconds
```

## Troubleshooting

### Common Issues

1. **Authentication Errors**:
```bash
# Check API key validity
curl -H "Authorization: Bearer $ZAI_API_KEY" \
     https://api.zai-code.com/v1/models

# Verify key format
echo $ZAI_API_KEY | wc -c
```

2. **Network Connectivity**:
```bash
# Test endpoint reachability
curl -I https://api.zai-code.com/v1

# Check DNS resolution
nslookup api.zai-code.com
```

3. **Model Not Found**:
```bash
# List available models
curl -H "Authorization: Bearer $ZAI_API_KEY" \
     https://api.zai-code.com/v1/models
```

### Debug Mode

Enable debug logging for ZAI integration:

```bash
# Enable debug logging
LOG_LEVEL="DEBUG"
LLM_DEBUG="true"

# Enable request/response logging
LLM_LOG_REQUESTS="true"
LLM_LOG_RESPONSES="true"
```

### Performance Issues

Monitor ZAI API performance:

```python
# Monitor response times and token usage
import time
from openhands.llm.llm import LLM

def monitor_zai_performance():
    llm = LLM()
    
    start_time = time.time()
    response = llm.completion("test prompt")
    end_time = time.time()
    
    print(f"Response time: {end_time - start_time:.2f}s")
    print(f"Response length: {len(response)} characters")
```

## Security Considerations

### API Key Security

1. **Use secure storage**:
```bash
# Kubernetes secrets
kubectl create secret generic zai-credentials \
  --from-literal=api-key="your-zai-api-key"

# Docker secrets
echo "your-zai-api-key" | docker secret create zai_api_key -
```

2. **Rotate keys regularly**:
```bash
# Set key rotation reminder
echo "0 0 1 * * /usr/local/bin/rotate_zai_key.sh" | crontab -
```

3. **Audit access**:
```bash
# Monitor API key usage
curl -H "Authorization: Bearer $ZAI_API_KEY" \
     https://api.zai-code.com/v1/usage
```

### Network Security

1. **VPC peering** (for enterprise):
```bash
# Configure VPC peering with ZAI
aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-12345678 \
  --peer-vpc-id vpc-87654321 \
  --peer-owner-id 123456789012
```

2. **IP whitelisting**:
```bash
# Add your server IP to ZAI whitelist
curl -X POST "https://api.zai-code.com/v1/whitelist" \
  -H "Authorization: Bearer $ZAI_API_KEY" \
  -d '{"ip": "your-server-ip"}'
```

## Best Practices

1. **Start with code planner model** for best results
2. **Use lower temperature** (0.1-0.3) for consistent code planning
3. **Monitor API usage** to avoid quota exhaustion
4. **Implement fallback providers** for high availability
5. **Cache responses** for repeated similar requests
6. **Use structured prompts** for better code generation
7. **Regular security audits** of API credentials
8. **Performance monitoring** of response times and quality

## Support

For ZAI-specific issues:
- ZAI Documentation: https://docs.zai-code.com
- ZAI Support: support@zai-code.com
- API Status: https://status.zai-code.com

For OpenHands integration issues:
- Check OpenHands logs: `docker logs openhands-enterprise`
- Verify configuration: Check `config.toml` and environment variables
- Test connectivity: Use the test scripts provided above