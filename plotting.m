%% PLOTTING
% --- load data
clear all

[f, p] = uigetfile('results - auditory discrimination task/trajectories_*.csv', 'Select trajectories .csv');
if isequal(f, 0); return; end
trajectories = readtable(fullfile(p, f));

[f, p] = uigetfile('results - auditory discrimination task/data_*.csv', 'Select data .csv');
if isequal(f, 0); return; end
results = readtable(fullfile(p,f));

if ismember('valid', results.Properties.VariableNames)
    keep = results.valid == 1;
end

validTrials = results.trial(keep);
results = results(keep,:);
trajectories = trajectories(ismember(trajectories.trial, validTrials),:);

%% movement time against L-R
deltaLR = [results.deltaLR];
MT   = [results.MT];
LR   = unique(deltaLR);

m = zeros(1,7);
st = zeros(1,7);

for i = 1:length(m)
    idx = deltaLR == LR(i)
    m(i) = mean(MT(idx), 'omitnan');
    st(i) = std(MT(idx),'omitnan');
end
figure
errorbar(LR, m, st, 'o-', 'LineWidth', 1.5)
xlabel('Click difference (left - right)')
ylabel('Mean movement time (s)')
xlim([min(LR)-1, max(LR)+1])

%% response likelihood against L-R
deltaLR = [results.deltaLR];
LR = unique(deltaLR);
accuracy = [results.accuracy];
acc = [];
for i = 1:length(LR)
    idx_acc = deltaLR == LR(i);
    acc = [acc mean(accuracy(idx_acc))];
end
plot(LR, acc)
xlabel('L-R')
ylabel('accuracy')
xlim([min(LR), max(LR)])

%% trajectories 
screenW = 1920;  screenH = 1080;     % screen used in the experiment
startX  = screenW * 0.5;             % start box x -> 0

deltaLR = results.deltaLR;
LR      = unique(deltaLR);
nPoints = 1000;
tq      = linspace(0, 1, nPoints);
allTraj = cell(1, numel(LR));

for i = 1:numel(LR)
    trials = results.trial(deltaLR == LR(i));
    T = nan(nPoints, 2, numel(trials));

    for k = 1:numel(trials)
        idx = trajectories.trial == trials(k);
        tt  = trajectories.time_s(idx);
        x   = trajectories.x_pix(idx) - startX;     % centered on the start box
        y   = trajectories.y_pix(idx);

        if numel(tt) < 2, continue, end
        [tt, u] = unique(tt);
        x = x(u);  y = y(u);
        if numel(tt) < 2, continue, end

        tn = (tt - tt(1)) / (tt(end) - tt(1));      % normalise time to 0-1
        T(:, 1, k) = interp1(tn, x, tq);
        T(:, 2, k) = interp1(tn, y, tq);
    end
    allTraj{i} = mean(T, 3, 'omitnan');
end

figure; hold on
cols = parula(numel(LR));
for i = 1:numel(LR)
    m = allTraj{i};
    plot(m(:,1), m(:,2), 'Color', cols(i,:), 'LineWidth', 1.5, ...
         'DisplayName', sprintf('LR = %g', LR(i)));
end

% reference: response circles (radius 50 px) and start box (half-width 30 px)
th = linspace(0, 2*pi, 100);  r = 50;
plot(-0.25*screenW + r*cos(th), 0.25*screenH + r*sin(th), 'k', 'HandleVisibility', 'off')
plot( 0.25*screenW + r*cos(th), 0.25*screenH + r*sin(th), 'k', 'HandleVisibility', 'off')
rectangle('Position', [-30, 0.9*screenH - 30, 60, 60])

set(gca, 'YDir', 'reverse')
xlabel('x position relative to start box (px)')
ylabel('y position (px)')
legend show
axis equal

%% performance improvement
results(isnan(results.trial),:) = [];
accuracy = results.accuracy_1;
trials = results.trial;

m100 = mean(accuracy(1:50));
std100 = std(accuracy(1:50));

m200 = mean(accuracy(51:100));
std200 = std(accuracy(51:100));

m300 = mean(accuracy(101:150));
std300 = std(accuracy(101:150));

