%% ---------------------------------------------------------
% AI Gas Gauge - HIGH-VARIATION SOC SCRIPT
% Strong Current Bursts (±300 A) + Stable Bounds
% ---------------------------------------------------------
clear; clc;

modelName = 'Data_generationscheme';

num_simulations = 10;
duration = 1000;
dt = 0.5;

% STRONG high-variation current limits
I_max_charge    = +100;     % positive = charging
I_max_discharge = -300;     % negative = discharging

capacity_Ah = 27;  
capacity_C  = capacity_Ah * 3600;

if ~exist('TrainingData','dir')
    mkdir TrainingData
end

if ~bdIsLoaded(modelName)
    load_system(modelName);
end
set_param(modelName,'FastRestart','off');

fprintf('\nStarting Data Generation...\n');

% Initial SOC start point
SOC_prev = 0.50;

for k = 1:num_simulations

    time_vec = (0:dt:duration)';
    N = length(time_vec);

    %% Build powerful current pattern
    base_profile = ...
          150 * sin(0.01*time_vec) ...       % wide swings
        + 80  * randn(N,1) ...               % noise
        + 240 * (rand(N,1) > 0.92) ...       % bursts +240 A
        - 240 * (rand(N,1) > 0.92);          % bursts –240 A

    % Clamp to limits
    current_raw = min(max(base_profile, I_max_discharge), I_max_charge);

    % Final vector
    current_profile = zeros(N,1);
    soc_est = SOC_prev;

    for i = 1:N

        % limit SOC range
        if soc_est <= 0.02
            current_profile(i) = +150;
        elseif soc_est >= 0.98
            current_profile(i) = -150;
        else
            current_profile(i) = current_raw(i);
        end

        % SOC integrator
        dSOC = current_profile(i) * dt / capacity_C;
        soc_est = soc_est + dSOC;
        soc_est = max(0.02, min(0.98, soc_est));
    end

    SOC_prev = soc_est;

    % Export drive cycle and temperature
    assignin('base','Drive_Cycle', timeseries(current_profile, time_vec));

    temp_C = randi([10 45]);
    assignin('base','Input_Temp', temp_C + 273.15);

    fprintf('Run %02d | Temp = %d°C ... ', k, temp_C);

    %% Run simulation
    simOut = sim(modelName,'StopTime',num2str(duration),'FastRestart','off');

    
    % Extract signals
    Current     = simOut.logsout{2}.Values;
    Voltage     = simOut.logsout{5}.Values;
    Temp        = simOut.logsout{4}.Values;
    SOC         = simOut.logsout{1}.Values;

    SOC_final = min(max(SOC.Data,0.02),0.98);
    SOC_prev  = SOC_final(end);

    % Save
    Data.time    = Current.Time;
    Data.current = Current.Data;
    Data.voltage = Voltage.Data;
    Data.temp    = Temp.Data;
    Data.soc     = SOC_final;

    save(sprintf('TrainingData/DriveData_%03d.mat',k),'Data');

    fprintf("Saved. End SOC = %.3f\n", SOC_prev);
end

fprintf('\n✔ Completed successfully.\n');
