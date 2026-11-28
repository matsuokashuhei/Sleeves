DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
MACOS_DIR     := apps/macos
PROJECT       := $(MACOS_DIR)/Sleeves.xcodeproj
DERIVED_DATA  := .build
APP_PATH      := $(DERIVED_DATA)/Build/Products/Debug/Sleeves.app

TF_IMAGE       := hashicorp/terraform:1.17.2
TF_DIR         := infra/cloudflare
TF_STATE_DIR   := infra/cloudflare/terraform
TF_BACKEND     := backend.hcl
TF_DOCKER_ARGS := \
	-v "$(CURDIR)/$(TF_DIR):/workspace" \
	-w /workspace \
	-e CLOUDFLARE_API_TOKEN \
	-e AWS_ACCESS_KEY_ID \
	-e AWS_SECRET_ACCESS_KEY \
	-e TF_VAR_zone_id \
	-e TF_VAR_project_name \
	-e TF_VAR_subdomain
TF_RUN         := docker run --rm $(TF_DOCKER_ARGS) $(TF_IMAGE)
TF_STATE_ARGS  := \
	-v "$(CURDIR)/$(TF_STATE_DIR):/workspace" \
	-w /workspace \
	-e CLOUDFLARE_API_TOKEN \
	-e TF_VAR_zone_id \
	-e TF_VAR_state_bucket_name
TF_STATE_RUN   := docker run --rm $(TF_STATE_ARGS) $(TF_IMAGE)

.PHONY: gen build test run logs tf-state-init tf-state-plan tf-state-apply tf-init tf-fmt tf-validate tf-plan tf-apply

gen:
	cd $(MACOS_DIR) && DEVELOPER_DIR=$(DEVELOPER_DIR) xcodegen generate

build:
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project $(PROJECT) -scheme Sleeves -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) build

test:
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild \
		-project $(PROJECT) -scheme Sleeves -configuration Debug \
		-derivedDataPath $(DERIVED_DATA) test

run:
	pkill -x Sleeves || true
	open $(APP_PATH)

logs:
	/usr/bin/log show --last 5m --style compact --info \
		--predicate 'subsystem == "com.cacheandbuffer.Sleeves"'

tf-state-init:
	$(TF_STATE_RUN) init

tf-state-plan:
	$(TF_STATE_RUN) plan

tf-state-apply:
	docker run --rm -it $(TF_STATE_ARGS) $(TF_IMAGE) apply

tf-init:
	$(TF_RUN) init -backend-config=$(TF_BACKEND)

tf-fmt:
	$(TF_RUN) fmt -check -recursive

tf-validate:
	$(TF_RUN) validate

tf-plan:
	$(TF_RUN) plan

tf-apply:
	docker run --rm -it $(TF_DOCKER_ARGS) $(TF_IMAGE) apply
