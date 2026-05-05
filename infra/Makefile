.PHONY: up down logs ps backup-db restore-db build

# Tum servisleri baslat
up:
	docker compose up -d

# Tum servisleri durdur
down:
	docker compose down

# Servisleri durdur ve volume'lari sil (DIKKAT: veri kaybi)
destroy:
	docker compose down -v

# Loglari izle
logs:
	docker compose logs -f --tail=100

# Belirli servisin logunu izle (ornek: make log-backend)
log-%:
	docker compose logs -f --tail=100 $*

# Servis durumlarini goster
ps:
	docker compose ps

# Backend'i yeniden build et
build:
	docker compose build backend

# PostgreSQL yedek al
backup-db:
	@mkdir -p backups
	@TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	docker compose exec -T postgres pg_dump -U securechat securechat | gzip > backups/securechat-$$TIMESTAMP.sql.gz; \
	echo "Yedek: backups/securechat-$$TIMESTAMP.sql.gz"

# PostgreSQL yedek yukle (ornek: make restore-db FILE=backups/securechat-20260429.sql.gz)
restore-db:
	@if [ -z "$(FILE)" ]; then echo "Kullanim: make restore-db FILE=backups/xxx.sql.gz"; exit 1; fi
	@echo "UYARI: Mevcut veriler silinecek. Devam etmek icin ENTER'a basin..."
	@read _confirm
	gunzip -c $(FILE) | docker compose exec -T postgres psql -U securechat -d securechat

# Redis'e baglan
redis-cli:
	docker compose exec redis redis-cli -a $${REDIS_PASSWORD}

# PostgreSQL'e baglan
psql:
	docker compose exec postgres psql -U securechat -d securechat
