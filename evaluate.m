% user configuration
visualEvaluation = true;
useHoloLensPosesAsPoseEstimates = false;

%% initialization
assert(~(useHoloLensPosesAsPoseEstimates && visualEvaluation));
load(params.input.qlist.path);
densePV_matname = fullfile(params.output.dir, 'densePV_top10_shortlist.mat');
load(densePV_matname, 'ImgList');

mkdirIfNonExistent(params.evaluation.dir);
mkdirIfNonExistent(params.evaluation.retrieved.poses.dir);
mkdirIfNonExistent(params.evaluation.query_vs_synth.dir);
mkdirIfNonExistent(params.evaluation.query_segments_vs_synth_segments.dir);

% TODO: this is an evaluation, we should show the high quality projections, not those used in densePV
%% visual evaluation - query_vs_synth
if visualEvaluation
    for i=1:size(query_imgnames_all,2)
        queryName = query_imgnames_all{i};
        queryImage = imread(fullfile(params.dataset.query.dir, queryName));

        ImgListRecord = ImgList(find(strcmp({ImgList.queryname}, queryName)));
        dbnamesId = ImgListRecord.dbnamesId(1);
        synthPath = fullfile(params.output.synth.dir, queryName, sprintf('%d%s', dbnamesId, params.output.synth.matformat));
        load(synthPath, 'RGBpersps');
        numRows = size(queryImage,1);
        numCols = size(queryImage,2);

        synthImage = RGBpersps{end};
        if isempty(synthImage)
            synthImage = zeros(numRows, numCols, 3, 'uint8');
        else
            synthImage = imresize(synthImage, [numRows numCols]);
        end

        queryId = strsplit(queryName, '.');
        queryId = queryId{1};
        imwrite(queryImage, fullfile(params.evaluation.query_vs_synth.dir, sprintf('%s-query.jpg', queryId)));
        imwrite(synthImage, fullfile(params.evaluation.query_vs_synth.dir, sprintf('%s-synth.jpg', queryId)));

        %imshowpair(queryImage, synthImage, 'montage');
        %saveas(gcf, fullfile(params.evaluation.query_vs_synth.dir, queryName));
    end
end

% TODO: this is an evaluation, we should show the high quality projections, not those used in densePV
%% visual evaluation - query_segments_vs_synth_segments
if visualEvaluation
    areQueriesFromHoloLensSequence = isfield(params, 'sequence') && isfield(params.sequence, 'length');
    if areQueriesFromHoloLensSequence
        for i=1:size(query_imgnames_all,2)
            parentQueryName = query_imgnames_all{i};
            parentQueryId = queryNameToQueryId(parentQueryName);

            ImgListRecord = ImgList(find(strcmp({ImgList.queryname}, parentQueryName)));
            dbnamesId = ImgListRecord.dbnamesId(1);
            synthPath = fullfile(params.output.synth.dir, parentQueryName, sprintf('%d%s', dbnamesId, params.output.synth.matformat));
            load(synthPath, 'RGBpersps');
            thisOutputDir = fullfile(params.evaluation.query_segments_vs_synth_segments.dir, parentQueryName);
            mkdirIfNonExistent(thisOutputDir);
            k = length(RGBpersps);
            for j=1:k
                queryId = parentQueryId-k+j;
                queryName = sprintf('%d.jpg', queryId);
                queryImage = imread(fullfile(params.dataset.query.dir, queryName));
                numRows = size(queryImage,1);
                numCols = size(queryImage,2);
                synthImage = RGBpersps{j};
                if isempty(synthImage)
                    synthImage = zeros(numRows, numCols, 3, 'uint8');
                else
                    synthImage = imresize(synthImage, [numRows numCols]);
                end

                imwrite(queryImage, fullfile(thisOutputDir, sprintf('%d-query.jpg', queryId)));
                imwrite(synthImage, fullfile(thisOutputDir, sprintf('%d-synth.jpg', queryId)));
            end
        end
    end
end

%% quantitative results

