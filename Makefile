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
	buildah copy $(container) 'requirements.txt'
	buildah run $(container) -- adduser -h /srv/ -s /sbin/nologin -D -H gunicorn --
	buildah run $(container) -- chown gunicorn /srv/ --
	buildah run --user gunicorn $(container) -- pip install --requirement requirements.txt --user --
	# Begin: HACK: For rootless compatibility across podman and k8s environments, unset file ownership and grant read+exec to binaries
	buildah run $(container) -- chown -R nobody:nobody /srv/ --
	buildah run $(container) -- chmod -R a+rx /srv/.local/bin/ --
	buildah run $(container) -- find /srv/ -type d -exec chmod a+rx {} \;
	# End: HACK
	buildah config --port 8000 --user gunicorn --entrypoint '/srv/.local/bin/gunicorn web.app:app --bind :8000' $(container)
	buildah commit --squash --rm $(container) ${IMAGE_NAME}:${IMAGE_TAG}

venv: venv/bin/activate
	venv/bin/pip install --requirement requirements-dev.txt
	touch venv

venv/bin/activate:
	test -d venv || virtualenv venv
	venv/bin/pip install pip-tools
	touch venv/bin/activate

%.txt: venv %.in
	venv/bin/pip-compile $@

lint: venv
	venv/bin/flake8 tests
	venv/bin/flake8 web

tests: venv
	venv/bin/pytest tests
