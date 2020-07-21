%% initialization
load(params.input.qlist.path);
densePV_matname = fullfile(params.output.dir, 'densePV_top10_shortlist.mat');
load(densePV_matname, 'ImgList');

mkdirIfNonExistent(params.evaluation.dir);
mkdirIfNonExistent(params.evaluation.retrieved.poses.dir);
mkdirIfNonExistent(params.evaluation.query_vs_synth.dir);

%% visual evaluation
for i=1:size(query_imgnames_all,2)
    queryName = query_imgnames_all{i};
    queryImage = imread(fullfile(params.dataset.query.dir, queryName));
    
    fun = @(x) strcmp(ImgList(x).queryname,queryName);
    tf = arrayfun(fun, 1:numel(ImgList));
    ImgListRecord = ImgList(find(tf));
    cutoutPath = ImgListRecord.topNname{1};
    synthPath = fullfile(params.output.synth.dir, queryName, buildCutoutName(cutoutPath, params.output.synth.matformat));
    load(synthPath, 'RGBpersp');
    numRows = size(queryImage,1);
    numCols = size(queryImage,2);
    
    synthImage = RGBpersp;
    if isempty(synthImage)
        synthImage = zeros(numRows, numCols, 3, 'uint8');
    else
        synthImage = imresize(synthImage, [numRows numCols]);
    end

    queryId = strsplit(queryName, '.');
    queryId = queryId{1};
    imwrite(queryImage, fullfile(params.evaluation.query_vs_synth.dir, sprintf('%s-query.jpg', queryId)))
    imwrite(synthImage, fullfile(params.evaluation.query_vs_synth.dir, sprintf('%s-synth.jpg', queryId)))

    %imshowpair(queryImage, synthImage, 'montage');
    %saveas(gcf, fullfile(params.evaluation.query_vs_synth.dir, queryName));
end

%% quantitative results

% do not compute a numerical error for those queries I dont have reference pose! (they are on params.blacklistedQueryInd)
% this would screw up the resulting statistics
nQueries = size(query_imgnames_all,2);
whitelistedQueries = ones(1,nQueries);
if isfield(params, 'blacklistedQueryInd')
    blacklistedQueryNames = arrayfun(@(idx) sprintf('%d.jpg', idx), params.blacklistedQueryInd, 'UniformOutput', false);
    blacklistedQueries = false(1,nQueries);
    for i=1:nQueries
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

    [P,T,R,spaceName] = loadPoseFromInLocCIIRC_demo(queryId, ImgList, params);
    if ~strcmp(spaceName, referenceSpace) || ~whitelistedQueries(i)
        T = nan(3,1);
        R = nan(3,3);
        P = nan(4,4);
    end

    if any(isnan(P(:))) && whitelistedQueries(i)
        inLocCIIRCLostCount = inLocCIIRCLostCount + 1;
    end

    queryPoseFilename = sprintf('%d.txt', queryId);
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
errorsTable = struct2table(errors);
errors = table2struct(sortrows(errorsTable, 'queryId'));
errorsFile = fopen(params.evaluation.errors.path, 'w');
fprintf(errorsFile, 'id,inMap,translation,orientation\n');
for i=1:nQueries
    inMapStr = 'No';
    if errors(i).inMap
        inMapStr = 'Yes';
    end
    fprintf(errorsFile, '%d,%s,%0.2f,%0.2f\n', errors(i).queryId, inMapStr, errors(i).translation, errors(i).orientation);
end
fclose(errorsFile);

% mean errors
errorsFile = fopen(params.evaluation.mean.errors.path, 'w');
fprintf(errorsFile, ' \ttranslation [m]\torientation [deg]\n');
meanTranslation = mean([errors(~isnan([errors.translation])).translation]);
meanOrientation = mean([errors(~isnan([errors.orientation])).orientation]);
fprintf(errorsFile, 'Mean\t%0.2f\t%0.2f\n', meanTranslation, meanOrientation);
fclose(errorsFile);

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
    for j=1:size(errors,1)
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
    nMeaningfulErrors = size(errors,1) - nBlacklistedQueries;
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
fprintf(summaryFile, '\nInLocCIIRC got completely lost %d out of %d times. (Not included in the mean errors)\n', ...
        inLocCIIRCLostCount, nQueries);
fprintf(summaryFile, '\nErrors (InLocCIIRC poses wrt reference poses):\n');
fprintf(summaryFile, fileread(params.evaluation.mean.errors.path));
fclose(summaryFile);
disp(fileread(params.evaluation.summary.path));