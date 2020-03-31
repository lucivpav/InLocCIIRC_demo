function [ params ] = setup_project_ht_WUSTL
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

params = struct();

%WUSTL dataset
env = environment();
if strcmp(env, 'ciirc')
    params.data.dir = '/home/lucivpav/InLocCIIRC_dataset';
    params.data.netvlad.dir = '/home/lucivpav/NetVLAD';
elseif strcmp(env, 'cmp')
    params.data.dir = '/datagrid/personal/lucivpav/InLocCIIRC_dataset';
    params.data.netvlad.dir = '/datagrid/personal/lucivpav/NetVLAD';
elseif strcmp(env, 'laptop')
    params.data.dir = '/Volumes/GoogleDrive/Můj disk/ARTwin/InLocCIIRC_dataset';
    params.data.netvlad.dir = '/Volumes/GoogleDrive/Můj disk/ARTwin/InLocCIIRC_dataset/NetVLAD';
end
params.data.netvlad.pretrained = fullfile(params.data.netvlad.dir, 'vd16_pitts30k_conv5_3_vlad_preL2_intra_white.mat');
%database
params.data.db.space_names = {'B-670', 'B-315'};
%%scan
params.data.db.scan.dir = 'scans';
params.data.db.scan.matformat = '.ptx.mat';
%%cutouts
params.data.db.cutout.dir = 'cutouts';
params.data.db.cutout.imgformat = '.jpg';
params.data.db.cutout.matformat = '.mat';
%%alignments
params.data.db.trans.dir = 'alignments';
%query
params.data.q.dir = 'query';
params.data.q.imgformat = '.jpg';
params.data.q.fl = 3172; % [px]
% models
params.data.models.dir = fullfile(params.data.dir, 'models');


%input
params.input.dir = fullfile(params.data.dir, 'inputs');
params.input.dblist_matname = fullfile(params.input.dir, 'cutout_imgnames_all.mat');%string cell containing cutout image names
params.input.qlist_matname = fullfile(params.input.dir, 'query_imgnames_all.mat');%string cell containing query image names
params.input.score_matname = fullfile(params.input.dir, 'scores.mat');%retrieval score matrix
params.input.feature.dir = fullfile(params.input.dir, 'features');
params.input.feature.db_matformat = '.features.dense.mat';
params.input.feature.q_matformat = '.features.dense.mat';
params.input.feature.db_sps_matformat = '.features.sparse.mat';
params.input.feature.q_sps_matformat = '.features.sparse.mat';
params.input.projectMesh_py_path = fullfile(cd, 'functions/InLocCIIRC_utils/projectMesh/projectMesh.py');


%output
params.output.dir = fullfile(params.data.dir, 'outputs');
params.output.gv_dense.dir = fullfile(params.output.dir, 'gv_dense');%dense matching results (directory)
params.output.gv_dense.matformat = '.gv_dense.mat';%dense matching results (file extention)
params.output.gv_sparse.dir = fullfile(params.output.dir, 'gv_sparse');%sparse matching results (directory)
params.output.gv_sparse.matformat = '.gv_sparse.mat';%sparse matching results (file extention)

params.output.pnp_dense_inlier.dir = fullfile(params.output.dir, 'PnP_dense_inlier');%PnP results (directory)
params.output.pnp_dense.matformat = '.pnp_dense_inlier.mat';%PnP results (file extention)
params.output.pnp_sparse_inlier.dir = fullfile(params.output.dir, 'PnP_sparse_inlier');%PnP results (directory)
params.output.pnp_sparse_inlier.matformat = '.pnp_sparse_inlier.mat';%PnP results (file extention)

params.output.pnp_sparse_origin.dir = fullfile(params.output.dir, 'PnP_sparse_origin');%PnP results (directory)
params.output.pnp_sparse_origin.matformat = '.pnp_sparse_origin.mat';%PnP results (file extention)

params.output.synth.dir = fullfile(params.output.dir, 'synthesized');%View synthesis results (directory)
params.output.synth.matformat = '.synth.mat';%View synthesis results (file extention)

% evaluation
params.evaluation.dir = fullfile(params.data.dir, 'evaluation');
params.evaluation.query_vs_synth.dir = fullfile(params.evaluation.dir, 'queryVsSynth');
params.evaluation.errors.path = fullfile(params.evaluation.dir, 'errors.csv');
params.evaluation.summary.path = fullfile(params.evaluation.dir, 'summary.txt');
params.evaluation.retrieved.poses.path = fullfile(params.evaluation.dir, 'retrievedPoses.csv');

end