#!/bin/bash
# Pre-push script to run the same checks as CI/CD locally
# This prevents failed CI/CD runs by catching issues before push

set -e  # Exit on any error

echo "🔍 Running pre-push checks (matching CI/CD requirements)..."

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    echo "❌ Error: Not in an Elixir project directory"
    exit 1
fi

# Set MIX_ENV to match CI
export MIX_ENV=test

echo ""
echo "📦 Installing dependencies..."
mix deps.get

echo ""
echo "🎨 Checking code formatting..."
if ! mix format --check-formatted; then
    echo "❌ Code formatting check failed!"
    echo "💡 Run 'mix format' to fix formatting issues"
    exit 1
fi

echo ""
echo "🔍 Running Credo static analysis..."
if ! mix credo --strict; then
    echo "❌ Credo static analysis failed!"
    echo "💡 Fix the issues above or update .credo.exs if needed"
    exit 1
fi

echo ""
echo "🔨 Compiling with warnings as errors..."
if ! mix compile --warnings-as-errors; then
    echo "❌ Compilation failed with warnings!"
    echo "💡 Fix all compiler warnings before pushing"
    exit 1
fi

echo ""
echo "🗄️  Setting up test database (matching CI/CD)..."
if ! mix ecto.create --quiet; then
    echo "❌ Database creation failed!"
    echo "💡 Ensure PostgreSQL is running and properly configured"
    exit 1
fi

if ! mix ecto.migrate --quiet; then
    echo "❌ Database migration failed!"
    echo "💡 Fix migration issues before pushing"
    exit 1
fi

echo ""
echo "🧪 Running tests (matching CI/CD)..."
if ! mix test; then
    echo "❌ Tests failed!"
    echo "💡 Fix failing tests before pushing"
    exit 1
fi

echo ""
echo "✅ All pre-push checks passed! Safe to push."
echo ""