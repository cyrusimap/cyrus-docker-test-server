IMAGE_NAME = ghcr.io/cyrusimap/cyrus-docker-test-server
TAG = latest
CONTAINER_NAME = cyrus-test
PLATFORM = linux/amd64

# How long to wait for the container to be ready (seconds)
STARTUP_TIMEOUT = 120

.PHONY: build test run stop clean publish

build:
	docker build --platform $(PLATFORM) . -t $(IMAGE_NAME):$(TAG)

run: stop
	docker run --platform $(PLATFORM) -d --name $(CONTAINER_NAME) \
	  -p 8080:8080 -p 8143:8143 -p 8110:8110 -p 8024:8024 -p 8001:8001 -p 4190:4190 \
	  $(IMAGE_NAME):$(TAG)
	@echo "Waiting for container to be ready..."
	@for i in $$(seq 1 $(STARTUP_TIMEOUT)); do \
	  curl -sf http://localhost:8001/ >/dev/null 2>&1 && break; \
	  sleep 1; \
	done
	@curl -sf http://localhost:8001/ >/dev/null 2>&1 || (echo "Container failed to start"; docker logs $(CONTAINER_NAME); exit 1)
	@echo "Container is ready."

test: run
	./test.sh

stop:
	-docker rm -f $(CONTAINER_NAME) 2>/dev/null

clean: stop
	-docker rmi $(IMAGE_NAME):$(TAG) 2>/dev/null

publish: build test
	@echo "All tests passed. Pushing image..."
	docker push $(IMAGE_NAME):$(TAG)
	@echo "Published $(IMAGE_NAME):$(TAG)"
