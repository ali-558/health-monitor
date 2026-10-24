from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime
from typing import Optional

# Initialize Firebase
cred = credentials.Certificate("serviceAccountKey.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

app = FastAPI(title="Healthcare Monitoring AI 🏥")

# Data model
class SensorData(BaseModel):
    userId: str
    deviceID: str
    ecg: float
    ppg: float  # Heart rate
    temperature: float
    spo2: Optional[float] = None

@app.get("/")
def root():
    return {
        "message": "Healthcare AI Server Running! 🏥",
        "status": "online",
        "version": "1.0"
    }

@app.post("/analyze")
def analyze_and_store(data: SensorData):
    """
    Receive and analyze sensor data
    """
    try:
        print(f"\n📊 Analyzing data from device: {data.deviceID}")
        print(f"   HR: {data.ppg} bpm")
        print(f"   Temp: {data.temperature}°C")
        print(f"   SpO2: {data.spo2}%")
        
        # Simple AI analysis
        status = "Normal"
        advice = "All vitals within normal range."
        
        if data.ppg < 40 or data.ppg > 130:
            status = "Critical"
            advice = "⚠️ Critical heart rate detected! Seek medical attention."
        elif data.temperature > 38.5:
            status = "Warning"
            advice = "⚡ Elevated temperature detected. Monitor closely."
        elif data.spo2 and data.spo2 < 94:
            status = "Warning"
            advice = "⚡ Low oxygen saturation. Consult a doctor."
        
        # Store in Firebase
        user_ref = db.collection('users').document(data.userId)
        
        reading_data = {
            'deviceID': data.deviceID,
            'ecg': data.ecg,
            'ppg': data.ppg,
            'temperature': data.temperature,
            'spo2': data.spo2,
            'timestamp': datetime.now(),
            'anomalyDetected': status != "Normal",
            'aiFeedback': advice
        }
        
        reading_ref = user_ref.collection('readings').add(reading_data)
        reading_id = reading_ref[1].id
        
        # Store AI result
        ai_result_data = {
            'status': status,
            'advice': advice,
            'model': 'basic_threshold_v1',
            'confidence': 0.95,
            'timestamp': datetime.now(),
            'relatedReadingID': reading_id
        }
        
        ai_result_ref = user_ref.collection('ai_results').add(ai_result_data)
        
        print(f"✅ Stored reading: {reading_id}")
        print(f"✅ Status: {status}")
        
        return {
            "success": True,
            "readingID": reading_id,
            "aiResultID": ai_result_ref[1].id,
            "analysis": {
                "status": status,
                "advice": advice,
                "confidence": 0.95
            }
        }
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/user/{userId}/latest")
def get_latest(userId: str):
    """Get latest reading and AI analysis"""
    try:
        user_ref = db.collection('users').document(userId)
        
        # Get latest reading
        readings = user_ref.collection('readings')\
            .order_by('timestamp', direction=firestore.Query.DESCENDING)\
            .limit(1).get()
        
        if not readings:
            return {"error": "No readings found"}
        
        latest_reading = readings[0].to_dict()
        
        # Get latest AI result
        ai_results = user_ref.collection('ai_results')\
            .order_by('timestamp', direction=firestore.Query.DESCENDING)\
            .limit(1).get()
        
        latest_ai = ai_results[0].to_dict() if ai_results else None
        
        return {
            "reading": latest_reading,
            "ai_analysis": latest_ai
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    print("\n🚀 Starting Healthcare AI Server...")
    print("📡 Server: http://127.0.0.1:8000")
    print("📚 API Docs: http://127.0.0.1:8000/docs")
    uvicorn.run(app, host="0.0.0.0", port=8000)


