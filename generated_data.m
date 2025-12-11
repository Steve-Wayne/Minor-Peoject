%% ---------------------------------------------------------
% AI Gas Gauge - CLEAN FINAL SCRIPT (Corrected)
% Uses last simulation SOC as next initial SOC
% ---------------------------------------------------------
clear; clc;

modelName = 'Data_generationscheme';   % your Simulink model

num_simulations = 30;
duration = 1000;
dt = 0.5;

% Current limits (your reversed polarity is fine)
I_max_charge    = 10;
I_max_discharge = -60;

% Create folder
if ~exist('TrainingData','dir')
    mkdir TrainingData
end

% Load model
if ~bdIsLoaded(modelName)
    load_system(modelName);
end
set_param(modelName, 'FastRestart', 'off');

fprintf('\nStarting Data Generation for %d runs...\n', num_simulations);

%% ------------------- INITIAL SOC ------------------------
SOC_last = 0.50;   % 50% SOC at first run

% Enable SOC specification for Table-Based Battery
set_param([modelName '/Battery (Table-Based)'], ...
          'stateOfCharge_specify', 'on');

set_param([modelName '/Battery (Table-Based)'], ...
          'stateOfCharge_priority', 'Low');

set_param([modelName '/Battery (Table-Based)'], ...
          'stateOfCharge', num2str(SOC_last));

%% ========================================================
for k = 1:num_simulations

    %% 1) Generate random current profile
    time_vec = (0:dt:duration)';
    base_load = 3 * sin(0.002 * time_vec);
    pulses    = 6 * (rand(size(time_vec)) - 0.5);
    noise     = 1.5 * randn(size(time_vec));

    current_profile_raw = base_load + pulses + noise;
    current_profile = min(max(current_profile_raw, I_max_discharge), I_max_charge);
    Drive_Cycle = timeseries(current_profile, time_vec);

    %% 2) Random temperature
    temp_C = randi([5 40]);
    Input_Temp = temp_C + 273.15;

    assignin('base','Drive_Cycle', Drive_Cycle);
    assignin('base','Input_Temp', Input_Temp);

    fprintf(' Run %02d | Temp = %2d°C ... ', k, temp_C);

    %% 3) Run simulation
    simOut = sim(modelName, ...
                 'StopTime', num2str(duration), ...
                 'FastRestart', 'off');

    %% 4) Check logsout
    if isempty(simOut.logsout)
        fprintf("Skipped (empty logsout)\n");
        continue
    end

    names = simOut.logsout.getElementNames;
    required = {'Current','Voltage','Temperature','Actual_SOC_Battery'};
    missing  = setdiff(required, names);

    if ~isempty(missing)
        fprintf("Skipped (missing signals: %s)\n", strjoin(missing, ', '));
        continue
    end

    %% 5) Extract signals
    Current      = simOut.logsout.get('Current').Values;
    Voltage      = simOut.logsout.get('Voltage').Values;
    Temperature  = simOut.logsout.get('Temperature').Values;
    ActualSOC    = simOut.logsout.get('Actual_SOC_Battery').Values;

    SOC_clamped = min(max(ActualSOC.Data, 0.05), 0.95);

    %% 6) Save data
    Data.time       = Current.Time;
    Data.current    = Current.Data;
    Data.voltage    = Voltage.Data;
    Data.temp       = Temperature.Data;
    Data.soc        = SOC_clamped;
    Data.temp_const = temp_C;

    save(sprintf('TrainingData/DriveData_%03d.mat', k), 'Data');
    fprintf("Saved.\n");

    %% 7) Set initial SOC for NEXT run
    SOC_last = SOC_clamped(end);   % real SOC
    SOC_last = max(0.05, min(0.95, SOC_last));  

    % write into battery block
    set_param([modelName '/Battery (Table-Based)'], ...
              'stateOfCharge', num2str(SOC_last));

end

fprintf('\n----------------------------------------------\n');
fprintf('Data Generation COMPLETE. Check TrainingData.\n');
fprintf('----------------------------------------------\n');
