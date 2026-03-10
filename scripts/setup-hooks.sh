#!/bin/bash
# Setup script to install git hooks

echo "🔧 Installing git hooks..."

# Copy pre-commit hook to .git/hooks
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo "✅ Git hooks installed successfully!"
echo "The pre-commit hook will now block commits when tests fail."
