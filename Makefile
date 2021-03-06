SHELL=/bin/bash -o pipefail

GO ?= go
DOCKER ?= docker
HELM ?= helm

REGISTRY_IMAGE="codenotary/kube-notary:latest"
TEST_FLAGS ?= -v -race

export GO111MODULE=on

.PHONY: help
help: ## Show this help.
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'

.PHONY: kube-notary
kube-notary: ## Build kube-notary binary
	$(GO) get github.com/rakyll/statik
	GOOS=linux GOARCH=amd64 $(GO) generate ./pkg/status
	GOOS=linux GOARCH=amd64 $(GO) build ./cmd/kube-notary

.PHONY: kube-notary/debug
kube-notary/debug: ## Build kube-notary not optimized binary (-gcflags='all=-N -l)
	$(GO) get github.com/rakyll/statik
	GOOS=linux GOARCH=amd64 $(GO) generate ./pkg/status
	GOOS=linux GOARCH=amd64 $(GO) build -gcflags "all=-N -l" ./cmd/kube-notary

.PHONY: image
image: ## Build kube-notary image
	$(DOCKER) build -t $(REGISTRY_IMAGE) -f ./Dockerfile .

.PHONY: image/debug
image/debug: ## Build kube-notary debug image kube-notary:debug
	$(DOCKER) build -t kube-notary:debug -f ./Dockerfile.debug .

.PHONY: image.push
image.push: image ## Push image in the registry
	$(DOCKER) push $(REGISTRY_IMAGE)

.PHONY: kubernetes
kubernetes:
	rm -rf kubernetes/kube-notary
	rm -rf kubernetes/kube-notary-namespaced
	$(HELM) template -n kube-notary helm/kube-notary --set watch.namespace="default" --output-dir ./kubernetes
	for f in ./kubernetes/kube-notary/templates/*; do grep -E "helm|Tiller" -v $$f > $$f.tmp; rm $$f; mv $$f.tmp $$f; done
	mv kubernetes/kube-notary kubernetes/kube-notary-namespaced
	$(HELM) template -n kube-notary helm/kube-notary --output-dir ./kubernetes
	for f in ./kubernetes/kube-notary/templates/*; do grep -E "helm|Tiller" -v $$f > $$f.tmp; rm $$f; mv $$f.tmp $$f; done

.PHONY: CHANGELOG.md
CHANGELOG.md: ## Update changelog
	git-chglog -o CHANGELOG.md

.PHONY: test
test: ## Launch kube-notary GO tests
	$(GO) vet ./...
	$(GO) test ${TEST_FLAGS} ./...

.PHONY: test/e2e.local
test/e2e.local: ## Launch kube-notary local tests
	$(DOCKER) build -t kube-notary:test -f ./Dockerfile .
	cd ./test/e2e && ./run.sh

.PHONY: test/e2e
test/e2e: ## Launch kube-notary e2e tests. It uses kube-notary-test-e2e image
	$(DOCKER) build -t kube-notary:test -f ./Dockerfile .
	$(DOCKER) build -t kube-notary-test-e2e -f Dockerfile.test-e2e .
	$(DOCKER) run --rm -v "/var/run/docker.sock:/var/run/docker.sock:ro" --network host kube-notary-test-e2e

.PHONY: kubernetes/debug
kubernetes/debug: ## Create a kubernetes debug environment for kube-notary. A delve server is launch inside kube-notary pod. Launch make image/debug first
	cd ./test/debug && ./run.sh

.PHONY: kubernetes/kube
kubernetes/kube:  ## Create a kubernetes environment for kube-notary. Launch make image first
	cd ./test/kube && ./run.sh