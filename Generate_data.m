%% ---------------------------------------------------------
% AI Gas Gauge - FINAL Stable Data Generation Script
% ---------------------------------------------------------
clear; clc;

modelName = 'Data_generationscheme';

num_simulations = 2;
duration = 36000;
dt = 0.5;

% STRONGER realistic current limits
I_max_charge    = 40;     % charging
I_max_discharge = -60;   % discharging

capacity_Ah = 27;
capacity_C  = capacity_Ah * 3600;

%% Load model
if ~bdIsLoaded(modelName)
    load_system(modelName);
end
set_param(modelName, 'FastRestart', 'off');

%% SOC memory
SOC_prev = 0.50;

fprintf('\nStarting Data Generation...\n');

for k = 1:num_simulations

    %% 1) Time axis
    time_vec = (0:dt:duration)';

    %% 2) Build random current + SOC safety feedback
    base_load = 20 * sin(0.0005 * time_vec);
    pulses    = 60 * (rand(size(time_vec)) - 0.5);
    noise     = 8  * randn(size(time_vec));

    current_raw = base_load + pulses + noise;

    current_profile = zeros(size(time_vec));
    soc_est = SOC_prev;
    for i = 1:length(time_vec)

        % SOC protection
        if soc_est >= 0.98
            current_profile(i) = I_max_discharge * 0.5; % gentle discharge
        elseif soc_est <= 0.05
            current_profile(i) = I_max_charge * 0.5;     % gentle charge
        else
            current_profile(i) = min(max(current_raw(i), ...
                                          I_max_discharge), ...
                                          I_max_charge);
        end

        % SOC update
        dSOC = -current_profile(i) * dt / capacity_C;
        soc_est = max(0.02, min(0.98, soc_est + dSOC));
    end

    SOC_prev = soc_est;

    % Assign signals
    assignin('base','Drive_Cycle', ...
             timeseries(current_profile, time_vec));

    temp_C = randi([5 40]);
    assignin('base','Input_Temp', temp_C + 273.15);

    fprintf("Run %02d | Temp %d°C ... ", k, temp_C);

    %% 3) Run simulation
    simOut = sim(modelName, 'StopTime', num2str(duration), ...
                            'FastRestart','off');

    if isempty(simOut.logsout)
        fprintf("Skipped (logs missing)\n");
        continue;
    end

    % Extract properly by name
    Current     = simOut.logsout.get('Current').Values;
    Voltage     = simOut.logsout.get('Voltage').Values;
    Temperature = simOut.logsout.get('Temperature').Values;
    ActualSOC   = simOut.logsout.get('Actual_SOC_Battery').Values;

    SOC_clamped = min(max(ActualSOC.Data, 0.02), 0.98);
    SOC_prev = SOC_clamped(end);
    
    %% Save dataset
    Data.time       = Current.Time;
    Data.current    = Current.Data;
    Data.voltage    = Voltage.Data;
    Data.temp       = Temperature.Data;
    Data.soc        = SOC_clamped;
    Data.temp_const = temp_C;

    save(sprintf('TrainingData/DriveData_%03d.mat', k), 'Data');

    fprintf("Saved.\n");

end

fprintf('\n----------------------------------------------\n');
fprintf('Data Generation COMPLETE.\n');
fprintf('----------------------------------------------\n');
