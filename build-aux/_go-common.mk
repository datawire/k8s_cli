# Copyright 2018 Datawire. All rights reserved.
#
# Makefile snippet of common bits between go-mod.mk and
# go-workspace.mk.  Don't include this directly from your Makefile,
# include either go-mod.mk or go-workspace.mk!
#
# _go-common.mk needs 3 things of the calling go-FOO.mk:
#  1. set $(go.module) to github.com/datawire/whatever
#  2. set $(go.pkgs) to something morally equivalent to `./...`.  When
#     using modules, it's literally `./...`.  But when using
#     workspaces, './...` doesn't respect `./vendor/`, so the we have
#     to expand the list before passing it to Go.
#  3. write the recipe for `go-get`
#
# It is acceptable to set $(go.pkgs) *after* including _go-common.mk
ifeq ($(go.module),)
$(error Do not include _go-common.mk directly, include go-mod.mk or go-workspace.mk)
endif
_go-common.mk := $(lastword $(MAKEFILE_LIST))

NAME ?= $(notdir $(go.module))

go.DISABLE_GO_TEST ?=
go.LDFLAGS ?=
go.PLATFORMS ?= $(GOOS)_$(GOARCH)
go.GOLANG_LINT_VERSION ?= 1.13.1
go.GOLANG_LINT_FLAGS ?= $(if $(wildcard .golangci.yml .golangci.toml .golangci.json),,--disable-all --enable=gofmt --enable=govet)

# It would be simpler to create this list if we could use Go modules:
#
#     go.bins := $(shell $(GO) list -f='{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./...)
#
# But alas, we can't do that *even if* the build is using Go modules,
# as that would cause the module system go ahead and download
# dependencies.  We don't want Go to do that at Makefile-parse-time;
# what if we're running `make clean`?
#
# So instead, we must deal with this abomination.  At least that means
# we can share it between go-mod.mk and go-workspace.mk.
_go.submods := $(patsubst %/go.mod,%,$(shell git ls-files '*/go.mod'))
go.list = $(call path.addprefix,$(go.module),\
                                $(filter-out $(foreach d,$(_go.submods),$d $d/%),\
                                             $(call path.trimprefix,_$(CURDIR),\
                                                                    $(shell GOPATH=/bogus GO111MODULE=off GOCACHE=off go list $1))))
go.bins := $(call go.list,-f='{{if eq .Name "main"}}{{.ImportPath}}{{end}}' ./...)

#
# Rules

# go-FOO.mk is responsible for implementing go-get
go-get: ## (Go) Download Go dependencies
.PHONY: go-get

define _go.bin.rule
bin_%/.cache.$(notdir $(go.bin)): go-get FORCE
	go build $$(if $$(go.LDFLAGS),--ldflags $$(call quote.shell,$$(go.LDFLAGS))) -o $$@ $(go.bin)
bin_%/$(notdir $(go.bin)): bin_%/.cache.$(notdir $(go.bin))
	@{ \
		PS4=''; set -x; \
		if ! cmp -s $$< $$@; then \
			$(if $(CI),if test -e $$@; then false This should not happen in CI: $$@ should not change; fi &&) \
			cp -f $$< $$@; \
		fi; \
	}
endef
$(foreach go.bin,$(go.bins),$(eval $(_go.bin.rule)))

go-build: $(foreach _go.PLATFORM,$(go.PLATFORMS),$(addprefix bin_$(_go.PLATFORM)/,$(notdir $(go.bins))))
.PHONY: go-build

$(dir $(_go-common.mk))golangci-lint: $(_go-common.mk)
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s -- -b $(@D) v$(go.GOLANG_LINT_VERSION)

go-lint: ## (Go) Check the code with `golangci-lint`
go-lint: $(dir $(_go-common.mk))golangci-lint go-get
	$(dir $(_go-common.mk))golangci-lint run $(go.GOLANG_LINT_FLAGS) $(go.pkgs)
.PHONY: go-lint

go-fmt: ## (Go) Fixup the code with `go fmt`
go-fmt: go-get
	go fmt $(go.pkgs)
.PHONY: go-fmt

go-test: ## (Go) Check the code with `go test`
go-test: go-get
	$(if $(go.DISABLE_GO_TEST),,go test $(go.pkgs))
.PHONY: go-test

#
# Hook in to common.mk

build: go-build
lint: go-lint
check: go-test
format: go-fmt

clobber: _clobber-go-common
_clobber-go-common:
	rm -f $(dir $(_go-common.mk))golangci-lint
.PHONY: _clobber-go-common
