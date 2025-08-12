# The Maestro Development Makefile

.PHONY: help setup test check format lint compile clean pre-push ci deps

# Default target
help: ## Show this help message
	@echo "The Maestro Development Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

setup: ## Initial project setup
	@echo "🚀 Setting up The Maestro development environment..."
	mix deps.get
	mix ecto.create
	mix ecto.migrate
	@echo "✅ Setup complete!"

deps: ## Install/update dependencies
	@echo "📦 Installing dependencies..."
	mix deps.get

format: ## Format code
	@echo "🎨 Formatting code..."
	mix format

lint: ## Run Credo linter
	@echo "🔍 Running Credo..."
	mix credo --strict

compile: ## Compile with warnings as errors
	@echo "🔨 Compiling..."
	mix compile --warnings-as-errors

test: ## Run tests
	@echo "🧪 Running tests..."
	MIX_ENV=test mix test

check: ## Run all quality checks (matches CI/CD)
	@echo "🔍 Running all quality checks..."
	@./scripts/pre-push.sh

pre-push: check ## Alias for check (matches CI/CD requirements)

ci: check ## Run CI checks locally

clean: ## Clean build artifacts
	@echo "🧹 Cleaning..."
	mix clean
	mix deps.clean --all

# Development workflow targets
dev-setup: setup ## Complete development setup
	@echo "🛠️  Development environment ready!"

quick-check: format lint ## Quick quality check (no tests)
	@echo "⚡ Quick checks complete!"

# Git workflow helpers  
safe-push: check ## Run checks then push (if checks pass)
	@echo "🚀 Checks passed, pushing..."
	git push