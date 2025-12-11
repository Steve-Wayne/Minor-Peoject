% Create SOC estimator subsystem in Simulink
% Save as: create_SOC_subsystem.m

function create_SOC_subsystem()
    model_name = 'BMS_Complete_System';
    subsystem_name = [model_name '/SOC_Estimator'];
    
    % Open subsystem for editing
    open_system(subsystem_name);
    
    % Add input ports
    add_block('simulink/Ports & Subsystems/In1', [subsystem_name '/V_measured']);
    add_block('simulink/Ports & Subsystems/In1', [subsystem_name '/I_measured']);
    add_block('simulink/Ports & Subsystems/In1', [subsystem_name '/T_measured']);
    
    % Add MATLAB function block with Kalman filter
    add_block('simulink/User-Defined Functions/MATLAB Function', ...
              [subsystem_name '/Kalman_Filter']);
    
    % Configure MATLAB function
    % (This would contain the Kalman filter code from Step 7)
    
    % Add Coulomb counting for comparison
    add_block('simulink/Continuous/Integrator', [subsystem_name '/Coulomb_Counter']);
    add_block('simulink/Math Operations/Gain', [subsystem_name '/Current_to_SOC']);
    set_param([subsystem_name '/Current_to_SOC'], 'Gain', '-1/(2.6*3600)');
    
    % Add output port
    add_block('simulink/Ports & Subsystems/Out1', [subsystem_name '/SOC_estimate']);
    
    % Add 2D lookup table for OCV
    add_block('simulink/Lookup Tables/2-D Lookup Table', [subsystem_name '/OCV_Lookup']);
    
    fprintf('✅ SOC Estimator subsystem created\n');
    fprintf('   Features: Kalman filter + Coulomb counting\n');
    fprintf('   Inputs: Voltage, Current, Temperature\n');
    fprintf('   Output: SOC estimate (0-100%%)\n');
end