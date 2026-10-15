#!/bin/bash
# Setup script for YouTube Download
# Helps install yt-dlp binary or Python module

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "🎬 YouTube Download Setup"
echo "========================="
echo ""

if [ ! -f "extension.mjs" ] || [ ! -f "package.json" ]; then
    echo "❌ Error: Could not find the youtube-download skill root (expected extension.mjs and package.json)."
    exit 1
fi

# Install npm dependencies
echo "1️⃣  Installing Node dependencies..."
npm install || {
    echo "⚠️  npm install failed. Trying with --legacy-peer-deps..."
    npm install --legacy-peer-deps || {
        echo "⚠️  npm still failed. You may need to:"
        echo "   - Update Node.js: https://nodejs.org/"
        echo "   - Clear cache: npm cache clean --force"
        echo "   - Try manually: npm install"
        exit 1
    }
}
echo "✅ Node dependencies installed"
echo ""

# Detect OS and offer download option
OS=$(uname -s)
echo "2️⃣  Detected OS: $OS"
echo ""

echo "Choose how to run yt-dlp:"
echo ""
echo "  A) Download binary (recommended - no Python required)"
echo "  B) Use Python module (system-wide)"
echo "  C) Create virtual environment (isolated Python)"
echo "  D) Skip (install manually later)"
echo ""
read -p "Choose [A/B/C/D]: " choice

case $choice in
    A|a)
        echo ""
        echo "📥 Downloading yt-dlp binary..."
        mkdir -p bin
        
        if [ "$OS" = "Linux" ]; then
            wget -q https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -O bin/yt-dlp
            chmod +x bin/yt-dlp
            echo "✅ Downloaded yt-dlp for Linux"
        elif [ "$OS" = "Darwin" ]; then
            curl -L -s https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos -o bin/yt-dlp
            chmod +x bin/yt-dlp
            echo "✅ Downloaded yt-dlp for macOS"
        else
            echo "⚠️  Windows detected. Download manually from: https://github.com/yt-dlp/yt-dlp/releases"
            exit 1
        fi
        echo ""
        ;;
    B|b)
        echo ""
        echo "📦 Installing yt-dlp Python module..."
        pip install yt-dlp
        echo "✅ yt-dlp installed"
        echo ""
        ;;
    C|c)
        echo ""
        echo "🐍 Creating virtual environment..."
        python3 -m venv .venv
        source .venv/bin/activate
        pip install yt-dlp
        deactivate
        echo "✅ Virtual environment created with yt-dlp"
        echo ""
        ;;
    D|d)
        echo "Skipped. Install yt-dlp manually when ready."
        echo ""
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

# Verify setup
echo "3️⃣  Verifying setup..."
if command -v yt-dlp &> /dev/null; then
    VERSION=$(yt-dlp --version)
    echo "✅ yt-dlp found: $VERSION"
elif [ -f "bin/yt-dlp" ] && [ -x "bin/yt-dlp" ]; then
    VERSION=$(./bin/yt-dlp --version)
    echo "✅ yt-dlp binary found: $VERSION"
elif command -v python3 &> /dev/null; then
    if python3 -c "import yt_dlp" 2>/dev/null; then
        VERSION=$(python3 -c "import yt_dlp; print(yt_dlp.__version__)")
        echo "✅ yt-dlp Python module found: $VERSION"
    else
        echo "⚠️  yt-dlp not found. Install with one of the options above."
        exit 1
    fi
else
    echo "⚠️  yt-dlp not found. Install with one of the options above."
    exit 1
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Reload Copilot extensions (or restart Copilot CLI)"
echo "2. Try: /youtube-download"
echo ""
