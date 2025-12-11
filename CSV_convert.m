%% ---------------------------------------------------------
% Convert DriveData_XXX.mat → DriveData_XXX.csv (with SOC %)
% ---------------------------------------------------------

clear; clc;

inputFolder  = 'TrainingData';               
outputFolder = 'CSV_Output';

if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

files = dir(fullfile(inputFolder, 'DriveData_*.mat'));

fprintf("\nConverting %d MAT files to CSV...\n\n", length(files));

for k = 1:length(files)

    matFile = fullfile(inputFolder, files(k).name);
    load(matFile, 'Data');   % Loads struct Data

    % Extract fields
    time        = Data.time(:);
    current_A   = Data.current(:);
    voltage_V   = Data.voltage(:);

    % Convert temperature to °C
    if mean(Data.temp) > 200
        temperature_C = Data.temp(:) - 273.15;
    else
        temperature_C = Data.temp(:);
    end

    % Convert SOC → percent
    soc_percent = Data.soc(:) * 100;

    % Build table
    T = table(time, current_A, temperature_C, voltage_V, soc_percent);

    % Output CSV name
    [~, name, ~] = fileparts(files(k).name);
    csvFile = fullfile(outputFolder, name + ".csv");

    % Write CSV
    writetable(T, csvFile);

    fprintf("Saved → %s\n", csvFile);
end

fprintf("\n✔ CSV generation complete.\n");
