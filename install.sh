#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Installing GeCo project dependencies with uv..."

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "uv is not installed. Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
    
    # Verify installation
    if ! command -v uv &> /dev/null; then
        echo "Error: Failed to install uv. Please install it manually."
        exit 1
    fi
    echo "uv installed successfully."
else
    echo "uv is already installed."
fi

# Create pyproject.toml if it doesn't exist
if [ ! -f "pyproject.toml" ]; then
    echo "Creating pyproject.toml..."
    cat > pyproject.toml << 'EOF'
[project]
name = "geco"
version = "0.1.0"
description = "A Novel Unified Architecture for Low-Shot Counting by Detection and Segmentation"
readme = "README.md"
requires-python = ">=3.8"
dependencies = [
    "torch>=2.0.0",
    "torchvision>=0.15.0",
    "matplotlib>=3.5.0",
    "pillow>=9.0.0",
    "numpy>=1.21.0",
]

[project.optional-dependencies]
evaluation = [
    "tqdm>=4.64.0",
    "pycocotools>=2.0.0",
    "scipy>=1.9.0",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
EOF
    echo "pyproject.toml created."
else
    echo "pyproject.toml already exists."
fi

# Create virtual environment
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment with uv venv..."
    uv venv
    echo "Virtual environment created."
else
    echo "Virtual environment already exists."
fi

# Install dependencies
echo "Installing dependencies with uv sync..."
uv sync

# Create logs directory
mkdir -p logs

# Create MODEL_folder directory if it doesn't exist (as mentioned in README)
if [ ! -d "MODEL_folder" ]; then
    mkdir -p MODEL_folder
    echo "Created MODEL_folder directory"
else
    echo "MODEL_folder directory already exists"
fi

# Check for model file in common locations
MODEL_FOUND=false
MODEL_LOCATIONS=(
    "GeCo.pth"
    "./GeCo.pth"
    "./models/GeCo.pth"
    "./MODEL_folder/GeCo.pth"
)

for location in "${MODEL_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        echo "Found model file at: $location"
        MODEL_FOUND=true
        break
    fi
done

if [ "$MODEL_FOUND" = false ]; then
    echo ""
    echo "⚠️  Model file (GeCo.pth) not found!"
    echo ""
    echo "Attempting to download model file using gdown..."
    echo ""
    
    # Google Drive file ID from the README
    MODEL_FILE_ID="1wjOF9MWkrVJVo5uG3gVqZEW9pwRq_aIk"
    MODEL_DEST="./MODEL_folder/GeCo.pth"
    
    # Use uv run to execute gdown (will use gdown from dependencies)
    if [ -d ".venv" ]; then
        echo "Downloading model to $MODEL_DEST..."
        echo "This may take a few minutes depending on your internet connection..."
        echo ""
        
        if uv run gdown --id "$MODEL_FILE_ID" --output "$MODEL_DEST" --fuzzy 2>&1; then
            if [ -f "$MODEL_DEST" ]; then
                # Verify file size (model should be reasonably large, at least 1MB)
                FILE_SIZE=$(stat -f%z "$MODEL_DEST" 2>/dev/null || stat -c%s "$MODEL_DEST" 2>/dev/null || echo "0")
                if [ "$FILE_SIZE" -gt 1000000 ]; then  # At least 1MB
                    # Format file size for display
                    if [ "$FILE_SIZE" -gt 1073741824 ]; then
                        SIZE_DISPLAY=$(echo "scale=2; $FILE_SIZE/1073741824" | bc 2>/dev/null || echo "$(($FILE_SIZE / 1073741824))")
                        SIZE_DISPLAY="${SIZE_DISPLAY} GB"
                    elif [ "$FILE_SIZE" -gt 1048576 ]; then
                        SIZE_DISPLAY=$(echo "scale=2; $FILE_SIZE/1048576" | bc 2>/dev/null || echo "$(($FILE_SIZE / 1048576))")
                        SIZE_DISPLAY="${SIZE_DISPLAY} MB"
                    else
                        SIZE_DISPLAY=$(echo "scale=2; $FILE_SIZE/1024" | bc 2>/dev/null || echo "$(($FILE_SIZE / 1024))")
                        SIZE_DISPLAY="${SIZE_DISPLAY} KB"
                    fi
                    echo "✅ Model file downloaded successfully! (${SIZE_DISPLAY})"
                    MODEL_FOUND=true
                else
                    echo "❌ Downloaded file seems too small (${FILE_SIZE} bytes). Please download manually."
                    rm -f "$MODEL_DEST"
                fi
            else
                echo "❌ Download completed but file not found. Please download manually."
            fi
        else
            echo "❌ Failed to download model using gdown."
            echo ""
            echo "Please download the model file manually from:"
            echo "  https://drive.google.com/file/d/${MODEL_FILE_ID}/view?usp=sharing"
            echo ""
            echo "After downloading, place it in one of these locations:"
            echo "  - ./GeCo.pth (current directory)"
            echo "  - ./MODEL_folder/GeCo.pth (recommended)"
            echo "  - ./models/GeCo.pth"
            echo ""
            echo "Or set MODEL_PATH in .env file to point to your model file location."
        fi
    else
        echo "❌ Virtual environment not found. Cannot download model."
        echo "Please run the installation again or download the model manually."
    fi
    echo ""
else
    echo "✅ Model file found - ready for inference!"
fi

# Create .env file from example if it doesn't exist
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo "Created .env file from .env.example"
    else
        echo "PORT=8013" > .env
        echo "HOST=0.0.0.0" >> .env
        echo "Created default .env file"
    fi
else
    echo ".env file already exists"
fi

# Add MODEL_PATH to .env if model was found and not already set
if [ "$MODEL_FOUND" = true ] && ! grep -q "^MODEL_PATH=" .env 2>/dev/null; then
    for location in "${MODEL_LOCATIONS[@]}"; do
        if [ -f "$location" ]; then
            # Convert relative path to absolute if needed
            ABS_PATH=$(cd "$(dirname "$location")" && pwd)/$(basename "$location")
            echo "MODEL_PATH=$ABS_PATH" >> .env
            echo "Added MODEL_PATH to .env file"
            break
        fi
    done
fi

echo ""
echo "Installation complete!"
echo "Virtual environment: .venv/"
echo "To activate manually, run: source .venv/bin/activate"
echo ""
echo "Configuration:"
echo "  - Edit .env file to configure HOST and PORT (default: PORT=8013)"
if [ "$MODEL_FOUND" = false ]; then
    echo "  - Download and place GeCo.pth model file (see warning above)"
fi
echo ""
echo "To run the web app, use: ./run.sh"
echo "The web app will use the port specified in .env (default: 8013)"
if [ "$MODEL_FOUND" = false ]; then
    echo ""
    echo "⚠️  Note: Model file not found. Inference will not work until model is available."
fi
echo ""
echo "Other commands:"
echo "  ./stop.sh    - Stop the web app"
echo "  ./restart.sh - Restart the web app"
echo "  ./monitor.sh - Monitor the web app status"

