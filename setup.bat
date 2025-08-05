@echo off
echo 🎤 Meeting Transcriber Setup Script
echo ==================================

REM Check if Python is installed
python --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Python is not installed. Please install Python 3.7+ first.
    pause
    exit /b 1
)

echo ✅ Python found: 
python --version

REM Create virtual environment
echo 📦 Creating virtual environment...
python -m venv venv

REM Activate virtual environment
echo 🔧 Activating virtual environment...
call venv\Scripts\activate.bat

REM Install dependencies
echo 📚 Installing dependencies...
pip install -r requirements.txt

REM Create .env file if it doesn't exist
if not exist .env (
    echo 🔑 Creating .env file...
    copy env_example.txt .env
    echo ⚠️  IMPORTANT: Please edit .env file and add your OpenAI API key!
    echo    Get your API key from: https://platform.openai.com/api-keys
) else (
    echo ✅ .env file already exists
)

REM Create uploads directory
if not exist uploads (
    echo 📁 Creating uploads directory...
    mkdir uploads
)

echo.
echo 🎉 Setup complete!
echo.
echo Next steps:
echo 1. Edit .env file and add your OpenAI API key
echo 2. Set up billing at: https://platform.openai.com/account/billing
echo 3. Run: venv\Scripts\activate && python app.py
echo 4. Open browser to: http://localhost:5000
echo.
pause 