restoredefaultpath
clear; 
close all; 
opts = get_opts();
opts.sequence=5;
opts.reader = [];

% fps at 1/30/60
fps = 60;
for iCam = 1:8
    gen_gt_function(opts,iCam,fps);
end