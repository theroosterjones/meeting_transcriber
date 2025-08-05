#!/bin/bash

echo "🎤 Meeting Transcriber Setup Script"
echo "=================================="

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python 3.7+ first."
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"

# Create virtual environment
echo "📦 Creating virtual environment..."
python3 -m venv venv

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📚 Installing dependencies..."
pip install -r requirements.txt

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "🔑 Creating .env file..."
    cp env_example.txt .env
    echo "⚠️  IMPORTANT: Please edit .env file and add your OpenAI API key!"
    echo "   Get your API key from: https://platform.openai.com/api-keys"
else
    echo "✅ .env file already exists"
fi

# Create uploads directory
if [ ! -d uploads ]; then
    echo "📁 Creating uploads directory..."
    mkdir uploads
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit .env file and add your OpenAI API key"
echo "2. Set up billing at: https://platform.openai.com/account/billing"
echo "3. Run: source venv/bin/activate && python app.py"
echo "4. Open browser to: http://localhost:5000"
echo ""
echo "For Windows users:"
echo "1. Edit .env file and add your OpenAI API key"
echo "2. Run: venv\\Scripts\\activate && python app.py" 