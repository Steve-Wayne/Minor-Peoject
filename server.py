import json
import numpy as np
from fastapi import FastAPI
from pydantic import BaseModel
from typing import List
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- LOAD MATLAB MODEL ---
try:
    with open('model_params.json', 'r') as f:
        params = json.load(f)
    print("✔ Model parameters loaded.")
except FileNotFoundError:
    print("ERROR: 'model_params.json' not found.")
    exit(1)

# LOAD WEIGHTS
IW = np.array(params['IW'])              
LW = np.array(params['LW'])              
b1 = np.array(params['b1']).reshape(-1, 1) 
b2 = np.array(params['b2']).reshape(-1, 1) 

# LOAD SCALING LIMITS
x_min = np.array(params['x_min']).reshape(-1, 1)
x_max = np.array(params['x_max']).reshape(-1, 1)
y_min = params['y_min']
y_max = params['y_max']

def run_neural_net_batch(currents, temps, voltages):
    # Convert lists to NumPy arrays
    currents = np.array(currents)
    temps = np.array(temps)
    
    # CRITICAL: Convert Pack Voltage (e.g. 380V) to Cell Voltage (e.g. 3.9V)
    # Assuming 96 series cells
    cell_voltages = np.array(voltages) / 96.0

    # 1. Prepare Input Matrix (3 x N)
    # Stack them vertically so each column is one time-step
    X = np.vstack([currents, temps, cell_voltages])

    # 2. Clamp Inputs (Broadcasting works automatically)
    X_clamped = np.maximum(x_min, np.minimum(x_max, X))

    # 3. Normalize (-1 to 1)
    X_norm = 2.0 * (X_clamped - x_min) / (x_max - x_min) - 1.0
    
    # 4. Neural Network (Matrix Multiplication handles the batch!)
    # Layer 1
    Z = np.tanh(np.dot(IW, X_norm) + b1)
    # Layer 2
    Y_norm = np.dot(LW, Z) + b2
    
    # 5. Denormalize
    soc_fraction = (Y_norm - (-1.0)) * (y_max - y_min) / (1.0 - (-1.0)) + y_min
    
    # 6. Convert to Percentage
    if y_max < 2.0:
        soc_percent = soc_fraction * 100.0
    else:
        soc_percent = soc_fraction

    # Flatten result to a simple list [80.1, 79.9, ...]
    return soc_percent.flatten().tolist()

# --- DATA MODELS ---

# Single Value Model (For Manual Mode)
class InputData(BaseModel):
    current: float
    voltage: float
    temperature: float

# Batch Model (For Drive Cycle Mode)
class DriveCycleData(BaseModel):
    current: List[float]
    voltage: List[float]
    temperature: List[float]

# --- ENDPOINTS ---

@app.post("/predict")
async def predict_single(data: InputData):
    # Re-use the batch logic for single item (simpler maintenance)
    result = run_neural_net_batch([data.current], [data.temperature], [data.voltage])
    return {"soc": max(0, min(100, result[0]))}

@app.post("/simulate")
async def predict_cycle(data: DriveCycleData):
    try:
        soc_results = run_neural_net_batch(data.current, data.temperature, data.voltage)
        # Clamp all results 0-100
        soc_results = [max(0, min(100, s)) for s in soc_results]
        
        print(f"✔ Processed Batch: {len(soc_results)} points.")
        return {"soc": soc_results}
    except Exception as e:
        print(f"Error: {e}")
        return {"soc": []}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)