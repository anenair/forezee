# ============================================================
# Forzee — Makefile
# All project scripts should be run through this file.
# Usage: make <target>
# ============================================================

.PHONY: setup generate build test clean open lint format help

# ─── Setup ──────────────────────────────────────────────────

## Install dependencies and generate Xcode project (run first time)
setup:
	@echo "── Forzee Setup ────────────────────────────────────────"
	@echo "→ Checking for Homebrew..."
	@which brew > /dev/null || (echo "❌ Homebrew not found. Install from https://brew.sh" && exit 1)
	@echo "→ Installing XcodeGen..."
	@brew install xcodegen 2>/dev/null || brew upgrade xcodegen 2>/dev/null || true
	@echo "→ Checking for Secrets.xcconfig..."
	@if [ ! -f Secrets.xcconfig ]; then \
		cp Secrets.xcconfig.example Secrets.xcconfig; \
		echo ""; \
		echo "⚠️  Secrets.xcconfig created from example."; \
		echo "   Open Secrets.xcconfig and fill in your API keys before building."; \
		echo ""; \
	else \
		echo "✅ Secrets.xcconfig already exists"; \
	fi
	@$(MAKE) generate
	@echo ""
	@echo "✅ Setup complete. Run 'make open' to open in Xcode."

# ─── Generate ───────────────────────────────────────────────

## Regenerate Xcode project from project.yml
generate:
	@echo "→ Generating Xcode project from project.yml..."
	@xcodegen generate
	@echo "✅ Forzee.xcodeproj generated"

# ─── Build ──────────────────────────────────────────────────

## Build for iPhone 16 simulator
build:
	@echo "→ Building Forzee (Debug, iPhone 16 Simulator)..."
	@xcodebuild \
		-project Forzee.xcodeproj \
		-scheme Forzee \
		-configuration Debug \
		-destination "platform=iOS Simulator,name=iPhone 16" \
		build \
		| xcpretty || xcodebuild \
		-project Forzee.xcodeproj \
		-scheme Forzee \
		-configuration Debug \
		-destination "platform=iOS Simulator,name=iPhone 16" \
		build

## Build Release for App Store
build-release:
	@echo "→ Building Forzee (Release)..."
	@xcodebuild \
		-project Forzee.xcodeproj \
		-scheme Forzee \
		-configuration Release \
		-destination "generic/platform=iOS" \
		archive \
		-archivePath build/Forzee.xcarchive

# ─── Test ───────────────────────────────────────────────────

## Run unit tests
test:
	@echo "→ Running tests..."
	@xcodebuild \
		-project Forzee.xcodeproj \
		-scheme Forzee \
		-destination "platform=iOS Simulator,name=iPhone 16" \
		test

# ─── Clean ──────────────────────────────────────────────────

## Clean build artifacts
clean:
	@echo "→ Cleaning..."
	@xcodebuild \
		-project Forzee.xcodeproj \
		-scheme Forzee \
		clean 2>/dev/null || true
	@rm -rf build/
	@echo "✅ Clean complete"

# ─── Open ───────────────────────────────────────────────────

## Open the project in Xcode
open:
	@echo "→ Opening Forzee.xcodeproj in Xcode..."
	@open Forzee.xcodeproj

# ─── Lint / Format ──────────────────────────────────────────

## Run SwiftLint
lint:
	@which swiftlint > /dev/null || (echo "→ Installing SwiftLint..." && brew install swiftlint)
	@echo "→ Running SwiftLint..."
	@swiftlint lint --path Forzee/

## Auto-fix SwiftLint violations
lint-fix:
	@which swiftlint > /dev/null || (echo "→ Installing SwiftLint..." && brew install swiftlint)
	@echo "→ Auto-fixing lint violations..."
	@swiftlint lint --fix --path Forzee/

## Run swift-format
format:
	@which swift-format > /dev/null || (echo "→ Installing swift-format..." && brew install swift-format)
	@echo "→ Formatting Swift files..."
	@find Forzee -name "*.swift" | xargs swift-format format -i

# ─── Supabase ───────────────────────────────────────────────

## Apply Supabase schema (development only — never touches prod)
db-migrate-dev:
	@echo "→ Applying schema to local Supabase..."
	@which supabase > /dev/null || (echo "→ Installing Supabase CLI..." && brew install supabase/tap/supabase)
	@supabase db push --local

# ─── Git ────────────────────────────────────────────────────

## Stage all changes and commit. Usage: make commit MSG="your message"
commit:
	@if [ -z "$(MSG)" ]; then \
		echo "❌ Commit message required. Usage: make commit MSG=\"your message\""; \
		exit 1; \
	fi
	@echo "→ Staging changes..."
	@git add -A
	@echo "→ Committing..."
	@git commit -m "$(MSG)"

## Push current branch to origin
push:
	@echo "→ Pushing $$(git branch --show-current) to origin..."
	@git push -u origin $$(git branch --show-current)

## Stage, commit, and push in one shot. Usage: make ship MSG="your message"
ship: commit push

# ─── Help ───────────────────────────────────────────────────

## Show this help
help:
	@echo ""
	@echo "Forzee — Available Make Targets"
	@echo "────────────────────────────────────────────"
	@echo "  make setup          Install XcodeGen, copy secrets, generate project"
	@echo "  make generate       Regenerate Forzee.xcodeproj from project.yml"
	@echo "  make build          Build Debug for iPhone 16 Simulator"
	@echo "  make build-release  Build Release for App Store"
	@echo "  make test           Run unit tests"
	@echo "  make clean          Clean build artifacts"
	@echo "  make open           Open project in Xcode"
	@echo "  make lint           Run SwiftLint"
	@echo "  make lint-fix       Auto-fix SwiftLint violations"
	@echo "  make format         Run swift-format"
	@echo "  make db-migrate-dev Apply schema to local Supabase (dev only)"
	@echo "  make commit MSG=… Stage all + commit with message"
	@echo "  make push           Push current branch to origin"
	@echo "  make ship MSG=…   commit + push in one shot"
	@echo ""
