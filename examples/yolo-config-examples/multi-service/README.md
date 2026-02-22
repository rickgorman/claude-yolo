# Multi-Service Example

A Rails application that depends on multiple backend services.

## Structure

```
.yolo/
├── strategy     # Rails strategy
├── env          # Environment variables for all services
└── ports        # Port mappings for all services
```

## Files

### `strategy`
```
rails
```

### `env`
```bash
RAILS_ENV=development
DATABASE_URL=postgresql://postgres:password@db:5432/myapp_development
REDIS_URL=redis://redis:6379/0
ELASTICSEARCH_URL=http://elasticsearch:9200
SMTP_ADDRESS=mailcatcher
SECRET_KEY_BASE=development_secret_key
```

### `ports`
```
3000:3000      # Rails
5432:5432      # PostgreSQL
6379:6379      # Redis
9200:9200      # ElasticSearch
1025:1025      # MailCatcher SMTP
1080:1080      # MailCatcher Web
```

## Use Case

You're running a complex Rails application with:
- PostgreSQL database
- Redis for caching and Sidekiq
- ElasticSearch for search functionality
- MailCatcher for email testing

All services need to communicate with each other, so you configure the environment variables to point to the right hosts and ports.

## Docker Compose Integration

This configuration works well with docker-compose. Create a `docker-compose.yml`:

```yaml
version: '3.8'

services:
  db:
    image: postgres:15
    environment:
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  elasticsearch:
    image: elasticsearch:8.11.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
    ports:
      - "9200:9200"

  mailcatcher:
    image: schickling/mailcatcher
    ports:
      - "1025:1025"
      - "1080:1080"

volumes:
  postgres_data:
```

## Usage

1. Start backing services:
   ```bash
   docker-compose up -d
   ```

2. Start claude-yolo with this configuration:
   ```bash
   mkdir -p .yolo
   cp examples/yolo-config-examples/multi-service/* .yolo/
   claude-yolo --yolo --trust-yolo
   ```

3. In the container, your Rails app can connect to all services:
   ```ruby
   # config/database.yml uses DATABASE_URL
   # config/initializers/redis.rb uses REDIS_URL
   # config/initializers/elasticsearch.rb uses ELASTICSEARCH_URL
   ```

## Verification

Check that all services are accessible from within the container:

```bash
# PostgreSQL
psql $DATABASE_URL -c "SELECT version();"

# Redis
redis-cli -u $REDIS_URL ping

# ElasticSearch
curl $ELASTICSEARCH_URL

# MailCatcher
curl http://mailcatcher:1080
```

## Security Note

This example uses insecure passwords and configurations suitable for development only. For production:
- Use proper secrets management
- Enable authentication on all services
- Use encrypted connections
- Don't commit `.yolo/env` with real credentials
