#!/usr/bin/env bash
# Crear mappings para WireMock en modo testing

# Crear directorio para mappings si no existe
mkdir -p wiremock-stubs

# Mock para users-api fallando
cat > wiremock-stubs/users-api-fail.json << 'EOF'
{
  "request": {
    "method": "GET", 
    "urlPath": "/users"
  },
  "response": {
    "status": 503,
    "body": "Service Unavailable - Simulated failure for retry testing",
    "headers": {
      "Content-Type": "application/json"
    },
    "fixedDelayMilliseconds": 1000
  }
}
EOF

# Mock para users-api funcionando después de retry
cat > wiremock-stubs/users-api-success.json << 'EOF'
{
  "request": {
    "method": "GET",
    "urlPath": "/users/health"
  },
  "response": {
    "status": 200,
    "body": "{\"status\":\"OK\",\"service\":\"users-api\"}",
    "headers": {
      "Content-Type": "application/json"
    }
  }
}
EOF

echo "✅ Mappings de WireMock creados en wiremock-stubs/"