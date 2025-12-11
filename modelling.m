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


%% -------------------------
% 7) !!!PR!!! - Export Model for Python (JSON format)
% -------------------------
% MATLAB creates a "process" struct that scales inputs to [-1, 1].
% We must export these min/max values to replicate the logic in Python.

% Get Input Scaling (mapminmax)
x_process = net.inputs{1}.processSettings{1};
x_min = x_process.xmin;
x_max = x_process.xmax;

% Get Output Scaling (mapminmax)
y_process = net.outputs{2}.processSettings{1};
y_min = y_process.ymin;
y_max = y_process.ymax;

% Get Weights and Biases
IW = net.IW{1}; % Input Weights
LW = net.LW{2,1}; % Layer Weights
b1 = net.b{1}; % Bias 1
b2 = net.b{2}; % Bias 2

% Create a struct to save
jsonStruct = struct();
jsonStruct.x_min = x_min;
jsonStruct.x_max = x_max;
jsonStruct.y_min = y_min;
jsonStruct.y_max = y_max;
jsonStruct.IW = IW;
jsonStruct.LW = LW;
jsonStruct.b1 = b1;
jsonStruct.b2 = b2;

% Write to JSON file
fid = fopen('model_params.json', 'w');
encodedJSON = jsonencode(jsonStruct);
fprintf(fid, '%s', encodedJSON);
fclose(fid);

fprintf("✔ Weights exported to: model_params.json\n");
