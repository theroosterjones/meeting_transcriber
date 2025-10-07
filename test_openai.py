#!/usr/bin/env python3

import os
from dotenv import load_dotenv
from openai import OpenAI

# Load environment variables
load_dotenv()

# Configure OpenAI
client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

def test_openai_connection():
    """Test OpenAI API connection"""
    try:
        print("Testing OpenAI API connection...")
        print(f"API Key: {os.getenv('OPENAI_API_KEY')[:20]}...")
        
        # Test with a simple text completion
        response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": "Hello, this is a test."}],
            max_tokens=10
        )
        
        print("✅ OpenAI API connection successful!")
        print(f"Response: {response.choices[0].message.content}")
        return True
        
    except Exception as e:
        print(f"❌ OpenAI API connection failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_whisper_api():
    """Test Whisper API specifically"""
    try:
        print("\nTesting Whisper API...")
        
        # Create a simple test audio file (1 second of silence)
        import numpy as np
        import wave
        
        # Create a simple WAV file
        sample_rate = 16000
        duration = 1  # 1 second
        samples = np.zeros(sample_rate * duration, dtype=np.int16)
        
        with wave.open('test_audio.wav', 'w') as wav_file:
            wav_file.setnchannels(1)  # Mono
            wav_file.setsampwidth(2)  # 16-bit
            wav_file.setframerate(sample_rate)
            wav_file.writeframes(samples.tobytes())
        
        print("Created test audio file")
        
        # Test Whisper API
        with open('test_audio.wav', 'rb') as audio_file:
            transcript = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file
            )
        
        print("✅ Whisper API test successful!")
        print(f"Transcript: {transcript.text}")
        
        # Clean up
        os.remove('test_audio.wav')
        return True
        
    except Exception as e:
        print(f"❌ Whisper API test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("=== OpenAI API Test ===")
    
    # Test basic connection
    connection_ok = test_openai_connection()
    
    if connection_ok:
        # Test Whisper specifically
        whisper_ok = test_whisper_api()
        
        if whisper_ok:
            print("\n🎉 All tests passed! Your OpenAI setup is working correctly.")
        else:
            print("\n⚠️  Basic API works but Whisper may have issues.")
    else:
        print("\n❌ OpenAI API connection failed. Check your API key and internet connection.") 