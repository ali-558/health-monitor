import requests

# Test data
sensor_data = {
    "userId": "test_user_1",
    "deviceID": "LILYGO_TWATCH_001",
    "ecg": 78,
    "ppg": 75,  # Heart rate
    "temperature": 36.8,
    "spo2": 98
}

print("📤 Sending sensor data...")
response = requests.post("http://127.0.0.1:8000/analyze", json=sensor_data)
result = response.json()

print("\n✅ Response:")
print(f"Status: {result['analysis']['status']}")
print(f"Advice: {result['analysis']['advice']}")
print(f"Reading ID: {result['readingID']}")