#!/bin/bash
# Pre-push security check script

set -e

echo "🔍 Running pre-push security checks..."

# Check for common secret patterns
echo "Checking for API keys and tokens..."
if grep -r "civo_token.*=" --include="*.tf" --include="*.tfvars" --include="*.py" --include="*.js" --include="*.mjs" . 2>/dev/null | grep -v "YOUR_CIVO_TOKEN" | grep -v "example" | grep -v ".tfvars"; then
    echo "❌ FOUND CIVO TOKEN IN CODE!"
    exit 1
fi

if grep -rE "[0-9a-zA-Z]{40,}" --include="*.tfvars" --include="*.ftvars" . 2>/dev/null; then
    echo "❌ FOUND POTENTIAL SECRETS IN .tfvars FILES!"
    exit 1
fi

# Check for node_modules
if [ -d "agent_service/node_modules" ]; then
    echo "⚠️  WARNING: node_modules directory exists (should be gitignored)"
fi

# Check for .venv
if [ -d ".venv" ]; then
    echo "⚠️  WARNING: .venv directory exists (should be gitignored)"
fi

# Check for database files
if find . -name "*.db" -o -name "*.sqlite" 2>/dev/null | grep -q .; then
    echo "⚠️  WARNING: Database files found (should be gitignored)"
fi

echo ""
echo "✅ Security checks passed!"
echo ""
echo "📋 Pre-push checklist:"
echo "  [ ] Removed all API keys and tokens"
echo "  [ ] Updated terraform.tfvars.example with placeholder values"
echo "  [ ] Verified .gitignore is comprehensive"
echo "  [ ] Tested Docker build locally"
echo "  [ ] Updated README with deployment instructions"
echo ""
echo "Ready to push? Run: git push origin main"
