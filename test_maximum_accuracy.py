#!/usr/bin/env python3
"""
Comprehensive Test Suite for Maximum Accuracy
Tests 12 scenarios covering all edge cases
Target: 90-95% accuracy
"""

import requests
import json
import time

API_URL = "http://localhost:8000/analyze"

# Comprehensive test cases
test_cases = [
    # NORMAL CASES (2 tests)
    {
        "name": "✅ Normal #1 - Perfect Health",
        "userId": "test_user",
        "deviceID": "test_001",
        "ppg": 72,
        "temperature": 36.8,
        "spo2": 98,
        "ecg": 72,
        "expected": "NORMAL",
        "category": "normal"
    },
    {
        "name": "✅ Normal #2 - Borderline Healthy",
        "userId": "test_user",
        "deviceID": "test_002",
        "ppg": 95,  # Near upper limit but still normal
        "temperature": 37.0,
        "spo2": 96,
        "ecg": 95,
        "expected": "NORMAL",
        "category": "normal"
    },
    
    # WARNING CASES - Heart Rate (2 tests)
    {
        "name": "⚠️  Warning #1 - Elevated Heart Rate",
        "userId": "test_user",
        "deviceID": "test_003",
        "ppg": 105,  # Mildly elevated
        "temperature": 36.8,
        "spo2": 98,
        "ecg": 105,
        "expected": "WARNING",
        "category": "warning_hr"
    },
    {
        "name": "⚠️  Warning #2 - High Normal HR",
        "userId": "test_user",
        "deviceID": "test_004",
        "ppg": 115,  # Near critical but still warning
        "temperature": 36.9,
        "spo2": 97,
        "ecg": 115,
        "expected": "WARNING",
        "category": "warning_hr"
    },
    
    # WARNING CASES - Temperature (3 tests)
    {
        "name": "⚠️  Warning #3 - Low Grade Fever",
        "userId": "test_user",
        "deviceID": "test_005",
        "ppg": 85,
        "temperature": 37.5,  # Slightly elevated
        "spo2": 97,
        "ecg": 85,
        "expected": "WARNING",
        "category": "warning_temp"
    },
    {
        "name": "⚠️  Warning #4 - Fever",
        "userId": "test_user",
        "deviceID": "test_006",
        "ppg": 88,
        "temperature": 39.0,  # Clear fever
        "spo2": 97,
        "ecg": 88,
        "expected": "WARNING",
        "category": "warning_temp"
    },
    {
        "name": "⚠️  Warning #5 - High Fever",
        "userId": "test_user",
        "deviceID": "test_007",
        "ppg": 90,
        "temperature": 39.8,  # Near critical
        "spo2": 96,
        "ecg": 90,
        "expected": "WARNING",
        "category": "warning_temp"
    },
    
    # WARNING CASES - SpO2 (2 tests)
    {
        "name": "⚠️  Warning #6 - Mild Low Oxygen",
        "userId": "test_user",
        "deviceID": "test_008",
        "ppg": 78,
        "temperature": 36.7,
        "spo2": 93,  # Below 95
        "ecg": 78,
        "expected": "WARNING",
        "category": "warning_spo2"
    },
    {
        "name": "⚠️  Warning #7 - Low Oxygen",
        "userId": "test_user",
        "deviceID": "test_009",
        "ppg": 80,
        "temperature": 36.8,
        "spo2": 91,  # Near critical
        "ecg": 80,
        "expected": "WARNING",
        "category": "warning_spo2"
    },
    
    # CRITICAL CASES (3 tests)
    {
        "name": "🚨 Critical #1 - Severe Tachycardia",
        "userId": "test_user",
        "deviceID": "test_010",
        "ppg": 135,  # Very high
        "temperature": 37.0,
        "spo2": 98,
        "ecg": 135,
        "expected": "CRITICAL",
        "category": "critical_hr"
    },
    {
        "name": "🚨 Critical #2 - Severe Hypoxia",
        "userId": "test_user",
        "deviceID": "test_011",
        "ppg": 80,
        "temperature": 36.8,
        "spo2": 88,  # Critically low
        "ecg": 80,
        "expected": "CRITICAL",
        "category": "critical_spo2"
    },
    {
        "name": "🚨 Critical #3 - Hyperpyrexia",
        "userId": "test_user",
        "deviceID": "test_012",
        "ppg": 85,
        "temperature": 40.5,  # Dangerously high
        "spo2": 96,
        "ecg": 85,
        "expected": "CRITICAL",
        "category": "critical_temp"
    }
]

