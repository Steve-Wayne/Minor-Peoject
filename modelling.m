%% ========================================================================
%  SOC Estimation Neural Network (fitnet)
%  Loads all DriveData CSV files, trains a NN, evaluates accuracy.
% ========================================================================

clear; clc; close all;

%% -------------------------
% 1) Load all CSV files
% -------------------------
inputFolder = 'CSV_Output';   % Folder containing CSVs
files = dir(fullfile(inputFolder, 'DriveData_*.csv'));

allData = [];

for k = 1:length(files)
    T = readtable(fullfile(inputFolder, files(k).name));
    allData = [allData; T];
end

fprintf("Loaded %d files. Total samples = %d\n", length(files), height(allData));

%% -------------------------
% 2) Prepare Inputs & Target
% -------------------------
current_A   = allData.current_A;
temperature = allData.temperature_C;
voltage_V   = allData.voltage_V;

soc_percent = allData.soc_percent;

% Input matrix (each column = feature)
X = [current_A.'; temperature.'; voltage_V.'];

% Output (target)
Y = soc_percent.';     % row vector

%% -------------------------
% 3) Create Neural Network
% -------------------------
hiddenNeurons = 20;   % You can try 10, 20, 30, 40

net = fitnet(hiddenNeurons, 'trainlm');   % Levenberg-Marquardt (best)

% Split data
net.divideParam.trainRatio = 0.7;   % 70% training
net.divideParam.valRatio   = 0.15;  % 15% validation
net.divideParam.testRatio  = 0.15;  % 15% testing

% Training settings
net.trainParam.epochs = 500;
net.trainParam.goal   = 1e-5;

%% -------------------------
% 4) Train Network
% -------------------------
[net, tr] = train(net, X, Y);

fprintf("\n✔ Neural Network training complete!\n\n");

%% -------------------------
% 5) Evaluate Performance
% -------------------------
Y_pred = net(X);

rmse = sqrt(mean((Y_pred - Y).^2));
fprintf("RMSE = %.3f %% SOC\n", rmse);

%% Plot results
figure;
plot(Y, 'b'); hold on;
plot(Y_pred, 'r');
legend('Actual SOC', 'Predicted SOC');
title('SOC Prediction vs Actual');
xlabel('Sample'); ylabel('SOC (%)');

%% -------------------------
% 6) Save Model
% -------------------------
save('SOC_NeuralNet_Model.mat', 'net');

fprintf("✔ Model saved: SOC_NeuralNet_Model.mat\n");