% do not compute a numerical error for those queries I dont have reference pose! (they are on params.blacklistedQueryInd)
% this would screw up the resulting statistics
nQueries = size(query_imgnames_all,2);
whitelistedQueries = ones(1,nQueries);
blacklistedQueries = false(1,nQueries);
nBlacklistedQueries = 0;
if isfield(params, 'blacklistedQueryInd')
    blacklistedQueryNames = arrayfun(@(idx) sprintf('%d.jpg', idx), params.blacklistedQueryInd, 'UniformOutput', false);
    blacklistedQueries = false(1,nQueries);
    nSuggestedBlacklistedQueries = length(params.blacklistedQueryInd);
    for i=1:nSuggestedBlacklistedQueries
        queryName = blacklistedQueryNames{i};
        idx = find(strcmp(queryName,query_imgnames_all));
        if ~isempty(idx)
            blacklistedQueries(idx) = true;
        end
    end
    nBlacklistedQueries = sum(blacklistedQueries);
    fprintf('Skipping %0.0f%% queries without reference poses. %d queries remain.\n', ...
                nBlacklistedQueries*100/nQueries, nQueries-nBlacklistedQueries);
    whitelistedQueries = logical(ones(1,nQueries) - blacklistedQueries); % w.r.t. reference frame
end

errors = struct();
retrievedQueries = struct();
inLocCIIRCLostCount = 0;
for i=1:nQueries
    queryName = query_imgnames_all{i};
    queryId = strsplit(queryName, '.');
    queryId = queryId{1};
    queryId = uint32(str2num(queryId));

    descriptionsPath = fullfile(params.dataset.query.dir, 'descriptions.csv');
    descriptionsTable = readtable(descriptionsPath);
    descriptionsRow = descriptionsTable(descriptionsTable.id==queryId, :);
    referenceSpace = descriptionsRow.space{1,1};
    queryPoseFilename = sprintf('%d.txt', queryId);

    if useHoloLensPosesAsPoseEstimates
        % NOTE: because _dataset's holoLensPoses.m created these poses, they already account for the possible delays
        spaceName = referenceSpace;
        holoLensPosesDir = fullfile(params.dataset.query.dir, 'HoloLensPoses');
        holoLensPosePath = fullfile(holoLensPosesDir, queryPoseFilename);
        if exist(holoLensPosePath, 'file') ~= 2
            % due to the delay, some queries don't have a pose from HoloLens
            T = nan(3,1);
            R = nan(3,3);
            P = nan(4,4);
        else
            P = load_CIIRC_transformation(holoLensPosePath);
            T = -inv(P(1:3,1:3))*P(1:3,4);
            R = P(1:3,1:3);
        end
    else
        useLegacyAlignments = exist(fullfile(params.input.dir, 'use_legacy_alignments.txt'), 'file');
        [P,T,R,spaceName] = loadPoseFromInLocCIIRC_demo(queryId, ImgList, params, useLegacyAlignments);
    end

    if ~strcmp(spaceName, referenceSpace) || ~whitelistedQueries(i)
        T = nan(3,1);
        R = nan(3,3);
        P = nan(4,4);
    end

    if any(isnan(P(:))) && whitelistedQueries(i)
        inLocCIIRCLostCount = inLocCIIRCLostCount + 1;
    end

    posePath = fullfile(params.dataset.query.dir, 'poses', queryPoseFilename);
    referenceP = load_CIIRC_transformation(posePath);
    referenceT = -inv(referenceP(1:3,1:3))*referenceP(1:3,4);
    referenceR = referenceP(1:3,1:3);
    
    errors(i).queryId = queryId;
    errors(i).translation = norm(T - referenceT);
    errors(i).orientation = rotationDistance(referenceR, R);
    errors(i).inMap = descriptionsRow.inMap;

    retrievedPosePath = fullfile(params.evaluation.retrieved.poses.dir, queryPoseFilename);
    retrievedPoseFile = fopen(retrievedPosePath, 'w');
    P_str = P_to_str(P);
    fprintf(retrievedPoseFile, '%s', P_str);
    fclose(retrievedPoseFile);
    
    retrievedQueries(i).id = queryId;
    retrievedQueries(i).space = spaceName;
end

% errors
errorsBak = errors;
errorsTable = struct2table(errors);
errors = table2struct(sortrows(errorsTable, 'queryId'));
errorsFile = fopen(params.evaluation.errors.path, 'w');
fprintf(errorsFile, 'id,inMap,translation,orientation\n');
for i=1:nQueries
    inMapStr = 'No';
    if errors(i).inMap
        inMapStr = 'Yes';
    end
    fprintf(errorsFile, '%d,%s,%0.4f,%0.4f\n', errors(i).queryId, inMapStr, errors(i).translation, errors(i).orientation);
