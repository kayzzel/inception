#-------------------------------- VARIABLES ----------------------------------#

COMPOSE		=	docker compose -f srcs/docker-compose.yml

IMAGES		=	nginx wordpress mariadb

DATA_DIRS	=	/home/gabach/data/wordpress \
				/home/gabach/data/mariadb

#-------------------------------- RULES --------------------------------------#

.PHONY: all up down clean fclean re check_docker help

all: check_docker
	@mkdir -p $(DATA_DIRS)
	$(COMPOSE) up -d --build

up: check_docker
	@mkdir -p $(DATA_DIRS)
	$(COMPOSE) up -d

down: check_docker
	$(COMPOSE) down

clean: down
	docker rmi $(IMAGES)

fclean: clean
	$(COMPOSE) down -v
	sudo rm -rf $(DATA_DIRS)

re: fclean all

check_docker:
	@command -v docker >/dev/null 2>&1 || { \
		echo "Error: docker is not installed."; \
		echo "Install it via: https://docs.docker.com/engine/install/"; \
		exit 1; \
	}
	@docker compose version >/dev/null 2>&1 || { \
		echo "Error: docker compose (v2 plugin) is not installed."; \
		echo "Install it via: https://docs.docker.com/compose/install/"; \
		exit 1; \
	}

help:
	@echo "Available rules:"
	@echo "  all            - Build the images and start the whole stack"
	@echo "  up             - Start the stack (build if needed)"
	@echo "  down           - Stop and remove containers + network (keeps volumes and images)"
	@echo "  clean          - down + remove the built images (keeps volumes)"
	@echo "  fclean         - clean + remove the volumes and the data directories (DESTROYS all data)"
	@echo "  re             - fclean + all (full rebuild from scratch)"
	@echo "  check_docker   - Test if docker and docker compose are installed (used in every rule)"
