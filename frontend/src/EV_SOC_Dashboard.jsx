import { useState, useEffect, useRef } from 'react';
import { Battery, Zap, Thermometer, Activity, Gauge, AlertTriangle, CheckCircle, PlayCircle, StopCircle } from 'lucide-react';
import axios from 'axios';

function EVDashboard() {
  // --- MODES ---
  const [isSimulating, setIsSimulating] = useState(false); // Manual vs Batch Mode

  // --- CONTROLS ---
  const [throttle, setThrottle] = useState(0);
  const [brake, setBrake] = useState(0);
  const [regenBraking, setRegenBraking] = useState(50);
  const [ambientTemp, setAmbientTemp] = useState(25);

  // --- UI STATE ---
  const [vehicleSpeed, setVehicleSpeed] = useState(0);
  const [batteryCurrent, setBatteryCurrent] = useState(0);
  const [batteryVoltage, setBatteryVoltage] = useState(400);
  const [batteryTemp, setBatteryTemp] = useState(25);
  const [soc, setSoc] = useState(80);
  const [referenceSoc, setReferenceSoc] = useState(80);
  const [isConnected, setIsConnected] = useState(false);

  // --- GRAPHS ---
  const [currentHistory, setCurrentHistory] = useState(Array(50).fill(0));
  const [voltageHistory, setVoltageHistory] = useState(Array(50).fill(400));
  const [socHistory, setSocHistory] = useState(Array(50).fill(80));

  // --- PHYSICS & SIMULATION MEMORY ---
  const physicsSocRef = useRef(80);
  const currentRef = useRef(0);
  const speedRef = useRef(0);
  
  const animationRef = useRef(null);
  const lastTimeRef = useRef(Date.now());
  const lastApiCallTimeRef = useRef(0);

  // Playback Memory
  const simulationDataRef = useRef(null); // Stores the full batch result
  const playbackIndexRef = useRef(0);

  // --- CONFIGURATION ---
  const TIME_WARP = 10;
  const BATTERY_CAPACITY = 27;
  const MAX_CURRENT = 300;

  // =================================================================
  // 1. GENERATE DRIVE CYCLE (The "Simulation" Data)
  // =================================================================
  const generateDriveCycle = () => {
    const steps = 100; // 100 data points (e.g., 60 seconds)
    const currents = [];
    const voltages = [];
    const temps = [];
    
    let simSoc = 80; // Start at 80%
    let simTemp = 25;

    for (let i = 0; i < steps; i++) {
        // --- CREATE A SCENARIO ---
        // 0-20:  Heavy Acceleration (Discharge)
        // 20-50: Cruising (Light Discharge)
        // 50-70: Hard Braking (Regen/Charge)
        // 70-100: Idle
        let i_val = 0;
        if (i < 20) i_val = -250;       // Discharge (Negative)
        else if (i < 50) i_val = -50;   // Cruise
        else if (i < 70) i_val = 150;   // Regen (Positive)
        else i_val = 0;                 // Idle

        // Noise
        i_val += (Math.random() - 0.5) * 10;

        // Calculate Voltage based on physics (same formula as manual mode)
        // dSOC = I * dt / Capacity
        simSoc -= ((-1 * i_val) * 1.0) / (BATTERY_CAPACITY * 3600) * 100 * 5; // *5 for speed
        const ocv = 300 + simSoc;
        const sag = (-1 * i_val) * 0.1; // Resistance = 0.1
        const v_val = ocv - sag;

        // Temperature (Heating)
        simTemp += Math.abs(i_val) * 0.005;

        currents.push(i_val);
        voltages.push(v_val);
        temps.push(simTemp);
    }
    return { currents, voltages, temps };
  };

  const runSimulation = async () => {
    setIsSimulating(true);
    playbackIndexRef.current = 0;

    // 1. Generate Data
    const data = generateDriveCycle();
    
    try {
        // 2. Send BATCH to Python
        const response = await axios.post('http://localhost:8000/simulate', {
            current: data.currents,
            voltage: data.voltages,
            temperature: data.temps
        });

        // 3. Store Results for Playback
        simulationDataRef.current = {
            currents: data.currents,
            voltages: data.voltages,
            temps: data.temps,
            socs: response.data.soc // The Array from Python
        };
        setIsConnected(true);

    } catch (error) {
        console.error("Batch Failed", error);
        setIsConnected(false);
        setIsSimulating(false);
    }
  };

  const stopSimulation = () => {
      setIsSimulating(false);
      simulationDataRef.current = null;
  };

  // =================================================================
  // 2. MAIN LOOP (Handles both Manual & Simulation Playback)
  // =================================================================
  useEffect(() => {
    const loop = async () => {
      const now = Date.now();
      const deltaTime = (now - lastTimeRef.current) / 1000;
      lastTimeRef.current = now;

      if (isSimulating && simulationDataRef.current) {
         // --- PLAYBACK MODE ---
         // Advance frames
         if (now - lastApiCallTimeRef.current > 100) { // 10 FPS playback
             lastApiCallTimeRef.current = now;
             const idx = playbackIndexRef.current;
             const data = simulationDataRef.current;

             if (idx < data.socs.length) {
                 // Update UI with pre-calculated data
                 setBatteryCurrent(Math.abs(data.currents[idx])); // Show abs for UI
                 setBatteryVoltage(data.voltages[idx]);
                 setBatteryTemp(data.temps[idx]);
                 setSoc(data.socs[idx]); // The Python Result
                 
                 // Update Graphs
                 setCurrentHistory(p => [...p.slice(1), Math.abs(data.currents[idx])]);
                 setVoltageHistory(p => [...p.slice(1), data.voltages[idx]]);
                 setSocHistory(p => [...p.slice(1), data.socs[idx]]);

                 playbackIndexRef.current += 1;
             } else {
                 setIsSimulating(false); // End of tape
             }
         }

      } else {
         // --- MANUAL PHYSICS MODE (Your original logic) ---
         // 1. Speed & Current
         const targetSpeed = throttle > brake ? throttle * 1.6 : Math.max(0, speedRef.current - brake * 0.8);
         speedRef.current = speedRef.current + (targetSpeed - speedRef.current) * 0.05;
         
         let targetCurrent = 0;
         if (throttle > 0) targetCurrent = (throttle / 100) * MAX_CURRENT; // Discharge (Positive in UI Logic)
         else if (brake > 0) targetCurrent = -1 * ((brake * 1.5 + regenBraking) / 100) * 100;
         
         currentRef.current = currentRef.current + (targetCurrent - currentRef.current) * 0.1;

         // 2. SOC (Math)
         const socChange = (currentRef.current * deltaTime * TIME_WARP) / (BATTERY_CAPACITY * 3600) * 100;
         physicsSocRef.current = Math.max(0, Math.min(100, physicsSocRef.current - socChange));

         // 3. Voltage
         const ocv = 300 + physicsSocRef.current;
         const resistance = 0.1; 
         const sag = currentRef.current * resistance; 
         const noise = (Math.random() - 0.5) * 0.5;
         const simulatedVoltage = ocv - sag + noise;
         
         // 4. Temp
         const heatGen = Math.abs(currentRef.current) * 0.05;
         const newTemp = batteryTemp + (heatGen - (batteryTemp - ambientTemp) * 0.1) * deltaTime * 0.5;

         // 5. Update UI
         setVehicleSpeed(speedRef.current);
         setBatteryCurrent(currentRef.current);
         setBatteryVoltage(simulatedVoltage);
         setBatteryTemp(newTemp);
         setReferenceSoc(physicsSocRef.current);

         // 6. Python API (Single Value)
         if (now - lastApiCallTimeRef.current > 200) {
            lastApiCallTimeRef.current = now;
            // Send Negative for Discharge to match Backend
            const currentForAI = -1 * currentRef.current; 
            try {
                const response = await axios.post('http://localhost:8000/predict', {
                    current: currentForAI,
                    voltage: simulatedVoltage,
                    temperature: newTemp
                });
                setSoc(response.data.soc);
                setIsConnected(true);
            } catch (e) { setIsConnected(false); setSoc(physicsSocRef.current); }
         }
         
         // Graph Updates
         setCurrentHistory(p => [...p.slice(1), currentRef.current]);
         setVoltageHistory(p => [...p.slice(1), simulatedVoltage]);
         setSocHistory(p => [...p.slice(1), soc]);
      }

      animationRef.current = requestAnimationFrame(loop);
    };
    animationRef.current = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(animationRef.current);
  }, [throttle, brake, isSimulating, ambientTemp, batteryTemp, soc]);

  // --- CHART COMPONENT ---
  const LineChart = ({ data, color, min, max, unit }) => {
    const autoMin = min !== undefined ? min : Math.floor(Math.min(...data));
    const autoMax = max !== undefined ? max : Math.ceil(Math.max(...data));
    const width = 100, height = 50;
    const getPath = (dataset) => {
      if (!dataset.length) return '';
      return 'M ' + dataset.map((v, i) => {
        const x = (i / (dataset.length - 1)) * width;
        const y = height - ((v - autoMin) / (autoMax - autoMin || 1)) * height;
        return `${x},${y}`;
      }).join(' L ');
    };
    return (
      <div className="relative h-24 w-full">
        <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-full overflow-visible" preserveAspectRatio="none">
          <path d={getPath(data)} fill="none" stroke={color} strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
        </svg>
        <div className="flex justify-between text-xs text-gray-400 mt-1">
           <span>{autoMin.toFixed(0)}{unit}</span>
           <span>{autoMax.toFixed(0)}{unit}</span>
        </div>
      </div>
    );
  };

  const ControlSlider = ({ label, val, setVal, color, icon: Icon, disabled }) => (
    <div className={`bg-white p-4 rounded-xl border border-gray-100 shadow-sm ${disabled ? 'opacity-50 pointer-events-none' : ''}`}>
      <div className="flex justify-between mb-2">
        <span className="flex items-center gap-2 font-medium text-gray-700">
          <Icon size={16} className={`text-${color}-500`} /> {label}
        </span>
        <span className="font-bold text-gray-900">{val}%</span>
      </div>
      <input type="range" min="0" max="100" value={val} onChange={e => setVal(Number(e.target.value))} className={`w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-${color}-500`}/>
    </div>
  );

  return (
    <div className="min-h-screen bg-slate-50 p-6 font-sans text-slate-800">
      <div className="max-w-6xl mx-auto space-y-6">
        
        {/* HEADER */}
        <div className="flex flex-col md:flex-row justify-between items-center bg-white p-6 rounded-2xl shadow-sm border border-slate-200">
          <div>
            <h1 className="text-2xl font-bold flex items-center gap-2">
              <Zap className="text-yellow-500" fill="currentColor" /> 
              EV Battery Digital Twin
            </h1>
            <div className="flex items-center gap-2 mt-2 text-sm">
              <span className={`flex items-center gap-1 px-2 py-0.5 rounded-full ${isConnected ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'}`}>
                {isConnected ? <CheckCircle size={12}/> : <AlertTriangle size={12}/>}
                {isConnected ? "Model Online" : "Model Offline"}
              </span>
              <span className="text-slate-400">|</span>
              <span className="font-bold text-slate-600">{isSimulating ? "MODE: BATCH SIMULATION" : "MODE: MANUAL DRIVE"}</span>
            </div>
          </div>
          
          {/* SIMULATION CONTROLS */}
          <div className="flex gap-3">
              {!isSimulating ? (
                  <button onClick={runSimulation} className="flex items-center gap-2 bg-indigo-600 hover:bg-indigo-700 text-white px-6 py-3 rounded-xl font-bold transition-all shadow-md">
                      <PlayCircle size={20}/> Run Drive Cycle Test
                  </button>
              ) : (
                  <button onClick={stopSimulation} className="flex items-center gap-2 bg-red-500 hover:bg-red-600 text-white px-6 py-3 rounded-xl font-bold transition-all shadow-md">
                      <StopCircle size={20}/> Stop Simulation
                  </button>
              )}
          </div>
        </div>

        {/* DASHBOARD GRID */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          <div className="lg:col-span-4 space-y-4">
            <div className="flex items-center gap-2 font-bold text-lg text-slate-700"><Gauge size={20}/> Controls</div>
            <ControlSlider label="Throttle" val={throttle} setVal={setThrottle} color="blue" icon={Zap} disabled={isSimulating} />
            <ControlSlider label="Brake" val={brake} setVal={setBrake} color="red" icon={Activity} disabled={isSimulating} />
            <div className="bg-white p-4 rounded-xl border border-gray-100 shadow-sm">
               <div className="text-2xl font-bold text-center text-slate-300">
                   {isSimulating ? "AUTO-PILOT ACTIVE" : "MANUAL OVERRIDE"}
               </div>
            </div>
          </div>

          <div className="lg:col-span-4 space-y-4">
            <div className="flex items-center gap-2 font-bold text-lg text-slate-700"><Activity size={20}/> Telemetry</div>
            <div className="bg-white p-4 rounded-xl border border-gray-100 shadow-sm">
               <div className="text-sm text-slate-500 mb-1">Current</div>
               <div className="text-2xl font-bold mb-2">{batteryCurrent.toFixed(1)} A</div>
               <LineChart data={currentHistory} color="#3b82f6" unit="A" />
            </div>
            <div className="bg-white p-4 rounded-xl border border-gray-100 shadow-sm">
               <div className="text-sm text-slate-500 mb-1">Voltage</div>
               <div className="text-2xl font-bold mb-2">{batteryVoltage.toFixed(1)} V</div>
               <LineChart data={voltageHistory} color="#10b981" unit="V" />
            </div>
          </div>

          <div className="lg:col-span-4">
              <div className="bg-slate-900 text-white p-6 rounded-2xl shadow-lg h-full flex flex-col">
                 <h2 className="font-bold text-xl flex items-center gap-2 mb-6"><Battery className="text-purple-400"/> AI Prediction</h2>
                 <div className="flex-1 flex flex-col justify-center items-center relative mb-8">
                    <div className="w-48 h-48 rounded-full border-8 border-slate-800 flex items-center justify-center relative overflow-hidden">
                       <div className="text-center z-10 relative">
                          <div className="text-5xl font-black">{soc.toFixed(1)}%</div>
                          <div className="text-xs text-slate-400 mt-1">Range: {(soc * 3.8).toFixed(0)} km</div>
                       </div>
                       <div className="absolute bottom-0 w-full bg-purple-600 opacity-50 transition-all duration-300" style={{height: `${soc}%`}}></div>
                    </div>
                 </div>
                 <div className="h-32 bg-slate-800 rounded-xl p-2 border border-slate-700">
                    <LineChart data={socHistory} color="#a855f7" min={0} max={100} unit="%" />
                 </div>
              </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default EVDashboard;