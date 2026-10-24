import requests
import time

API_URL = "http://127.0.0.1:8000"

print("="*60)
print("🧪 TESTING HEALTHCARE AI SYSTEM")
print("="*60)

# Test 1: Check if server is running
print("\n[TEST 1] Checking server status...")
try:
    response = requests.get(f"{API_URL}/")
    if response.status_code == 200:
        print("✅ Server is running!")
        print(f"   {response.json()}")
    else:
        print(f"❌ Server returned status: {response.status_code}")
except Exception as e:
    print(f"❌ Cannot connect to server: {e}")
    print("   Make sure you run: python main.py")
    exit(1)

# Test Cases
test_cases = [
    {
        'name': 'Normal Vitals',
        'data': {
            'userId': 'test_user_1',
            'deviceID': 'LILYGO_TWATCH_001',
            'ecg': 75,
            'ppg': 75,
            'temperature': 36.8,
            'spo2': 98
        },
        'expected': 'Normal'
    },
    {
        'name': 'High Fever',
        'data': {
            'userId': 'test_user_1',
            'deviceID': 'LILYGO_TWATCH_001',
            'ecg': 80,
            'ppg': 95,
            'temperature': 39.0,
            'spo2': 97
        },
        'expected': 'Warning'
    },
    {
        'name': 'Critical Heart Rate',
        'data': {
            'userId': 'test_user_1',
            'deviceID': 'LILYGO_TWATCH_001',
            'ecg': 85,
            'ppg': 160,
            'temperature': 37.0,
            'spo2': 98
        },
        'expected': 'Critical'
    },
    {
        'name': 'Low Oxygen',
        'data': {
            'userId': 'test_user_1',
            'deviceID': 'LILYGO_TWATCH_001',
            'ecg': 78,
            'ppg': 85,
            'temperature': 36.9,
            'spo2': 88
        },
        'expected': 'Warning'
    }
]

correct = 0
total = len(test_cases)

print(f"\n[TEST 2] Running {total} health scenarios...")
print("="*60)

for i, test in enumerate(test_cases, 1):
    print(f"\n🔬 Test {i}/{total}: {test['name']}")
    print(f"   Data: HR={test['data']['ppg']} Temp={test['data']['temperature']}°C SpO2={test['data']['spo2']}%")
    
    try:
        response = requests.post(f"{API_URL}/analyze", json=test['data'])
        
        if response.status_code == 200:
            result = response.json()
            status = result['analysis']['status']
            advice = result['analysis']['advice']
            confidence = result['analysis']['confidence']
            
            print(f"   AI Status: {status}")
            print(f"   AI Advice: {advice[:100]}...")
            print(f"   Confidence: {confidence*100:.0f}%")
            
            if test['expected'].lower() in status.lower():
                print("   ✅ PASS - Correct prediction!")
                correct += 1
            else:
                print(f"   ❌ FAIL - Expected {test['expected']}, got {status}")
        else:
            print(f"   ❌ API Error: {response.status_code}")
    
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    time.sleep(2)  # Wait 2 seconds between tests

# Final Results
print("\n" + "="*60)
print("📊 TEST RESULTS")
print("="*60)
print(f"✅ Passed: {correct}/{total}")
print(f"❌ Failed: {total-correct}/{total}")
accuracy = (correct / total) * 100
print(f"🎯 Accuracy: {accuracy:.1f}%")

if accuracy >= 75:
    print("✅ System is working well!")
else:
    print("⚠️ System needs improvement")

# Test 3: Check Firebase storage
print("\n[TEST 3] Checking Firebase storage...")
try:
    response = requests.get(f"{API_URL}/user/test_user_1/latest")
    if response.status_code == 200:
        data = response.json()
        if 'reading' in data and 'ai_analysis' in data:
            print("✅ Data successfully stored in Firebase!")
            print(f"   Latest reading timestamp: {data['reading'].get('timestamp', 'N/A')}")
        else:
            print("❌ Data format issue")
    else:
        print(f"❌ Cannot fetch data: {response.status_code}")
except Exception as e:
    print(f"❌ Error: {e}")

print("\n" + "="*60)
print("🎉 TESTING COMPLETE!")
print("="*60)
print("\nNext steps:")
print("1. Open dashboard.html in your browser")
print("2. Check Firebase Console to see stored data")
print("3. Take screenshots for your report!")
