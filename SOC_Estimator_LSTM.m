classdef SOC_Estimator_LSTM < matlab.System & matlab.system.mixin.SampleTime
    % LSTM-based ΔSOC estimator for Simulink

    properties
        WindowLength = 100;   % samples
        SampleTime   = 0.1;   % MUST match training dt
    end

    properties (Access = private)
        buffer
        net
    end

    % =====================================================
    % OUTPUT SPECIFICATION
    % =====================================================
    methods (Access = protected)
        function num = getNumOutputsImpl(~), num = 1; end
        function out = getOutputSizeImpl(~), out = [1 1]; end
        function out = getOutputDataTypeImpl(~), out = "double"; end
        function out = isOutputComplexImpl(~), out = false; end
        function out = isOutputFixedSizeImpl(~), out = true; end
    end

    % =====================================================
    % SAMPLE TIME (CORRECT MODERN WAY)
    % =====================================================
    methods (Access = protected)
        function sts = getSampleTimeImpl(obj)
            sts = matlab.system.SampleTimeSpecification( ...
                'Type', 'Discrete', ...
                'SampleTime', obj.SampleTime);
        end
    end

    % =====================================================
    % MAIN LOGIC
    % =====================================================
    methods (Access = protected)

        function setupImpl(obj)
            obj.buffer = zeros(3, obj.WindowLength);
            data = load('lstm_dsoc_model.mat','net');
            obj.net = data.net;
        end

        function dSOC = stepImpl(obj, I, V, T)
            % Shift buffer
            obj.buffer(:,1:end-1) = obj.buffer(:,2:end);
            obj.buffer(:,end) = [I; V; T];

            % Predict ΔSOC
            y = predict(obj.net, obj.buffer);
            dSOC = double(y(end));
        end
    end
end
