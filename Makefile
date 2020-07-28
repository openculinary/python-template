.PHONY: build lint tests

SERVICE=$(shell basename $(shell git rev-parse --show-toplevel))
REGISTRY=registry.openculinary.org
PROJECT=reciperadar

IMAGE_NAME=${REGISTRY}/${PROJECT}/${SERVICE}
IMAGE_COMMIT := $(shell git rev-parse --short HEAD)
IMAGE_TAG := $(strip $(if $(shell git status --porcelain --untracked-files=no), latest, ${IMAGE_COMMIT}))

build: lint tests image

deploy:
	kubectl apply -f k8s
	kubectl set image deployments -l app=${SERVICE} ${SERVICE}=${IMAGE_NAME}:${IMAGE_TAG}

image:
	$(eval container=$(shell buildah from docker.io/library/python:3.8-alpine))
	buildah copy $(container) 'web' 'web'
	buildah copy $(container) 'Pipfile'
	buildah run $(container) -- chown guest /srv/ --
	buildah run --user guest $(container) -- pip install --root /srv/ pipenv --
	buildah run --user guest $(container) -- env HOME=/srv/ env PYTHONPATH=/srv/usr/local/lib/python3.8/site-packages /srv/usr/local/bin/pipenv install --skip-lock --
	buildah config --port 8000 --user guest --entrypoint 'env HOME=/srv/ env PYTHONPATH=/srv/usr/local/lib/python3.8/site-packages /srv/usr/local/bin/pipenv run gunicorn web.app:app --bind :8000' $(container)
	buildah commit --squash --rm $(container) ${IMAGE_NAME}:${IMAGE_TAG}

lint:
	pipenv run flake8

tests:
	pipenv run pytest tests
