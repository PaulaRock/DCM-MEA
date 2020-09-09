%------- Well types
clear all
close all

% for replication purpses this is the DCM pair for DCM_CMM{15} when loading well A5
% I (Paula) loaded well B6

%datafiletotest = ['/Users/k1775598/OneDrive - King''','s College London/IPSC_DCMs/GABA_plate/New_pair_GABA_d66_A5_elec3elec9'];
datafiletotest = ['/Users/paula/GoogleDrive/Career/Research/DPhil_Oxford/2_Analysis/DCM/GABA_Plate/Sample_Data/New_pair_GABA_d66_B6_elec4elec1.dat'];


% for replication - this is the version of spm used as per text of model
% description
spm_path = ['/Users/paula/GoogleDrive/Career/Research/DPhil_Oxford/2_Analysis/DCM/spm12MEA_Stem'];
addpath(genpath(spm_path))

load_wells_cells = {'A1','A2','A3','A4','A5','A6','A7','A8',...
    'B1','B2','B3','B4','B5','B6','B7','B8',...
    'C1','C2','C3','C4' ,'C5','C6','C7','C8',...
    'D1','D2','D3','D4','D5','D6','D7','D8',...
    'E1','E2','E3','E4','E5','E6','E7','E8',...
    'F1','F2','F3','F4','F5','F6','F7','F8'};

% A to C  ------ Control
% D to F  ------ GABA 50uml

Drug_in_chan_gaba    = [ 0 0 0 0 0 0 0 0 ...
    0 0 0 0 0 0 0 0 ...
    0 0 0 0 0 0 0 0 ...
    1 1 1 1 1 1 1 1 ...
    1 1 1 1 1 1 1 1 ...
    1 1 1 1 1 1 1 1];

DCM.xY.Dfile     = datafiletotest;

DCM.xY.Hz     =  [1 60];
DCM.xY.modality = 'LFP';
DCM.xY.Ic = [1 2]; % 2 channels in these data

DCM.A{1} = [1 0; 0 1];
DCM.A{2} = [1 0; 0 1];
DCM.A{3} = [1 0; 0 1];
DCM.B    = [];
DCM.C    = [1 1]';

DCM.options.model       =  'CMM';
DCM.options.analysis    =  'CSD';
DCM.options.spatial     =  'LFP';
DCM.options.Fdcm        =   DCM.xY.Hz;
DCM.options.Tdcm        =   [1 59000]; %% 1 minute of data
DCM.options.trials      =   1;
DCM.options.D           =   1;
DCM.M.hE                =   4;

DCM.Sname = {'ElecA','ElecB'};


DCM_CMM  =  spm_dcm_csd(DCM);


save('Sample_DCM_Reproduce_A5_3_9','DCM_CMM')