m400 = mean(accuracy(151:end));
std400 = std(accuracy(151:end));

mean_all = [m100 m200 m300 m400];
std_all  = [std100 std200 std300 std400];
n_all    = [100 100 100 numel(accuracy(301:end))];
sem_all  = std_all ./ sqrt(n_all);

blockEnd = [50 100 150 200];   % x axis: number of trials completed

errorbar(blockEnd, mean_all, sem_all, '-o', 'LineWidth', 1.5)
xlabel('Number of trials')
ylabel('Accuracy')
xlim([0 blockEnd(end) + 50])


%% x and y position against time
x_position = trajectories.x_pix;
y_position = trajectories.y_pix;
time = trajectories.time_s;

Ntrial = max(trajectories.trial);

figure; hold on;
for i=1:Ntrial
    this_trial = trajectories.trial==i;    
plot(1:sum(this_trial), time(this_trial),'Color',[0 0 1 .3]);
end


figure; hold on;
for i=1:Ntrial
    this_trial = trajectories.trial==i;    
plot(time(this_trial), x_position(this_trial),'Color',[0 0 1 .3]);
end

xlabel('time (ms)')
ylabel('x position')

figure;
plot(time, y_position)
xlabel('time (ms)')
ylabel('y position')

figure; hold on;
for i=1:Ntrial
    this_trial = trajectories.trial==i;    
plot(x_position(this_trial), y_position(this_trial),'Color',[0 i/Ntrial 1 .3]);
end
xlabel('x position')
ylabel('y position')
set(gca,'YDir','reverse')

%% TRAJECTORIES BY CONGRUENCE OF THE CLICK EVIDENCE (side-independent)
% Every reach is expressed relative to the side the participant reached:
% trials that ended LEFT are mirrored around the screen midline, so all
% reaches end at the same circle (top). Congruence = how many more clicks
% the reached side had than the other side:
%   positive -> evidence congruent with the reach (blue)
%   zero     -> tie (grey)
%   negative -> evidence incongruent with the reach (orange)
% Darker colour = larger click difference. The screen is rotated so the
% midline is a horizontal dashed line.
clear; close all


%% ---- Settings ----
nPts         = 1000;              % points per time-normalised trajectory
ss           = get(0,'ScreenSize');
screenX      = ss(3);             % screen width in px used in the experiment (CHANGE IF DIFFERENT)
screenY      = ss(4);             % screen height in px used in the experiment (CHANGE IF DIFFERENT)
circleR      = 50;
blueBase     = [0 0.45 0.85];     % left evidence  (congruent)
orangeBase   = [0.95 0.5 0.05];   % right evidence (incongruent), mirrored onto the left
tieColor     = [0.55 0.55 0.55];
useValidOnly = true;

%% ---- Prepare data ----
% Expects: results      (table or struct array, cleaned or not)
%          trajectories (table from the trajectories CSV)  OR
%          trajs / allTrajectories (cell array, one [time x y] matrix per trial number)
if istable(results), results = table2struct(results); end
trialNum  = [results.trial];
deltaLR   = [results.deltaLR];                      % nLeft - nRight (signed)
corrRight = strcmp({results.correctSide}, 'right');

% Right-evidence trials are mirrored onto the left side.
% Ties (deltaLR == 0) are mirrored when the randomly assigned correct side was right.
mirror = (deltaLR < 0) | (deltaLR == 0 & corrRight);

if useValidOnly
    ok = [results.valid] == 1;
else
    ok = true(size(deltaLR));
end

if ~exist('trajs', 'var')
    if exist('allTrajectories', 'var')
        trajs = allTrajectories;
    else
        if ~istable(trajectories), trajectories = struct2table(trajectories); end
        trajs = cell(1, max(trialNum));
        for t = trialNum
            r = trajectories.trial == t;
            trajs{t} = [trajectories.time_s(r), trajectories.x_pix(r), trajectories.y_pix(r)];
        end
    end
end

levels = unique(deltaLR(ok));
levels = levels(:)';                                % row, so the loop gets one level at a time
maxLev = max(abs(levels));

