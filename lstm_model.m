%% ============================================================
%   EV BATTERY SOC ESTIMATION USING LSTM (CORRECTED VERSION)
% ============================================================

clear; clc; close all;

%% ============================
% 1. LOAD BATTERY CYCLES
% ============================

folder = "CSV_Output"; 
files  = dir(fullfile(folder,"DriveData_*.csv"));

allX = {}; 
allY = {};

for k = 1:length(files)

    T = readtable(fullfile(folder, files(k).name));

    % ---- Correct column names ----
    I  = double(T.current_A);
    V  = double(T.voltage_V);
    Tt = double(T.temperature_C);
    SOC = double(T.soc_percent);

    % Raw inputs: [time × features]
    Xk_raw = [I, V, Tt];      % [N × 3]
    Yk_raw = SOC;             % [N × 1]

    % ---- FIX ORIENTATION FOR LSTM ----
    Xk = Xk_raw.';   % -> [3 × N]
    Yk = Yk_raw.';   % -> [1 × N]

    allX{k} = Xk;
    allY{k} = Yk;
end

fprintf("Loaded %d drive cycles.\n", length(files));

%% ============================
% 2. TRAIN / VAL / TEST SPLIT
% ============================

numCycles = length(allX);
numTrain  = round(0.7 * numCycles);
numVal    = round(0.15 * numCycles);
numTest   = numCycles - numTrain - numVal;

idx     = randperm(numCycles);
XTrain  = allX(idx(1:numTrain));
YTrain  = allY(idx(1:numTrain));
XVal    = allX(idx(numTrain+1:numTrain+numVal));
YVal    = allY(idx(numTrain+1:numTrain+numVal));
XTest   = allX(idx(numTrain+numVal+1:end));
YTest   = allY(idx(numTrain+numVal+1:end));

%% ============================
% 3. NORMALIZATION
% ============================

allTrainMat = cell2mat(XTrain);

mu    = mean(allTrainMat, 2);     
sigma = std(allTrainMat, 0, 2);
sigma(sigma == 0) = 1;

for i = 1:length(XTrain); XTrain{i} = (XTrain{i} - mu) ./ sigma; end
for i = 1:length(XVal);   XVal{i}   = (XVal{i}   - mu) ./ sigma; end
for i = 1:length(XTest);  XTest{i}  = (XTest{i}  - mu) ./ sigma; end

allYTrain = cell2mat(YTrain);  
y_mu  = mean(allYTrain(:));
y_std = std(allYTrain(:));
if y_std == 0, y_std = 1; end

for i = 1:length(YTrain); YTrain{i} = (YTrain{i} - y_mu) / y_std; end
for i = 1:length(YVal);   YVal{i}   = (YVal{i}   - y_mu) / y_std; end
for i = 1:length(YTest);  YTest{i}  = (YTest{i}  - y_mu) / y_std; end

%% ============================
% 4. LSTM MODEL
% ============================

layers = [
    sequenceInputLayer(3)

    lstmLayer(256,'OutputMode','sequence')
    dropoutLayer(0.2)

    lstmLayer(128,'OutputMode','sequence')
    dropoutLayer(0.2)

    lstmLayer(64,'OutputMode','sequence')

    fullyConnectedLayer(1)
    regressionLayer
];

%% ============================
% 5. TRAINING OPTIONS
% ============================

options = trainingOptions('adam', ...
    MaxEpochs = 100, ...
    MiniBatchSize = 1, ...
    InitialLearnRate = 0.001, ...
    ValidationData = {XVal, YVal}, ...
    ValidationFrequency = 10, ...
    GradientThreshold = 1, ...
    Plots = 'training-progress', ...
    Verbose = false);

%% ============================
% 6. TRAIN NETWORK
% ============================

net = trainNetwork(XTrain, YTrain, layers, options);

%% ============================
% 7. TEST & METRICS
% ============================

rmse_all = zeros(length(XTest),1);
mae_all  = zeros(length(XTest),1);
mape_all = zeros(length(XTest),1);
R2_all   = zeros(length(XTest),1);

figure; hold on;

for i = 1:length(XTest)

    % Predict normalized output
    Ypred_norm = predict(net, XTest{i}, 'MiniBatchSize', 1);

    % De-normalize
    ytrue = YTest{i} * y_std + y_mu;
    yhat  = Ypred_norm * y_std + y_mu;

    % Metrics
    err = ytrue - yhat;

    rmse_all(i) = sqrt(mean(err.^2));
    mae_all(i)  = mean(abs(err));
    mape_all(i) = mean(abs(err ./ max(ytrue, 1))) * 100;
    R2_all(i)   = 1 - sum(err.^2) / sum((ytrue - mean(ytrue)).^2);

    % Plot cycle
    plot(ytrue, 'b'); 
    plot(yhat,  'r--');
end

title("Actual vs Predicted SOC (LSTM Test)");
xlabel("Time step"); ylabel("SOC (%)");
legend("Actual","Predicted"); grid on;

%% ============================
% 8. PRINT METRICS
% ============================

fprintf("\n===== TEST METRICS PER CYCLE =====\n");
for i = 1:length(XTest)
    fprintf("Cycle %d: RMSE=%.2f, MAE=%.2f, MAPE=%.2f%%, R2=%.3f\n", ...
        i, rmse_all(i), mae_all(i), mape_all(i), R2_all(i));
end

fprintf("\n===== OVERALL METRICS =====\n");
fprintf("RMSE  = %.2f\n", mean(rmse_all));
fprintf("MAE   = %.2f\n", mean(mae_all));
fprintf("MAPE  = %.2f%%\n", mean(mape_all));
fprintf("R2    = %.3f\n", mean(R2_all));

%% ============================
% 9. SAVE MODEL
% ============================

save('lstm_soc_model.mat', ...
    'net','mu','sigma','y_mu','y_std', ...
    'rmse_all','mae_all','mape_all','R2_all');

fprintf("\n✔ Model and metrics saved to lstm_soc_model.mat\n");
