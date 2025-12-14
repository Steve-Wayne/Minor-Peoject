clear; clc;

modelName = 'Battery_charge_discharge';

duration = 3600;      % seconds
dt = 0.5;

I_max_charge    = 80;
I_max_discharge = -300;

capacity_Ah = 100;
capacity_C  = capacity_Ah * 3600;

force_interval_sec = 150;
force_duration_sec = [30 80];
force_I_range      = [-220 -120];

load_system(modelName);

SOC_prev = 0.5;

time_vec = (0:dt:duration)';
N = length(time_vec);

current_profile = zeros(N,1);
was_discharging = true;

%% -------- BASE DRIVE CYCLE --------
i = 1;
while i <= N

    hold_samples = min(randi([16 60]), N-i+1);  % ✅ integer samples
    r = rand;

    if r < 0.7
        I = -randi([100 260]);
        was_discharging = true;

    elseif r < 0.85 && was_discharging
        I = randi([10 30]);
        was_discharging = false;

    else
        I = randi([-5 5]);
    end

    current_profile(i:i+hold_samples-1) = I;
    i = i + hold_samples;
end

%% -------- CLAMP (NO SMOOTHING / NO NOISE) --------
current_profile = min(max(current_profile, ...
                    I_max_discharge), I_max_charge);

%% -------- FORCED DISCHARGE (HARD) --------
force_N = round(force_interval_sec/dt);
for k = 1:force_N:N
    dur = min(randi(force_duration_sec)/dt, N-k+1);
    current_profile(k:k+dur-1) = randi(force_I_range);
end

%% -------- ENFORCE NET DISCHARGE --------
W = round(120/dt);                    % 2-minute window
bad = movmean(current_profile,W) > -40;
current_profile(bad) = current_profile(bad) - 80;

%% -------- EXPORT TO SIMULINK --------
assignin('base','Drive_Cycle', ...
    timeseries(current_profile,time_vec));

assignin('base','Input_Temp', randi([15 45]));
