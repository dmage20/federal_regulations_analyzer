# justfile for ecfr-analyzer Rails app

# List all available commands
default:
    @just --list

# Install dependencies
install:
    bundle install

# Setup the application (install deps, create db, migrate, seed)
setup:
    bin/setup

# Start the development server (web + tailwind watcher)
dev:
    bin/dev

# Start the Rails server only
server:
    bin/rails server

# Start the Rails console
console:
    bin/rails console

# Watch and rebuild Tailwind CSS
css:
    bin/rails tailwindcss:watch

# Build Tailwind CSS once
css-build:
    bin/rails tailwindcss:build

# Database commands
# ----------------

# Create the database
db-create:
    bin/rails db:create

# Run pending migrations
db-migrate:
    bin/rails db:migrate

# Rollback the last migration
db-rollback:
    bin/rails db:rollback

# Reset the database (drop, create, migrate, seed)
db-reset:
    bin/rails db:reset

# Seed the database
db-seed:
    bin/rails db:seed

# Drop the database
db-drop:
    bin/rails db:drop

# Testing commands
# ----------------

# Run all tests
test:
    bin/rails test

# Run system tests
test-system:
    bin/rails test:system

# Run tests with coverage
test-coverage:
    COVERAGE=true bin/rails test

# Linting and security
# --------------------

# Run Rubocop
lint:
    bin/rubocop

# Run Rubocop with auto-fix
lint-fix:
    bin/rubocop -A

# Run Brakeman security scanner
security:
    bin/brakeman

# Run bundler-audit to check for vulnerable dependencies
audit:
    bin/bundler-audit check --update

# Run all checks (lint, security, audit)
check: lint security audit

# Background jobs
# ---------------

# Start Solid Queue worker
jobs:
    bin/jobs

# Sync eCFR data (custom job for this app)
sync-ecfr:
    bin/rails runner 'SyncAllAgenciesJob.perform_later'

# Show queued jobs status
jobs-status:
    bin/rails runner tmp/show_queued_jobs.rb

# Clear all queued jobs (use with caution!)
jobs-clear:
    bin/rails runner 'count = SolidQueue::Job.count; SolidQueue::Job.destroy_all; puts "Cleared #{count} jobs"'

# Cleanup and maintenance
# -----------------------

# Clean up log files
clean-logs:
    rm -f log/*.log
    rm -f tmux-*.log

# Clean up temporary files
clean-tmp:
    rm -rf tmp/cache/*
    bin/rails tmp:clear

# Clean everything (logs, tmp, and rebuild assets)
clean: clean-logs clean-tmp
    bin/rails assets:clobber || true
    bin/rails tailwindcss:build

# Git helpers
# -----------

# Show git status
status:
    git status

# Show git diff
diff:
    git diff

# Docker commands (if using)
# --------------------------

# Build Docker image
docker-build:
    docker build -t ecfr-analyzer .

# Run Docker container
docker-run:
    docker run -p 3000:3000 ecfr-analyzer

# CI simulation
# -------------

# Run the full CI suite locally
ci:
    bin/ci
