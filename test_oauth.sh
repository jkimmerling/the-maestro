#!/bin/bash

# Test script to verify OAuth flow
echo "Testing OAuth flow..."

# Remove any existing credentials
rm -f ~/.maestro/tui_credentials.json ~/.maestro/auth_preference.txt

# Start the TUI and simulate choosing OAuth option
echo "2" | timeout 60s ./maestro_tui

echo "Test completed"