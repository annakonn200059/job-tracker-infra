COMPOSE = docker compose -f local/docker-compose.yml

.PHONY: up up-db down reset logs ps psql build

up-db:
	$(COMPOSE) up -d postgres

up:
	$(COMPOSE) up -d --build

build:
	$(COMPOSE) build

down:
	$(COMPOSE) down

reset:
	$(COMPOSE) down -v
	$(COMPOSE) up -d postgres

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

psql:
	$(COMPOSE) exec postgres psql -U jobtracker -d jobtracker