%% ---- Geometry (rotated: horizontal axis = progress, vertical axis = screen x relative to start) ----
startY   = screenY * 0.9;
progress = @(y) startY - y;
midX     = screenX / 2;                             % start box x -> 0

figure('Color', 'w', 'Position', [100 100 1000 600]); hold on
yline(0, 'k--', 'LineWidth', 1.5);
th = linspace(0, 2*pi, 100);
plot(progress(screenY*0.25) + circleR*cos(th), -0.25*screenX + circleR*sin(th), ...
     'Color', [0.6 0.6 0.6], 'LineWidth', 1.5);     % left response circle

hLeg = []; legTxt = {};
for lev = levels
    idx = find(ok & deltaLR == lev);
    if isempty(idx), continue, end

    frac = abs(lev) / maxLev;
    w = 0.35 + 0.65*frac;
    if lev > 0
        col = blueBase * w + (1 - w);
        lab = 'Left evidence (congruent)';
    elseif lev < 0
        col = orangeBase * w + (1 - w);
        lab = 'Right evidence (incongruent), flipped';
    else
        col = tieColor;
        lab = 'Tie';
    end

    M = nan(numel(idx), nPts, 2);
    for k = 1:numel(idx)
        T = trajs{trialNum(idx(k))};
        if isempty(T) || size(T, 1) < 2, continue, end
        xx = T(:, 2) - midX;                        % centre on the start box
        if mirror(idx(k)), xx = -xx; end            % flip right-evidence trials onto the left
        q = linspace(1, size(T, 1), nPts);
        M(k, :, 1) = interp1(1:size(T, 1), progress(T(:, 3)), q);
        M(k, :, 2) = interp1(1:size(T, 1), xx, q);
    end

    nUsed = nnz(~isnan(M(:, 1, 1)));
    if nUsed == 0, continue, end
    mx = squeeze(mean(M(:, :, 1), 1, 'omitnan'));
    my = squeeze(mean(M(:, :, 2), 1, 'omitnan'));
    h = plot(mx, my, 'Color', col, 'LineWidth', 2.5);
    hLeg(end+1) = h; %#ok<SAGROW>
    legTxt{end+1} = sprintf('%s, %+d clicks (n=%d)', lab, lev, nUsed); %#ok<SAGROW>
end

xlabel('Progress towards the circles (px)');
ylabel('Horizontal position relative to start box (px)');
title('Mean trajectories by click evidence (right-evidence trials flipped onto the left)');
legend(hLeg, legTxt, 'Location', 'eastoutside');
xlim([-20 progress(screenY*0.25) + circleR + 20]);
ylim([-0.3*screenX 0.3*screenX]);
box on

%% ---- Settings ----
dt           = 1/60;              % time step of the common time grid (s)
tMax         = 1.2;               % plot window in s; 0 = audio onset
smoothWin    = 5;                 % Gaussian smoothing window in samples (~80 ms at 60 Hz)
minN         = 5;                 % only plot time bins where at least this many trials contribute
flipBy       = 'response';        % 'response': x velocity positive towards the circle that was reached
                                  % 'evidence': x velocity positive towards the side with more clicks
                                  % 'none'    : raw x velocity, positive = rightward (left/right reaches cancel)
useValidOnly = true;

%% ---- Prepare data ----
% Expects: results      (table or struct array)
%          trajectories (table from the trajectories CSV)  OR
%          trajs / allTrajectories (cell array, one [time x y] matrix per trial number)
if istable(results), results = table2struct(results); end
trialNum = [results.trial];
nTr      = numel(results);

switch flipBy
    case 'response'
        sgn = 2*double(strcmp({results.response}, 'right')) - 1;      % right reach: +1, left reach: -1
    case 'evidence'
        sgn = 2*double(strcmp({results.correctSide}, 'right')) - 1;   % right evidence: +1, left evidence: -1
    otherwise
        sgn = ones(1, nTr);                                           % raw: positive = rightward
end

if useValidOnly
    ok = [results.valid] == 1;
else
    ok = true(1, nTr);
end