end
fclose(errorsFile);
errors = errorsBak; % we cannot use the sorted. it would break compatibility with blacklistedQueries array!

meaningfulTranslationErrors = [errors(~isnan([errors.translation])).translation];
meaningfulOrientationErrors = [errors(~isnan([errors.orientation])).orientation];

% statistics of the errors
meanTranslation = mean(meaningfulTranslationErrors);
meanOrientation = mean(meaningfulOrientationErrors);
medianTranslation = median(meaningfulTranslationErrors);
medianOrientation = median(meaningfulOrientationErrors);
stdTranslation = std(meaningfulTranslationErrors);
stdOrientation = std(meaningfulOrientationErrors);

% retrievedQueries
retrievedQueriesTable = struct2table(retrievedQueries);
retrievedQueries = table2struct(sortrows(retrievedQueriesTable, 'id'));
retrievedQueriesFile = fopen(params.evaluation.retrieved.queries.path, 'w');
fprintf(retrievedQueriesFile, 'id space\n');
for i=1:nQueries
    fprintf(retrievedQueriesFile, '%d %s\n', retrievedQueries(i).id, ...
        retrievedQueries(i).space);
end
fclose(retrievedQueriesFile);

%% summary
summaryFile = fopen(params.evaluation.summary.path, 'w');
thresholds = [[0.25 10], [0.5 10], [1 10]];
scores = zeros(1, size(thresholds,2)/2);
inMapScores = scores;
offMapScores = scores;
fprintf(summaryFile, 'Conditions: ');
for i=1:2:size(thresholds,2)
    if i > 1
        fprintf(summaryFile, ' / ');
    end
    fprintf(summaryFile, '(%g [m], %g [deg])', thresholds(i), thresholds(i+1));
    
    count = 0;
    inMapCount = 0;
    offMapCount = 0;
    inMapSize = 0;
    offMapSize = 0;
    for j=1:length(errors)
        if blacklistedQueries(j)
            continue;
        end
        if errors(j).translation < thresholds(i) && errors(j).orientation < thresholds(i+1)
            count = count + 1;
            if errors(j).inMap
                inMapCount = inMapCount + 1;
            else
                offMapCount = offMapCount + 1;
            end
        end
        if errors(j).inMap
            inMapSize = inMapSize + 1;
        else
            offMapSize = offMapSize + 1;
        end
    end

    % we want to include cases InLoc got lost, but not blacklisted queries (=no reference poses)
    nMeaningfulErrors = length(errors) - nBlacklistedQueries;
    scores((i-1)/2+1) = count / nMeaningfulErrors * 100;
    inMapScores((i-1)/2+1) = inMapCount / inMapSize * 100;
    offMapScores((i-1)/2+1) = offMapCount / offMapSize * 100;
end
fprintf(summaryFile, '\n');
for i=1:size(scores,2)
    if i > 1
        fprintf(summaryFile, ' / ');
    end
    fprintf(summaryFile, '%g [%%]', scores(i));
end
fprintf(summaryFile, '\n');

% inMap
for i=1:size(inMapScores,2)
    if i > 1
        fprintf(summaryFile, ' / ');
    end
    fprintf(summaryFile, '%0.2f [%%]', inMapScores(i));
end
fprintf(summaryFile, ' -- InMap\n');

% offMap
for i=1:size(offMapScores,2)
    if i > 1
        fprintf(summaryFile, ' / ');
    end
    fprintf(summaryFile, '%0.2f [%%]', offMapScores(i));
end
fprintf(summaryFile, ' -- OffMap\n');
fprintf(summaryFile, '\nInLocCIIRC got completely lost %d out of %d times. Not included in the mean/median/std errors.\n', ...
        inLocCIIRCLostCount, nQueries);
fprintf(summaryFile, '\nErrors (InLocCIIRC poses wrt reference poses):\n');
fprintf(summaryFile, ' \ttranslation [m]\torientation [deg]\n');
fprintf(summaryFile, 'Mean\t%0.2f\t%0.2f\n', meanTranslation, meanOrientation);
fprintf(summaryFile, 'Median\t%0.2f\t%0.2f\n', medianTranslation, medianOrientation);
fprintf(summaryFile, 'Std\t%0.2f\t%0.2f\n', stdTranslation, stdOrientation);
fclose(summaryFile);
disp(fileread(params.evaluation.summary.path));