def run_comprehensive_tests():
    print("="*70)
    print("🧪 COMPREHENSIVE ACCURACY TEST")
    print("🎯 Target: 90-95% Accuracy (11-12 correct out of 12)")
    print("="*70)
    print()
    
    # Check server
    try:
        response = requests.get("http://localhost:8000/")
        server_info = response.json()
        print(f"✅ Server online: {server_info.get('message', 'Unknown')}")
        print(f"   Target Accuracy: {server_info.get('target_accuracy', 'Unknown')}")
        print()
    except:
        print("❌ ERROR: Server not running!")
        print("Start server: python main_maximum_accuracy.py")
        return
    
    results = []
    correct = 0
    total = len(test_cases)
    
    # Category tracking
    categories = {
        "normal": {"correct": 0, "total": 0},
        "warning_hr": {"correct": 0, "total": 0},
        "warning_temp": {"correct": 0, "total": 0},
        "warning_spo2": {"correct": 0, "total": 0},
        "critical_hr": {"correct": 0, "total": 0},
        "critical_spo2": {"correct": 0, "total": 0},
        "critical_temp": {"correct": 0, "total": 0}
    }
    
    for i, test in enumerate(test_cases, 1):
        category = test.get('category', 'unknown')
        print(f"Test {i}/{total}: {test['name']}")
        print(f"   Vitals: HR={test['ppg']}, Temp={test['temperature']}°C, SpO2={test['spo2']}%")
        
        try:
            response = requests.post(API_URL, json=test, timeout=30)
            
            if response.status_code == 200:
                result = response.json()
                analysis = result.get('analysis', {})
                
                status = analysis.get('status', 'UNKNOWN')
                confidence = analysis.get('confidence', 0)
                advice = analysis.get('advice', '')
                processing_time = analysis.get('processing_time', 0)
                unanimous = analysis.get('unanimous', False)
                votes = analysis.get('votes', {})
                
                is_correct = status == test['expected']
                correct += is_correct
                
                # Track by category
                if category in categories:
                    categories[category]['total'] += 1
                    if is_correct:
                        categories[category]['correct'] += 1
                
                # Store result
                results.append({
                    "test": test['name'],
                    "category": category,
                    "expected": test['expected'],
                    "got": status,
                    "correct": is_correct,
                    "confidence": confidence,
                    "time": processing_time,
                    "unanimous": unanimous,
                    "votes": votes
                })
                
                # Print result
                if is_correct:
                    unanimous_str = " [UNANIMOUS]" if unanimous else ""
                    print(f"   ✅ PASS{unanimous_str} - {status} (Conf: {confidence:.2f})")
                else:
                    print(f"   ❌ FAIL - Expected: {test['expected']}, Got: {status}")
                
                if votes:
                    print(f"   🗳️  Votes: {votes}")
                print(f"   💬 {advice[:100]}...")
                print(f"   ⏱️  {processing_time}s")
                
            else:
                print(f"   ❌ ERROR - HTTP {response.status_code}")
                results.append({
                    "test": test['name'],
                    "expected": test['expected'],
                    "got": "ERROR",
                    "correct": False
                })
        
        except Exception as e:
            print(f"   ❌ EXCEPTION: {e}")
            results.append({
                "test": test['name'],
                "expected": test['expected'],
                "got": "EXCEPTION",
                "correct": False
            })
        
        print()
        time.sleep(0.3)
    
    # Calculate metrics
    accuracy = (correct / total) * 100
    valid_results = [r for r in results if r.get('time', 0) > 0]
    avg_time = sum(r['time'] for r in valid_results) / len(valid_results) if valid_results else 0
    avg_confidence = sum(r.get('confidence', 0) for r in valid_results) / len(valid_results) if valid_results else 0
    unanimous_count = sum(1 for r in results if r.get('unanimous', False))
    
    # Print summary
    print("="*70)
    print("📊 FINAL RESULTS")
    print("="*70)
    print(f"✅ Tests Passed: {correct}/{total}")
    print(f"🎯 Accuracy: {accuracy:.1f}%")
    print(f"🤝 Unanimous Votes: {unanimous_count}/{total}")
    print(f"📈 Average Confidence: {avg_confidence:.2f}")
    print(f"⏱️  Average Time: {avg_time:.2f}s")
    print()
    
    # Category breakdown
    print("📋 Accuracy by Category:")
    for cat_name, cat_data in categories.items():
        if cat_data['total'] > 0:
            cat_acc = (cat_data['correct'] / cat_data['total']) * 100
            status_icon = "✅" if cat_acc >= 90 else "⚠️" if cat_acc >= 75 else "❌"
            print(f"   {status_icon} {cat_name}: {cat_data['correct']}/{cat_data['total']} ({cat_acc:.0f}%)")
    print()
    
    # Detailed results
    print("📝 Detailed Test Results:")
    for r in results:
        status_icon = "✅" if r['correct'] else "❌"
        unanimous_mark = " [U]" if r.get('unanimous') else ""
        print(f"{status_icon} {r['test']}{unanimous_mark}")
        print(f"   Expected: {r['expected']} | Got: {r['got']} | Conf: {r.get('confidence', 0):.2f}")
    
    print()
    print("="*70)
    
    # Performance assessment
    if accuracy >= 91.7:  # 11/12 or 12/12
        print("🎉🎉🎉 OUTSTANDING! 90-95% TARGET ACHIEVED!")
        print("   This exceeds commercial device standards!")
        print("   Perfect for capstone presentation!")
    elif accuracy >= 83.3:  # 10/12
        print("✅ EXCELLENT! Very close to target!")
        print("   83%+ is competitive with consumer devices.")
        print("   More than sufficient for capstone.")
    elif accuracy >= 75:  # 9/12
        print("✅ GOOD! Solid performance.")
        print("   75%+ demonstrates capability.")
        print("   Acceptable for capstone.")
    else:
        print("⚠️  Needs improvement.")
        print("   Consider reviewing failing test cases.")
    
    print("="*70)
    
    # Recommendations
    if accuracy < 91.7:
        print("\n💡 To Improve Further:")
        failed_tests = [r for r in results if not r['correct']]
        if failed_tests:
            print("   Failed tests:")
            for r in failed_tests:
                print(f"   - {r['test']}")
        print("   Consider: Fine-tuning weights or adding BioMistral model")
    
    return accuracy

if __name__ == "__main__":
    accuracy = run_comprehensive_tests()
