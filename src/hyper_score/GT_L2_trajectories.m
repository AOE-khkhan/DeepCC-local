clc
clear

opts=get_opts();

opts.trajectories.window_width = 1500;
L2_speed = 'mid';
% L2_speed = 'head-tail';

% opts.visualize = true;
opts.sequence = 7;
opts.experiment_name = '1fps_og_cc';

newGTs = cellmat(1,8,0,0,0);
spatialGroupID_max = zeros(1,8);
% Computes single-camera trajectories from tracklets
for iCam = 1:8
    sequence_window   = opts.sequence_intervals{opts.sequence};
    start_frame       = global2local(opts.start_frames(iCam), sequence_window(1));
    end_frame         = global2local(opts.start_frames(iCam), sequence_window(end));
    
    filename =sprintf('%s/ground_truth/tracklets%d_%s.mat',opts.dataset_path,iCam,opts.sequence_names{opts.sequence});
    if ~exist(filename, 'file')
    % Load GTs for current camera
    trainData = load(fullfile(opts.dataset_path, 'ground_truth','trainval.mat'));
    trainData = trainData.trainData;
    
    in_time_range_ids = trainData(:,3)>=start_frame & trainData(:,3)<=end_frame & trainData(:,1)==iCam;
    all_gts   = trainData(in_time_range_ids,2:7);
    % Initialize
    load(fullfile(opts.experiment_root, opts.experiment_name, 'L1-tracklets', sprintf('tracklets%d_%s.mat',iCam,opts.sequence_names{opts.sequence})));
    fields={'center','centerWorld','features','realdata','mask','interval','segmentStart','segmentInterval','segmentEnd','ids'};
    tracklets = rmfield(tracklets,fields);
    for i = 1:length(tracklets)
        window_frames = tracklets(i).data(:,1);
        gts_in_window = all_gts(ismember(all_gts(:,2),window_frames),:);
        gts_in_window(:,[1 2]) = gts_in_window(:,[2 1]);
        pids = unique(gts_in_window(:,2));
		fprintf('iCam %d, track #%d/%d, id_pool size: %d. \n',iCam,i,length(tracklets),length(pids))
        IoUs = zeros(length(window_frames),length(pids));
        bbox_det_s = tracklets(i).data(:,3:6);
        for j = 1:length(pids)
            pid = pids(j);
            index = find((gts_in_window(:,2)==pid));
            bbox_gt_s = gts_in_window(index,3:6);
            gt_frames = gts_in_window(index,1);
            det_overlap_index = ismember(window_frames,gt_frames);
            IoUs(det_overlap_index,j) = diag(bboxOverlapRatio(bbox_det_s(det_overlap_index,:),bbox_gt_s));
        end
        IoUs=mean(IoUs,1);
        [IoU,j]=max(IoUs);
        pid = pids(j);
        if IoU<0.2
            pid=-1;
        end
        if isempty(pids)
            pid=-1;
        end
        tracklets(i).id=pid;
        if isempty(tracklets(i).id)
            i
        end
        if opts.visualize
            index = find((gts_in_window(:,2)==pid));
            bbox_gt_s = gts_in_window(index,3:6);
            gt_frames = gts_in_window(index,1);
            det_overlap_index = find(ismember(window_frames,gt_frames),1);
            show_bbox(opts,iCam,window_frames(det_overlap_index),bbox_det_s(det_overlap_index,:),bbox_gt_s(1,:))
        end
    end
    
    % Save trajectories
    save(filename, 'tracklets');
    else
        load(filename)
        pids = [tracklets.id]';
        feat = reshape([tracklets.feature]',256,[])';
        
        if strcmp(L2_speed,'mid')
        [~, ~, startpoint, endpoint, intervals, ~, velocity] = getTrackletFeatures(tracklets);
        centerFrame     = local2global(opts.start_frames(iCam),round(mean(intervals,2)));
        centers         = 0.5 * (endpoint + startpoint);
        newGTs{iCam} = [ones(size(pids))*iCam,pids,centerFrame,zeros(size(pids,1),1),centers,velocity,zeros(size(pids,1),1),feat];
        else
        [~, ~, startpoint, endpoint, intervals, ~,  head_velocity,tail_velocity] = getHeadTailSpeed(tracklets);
        startFrame = intervals(:,1);
        endFrame = intervals(:,2);
        centerFrame     = round(mean(intervals,2));
        newGTs{iCam} = [ones(size(pids))*iCam,pids,centerFrame,zeros(size(pids,1),1),startFrame,endFrame,startpoint, endpoint,head_velocity,tail_velocity,zeros(size(pids,1),1),feat];
        end
        
        for i=1:ceil((end_frame-start_frame+1)/opts.trajectories.window_width)
        % Display loop state
        clc; fprintf('Cam: %d - Window %d...%d\n', iCam, start_frame+(i-1)*opts.trajectories.window_width, start_frame+i*opts.trajectories.window_width);
        indexs = logical((newGTs{iCam}(:,3)>=(start_frame+(i-1)*opts.trajectories.window_width)) .*(newGTs{iCam}(:,3)<(start_frame+i*opts.trajectories.window_width)));
        spatialGroupID = 1+spatialGroupID_max(iCam);
        spatialGroupID_max(iCam) = spatialGroupID;
        newGTs{iCam}(indexs,4)=spatialGroupID;
        end
    end
end

res = [];
for iCam = 1:8
    newGT = newGTs{iCam};
    newGT(:,4) = newGT(:,4)+sum(spatialGroupID_max(1:iCam-1));
    res = [res;newGT];
%     hdf5write(fullfile(opts.dataset_path, 'ground_truth',sprintf('hyperGT_%s_%d.h5',opts.sequence_names{opts.sequence},iCam)), '/hyperGT',newGTs{iCam}');
end


newGT(:,4) = 0;
hdf5write(fullfile(opts.dataset_path, 'ground_truth',sprintf('hyperGT_L2_%s_%d_%s.h5',opts.sequence_names{opts.sequence},opts.trajectories.window_width,L2_speed)), '/hyperGT',res');