if ~exist('trajs', 'var')
    if exist('allTrajectories', 'var')
        trajs = allTrajectories;
    else
        if ~istable(trajectories), trajectories = struct2table(trajectories); end
        trajs = cell(1, max(trialNum));
        for t = trialNum
            r = trajectories.trial == t;
            trajs{t} = [trajectories.time_s(r), trajectories.x_pix(r), trajectories.y_pix(r)];
        end
    end
end

tGrid = 0:dt:tMax;
nT    = numel(tGrid);

if isfield(results, 'trainDur')
    tAudioEnd = mean([results.trainDur]);           % end of the click train (s from audio onset)
else
    tAudioEnd = NaN;
end

%% ---- Velocity of every trial on the common time grid ----
VX = nan(nTr, nT);
VY = nan(nTr, nT);
for i = find(ok)
    T = trajs{trialNum(i)};
    if isempty(T) || size(T, 1) < smoothWin + 2, continue, end

    [tt, u] = unique(T(:, 1));
    x = T(u, 2);
    y = T(u, 3);
    if numel(tt) < smoothWin + 2, continue, end

    % resample onto a regular time grid, smooth, then differentiate
    tg = (ceil(tt(1)/dt)*dt) : dt : tt(end);
    if numel(tg) < smoothWin + 2, continue, end
    xg = smoothdata(interp1(tt, x, tg), 'gaussian', smoothWin);
    yg = smoothdata(interp1(tt, y, tg), 'gaussian', smoothWin);

    vx = sgn(i) * gradient(xg, dt);                 % see flipBy for the sign convention
    vy = -gradient(yg, dt);                         % positive = up the screen

    ib = round(tg / dt) + 1;
    in = ib >= 1 & ib <= nT;
    VX(i, ib(in)) = vx(in);
    VY(i, ib(in)) = vy(in);
end

%% ---- Mean and SEM across all trials ----
nBin = sum(~isnan(VX), 1);                          % trials contributing to each time bin
good = nBin >= minN;

mvx = mean(VX, 1, 'omitnan');   svx = std(VX, 0, 1, 'omitnan') ./ sqrt(nBin);
mvy = mean(VY, 1, 'omitnan');   svy = std(VY, 0, 1, 'omitnan') ./ sqrt(nBin);
nUsed = nnz(any(~isnan(VX), 2));

%% ---- Plot ----
col = [0 0.45 0.85];

% ---- Figure 1: x velocity ----
figure('Color', 'w', 'Position', [100 100 900 400]);
axX = axes; hold on
fill([tGrid(good) fliplr(tGrid(good))], [mvx(good)+svx(good) fliplr(mvx(good)-svx(good))], ...
     col, 'FaceAlpha', 0.2, 'EdgeColor', 'none');
plot(tGrid(good), mvx(good), 'Color', col, 'LineWidth', 2.5);
yline(0, 'k:');
switch flipBy
    case 'response', ylab = 'x velocity towards reached circle (px/s)';
    case 'evidence', ylab = 'x velocity towards evidence side (px/s)';
    otherwise,       ylab = 'x velocity (px/s), + = right';
end
ylabel(ylab);
title(sprintf('Average x velocity across all trials (n = %d, mean \\pm SEM)', nUsed));
xlabel('Time from audio onset (s)');
box on
if ~isnan(tAudioEnd)
    xline(axX, tAudioEnd, 'k--', 'audio end', 'LabelVerticalAlignment', 'bottom');
end
xlim(axX, [0 tMax]);

% ---- Figure 2: y velocity ----
figure('Color', 'w', 'Position', [130 130 900 400]);
axY = axes; hold on
fill([tGrid(good) fliplr(tGrid(good))], [mvy(good)+svy(good) fliplr(mvy(good)-svy(good))], ...
     col, 'FaceAlpha', 0.2, 'EdgeColor', 'none');
plot(tGrid(good), mvy(good), 'Color', col, 'LineWidth', 2.5);
yline(0, 'k:');
ylabel('y velocity up the screen (px/s)');
xlabel('Time from audio onset (s)');
title(sprintf('Average y velocity across all trials (n = %d, mean \\pm SEM)', nUsed));
box on
if ~isnan(tAudioEnd)
    xline(axY, tAudioEnd, 'k--', 'audio end', 'LabelVerticalAlignment', 'bottom');
end
xlim(axY, [0 tMax]);