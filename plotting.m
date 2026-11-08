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
deltaLR = [results.L_minus_R];
MT   = [results.MT];
LR   = unique(deltaLR);
n_trials = length(results.trial);

m = zeros(1,length(LR));
st = zeros(1,length(LR));
sem = zeros(1, length(LR));

for i = 1:length(m)
    idx = deltaLR == LR(i);
    m(i) = mean(MT(idx), 'omitnan');
    st(i) = std(MT(idx),'omitnan');
    sem(i) = st(i)/sqrt(n_trials);
end


figure
errorbar(LR, m, sem, 'o-', 'LineWidth', 1.5)
xlabel('Click difference (left - right)')
ylabel('Mean movement time (s)')
xlim([min(LR)-1, max(LR)+1])

%% movement time density plot
if istable(results)
    MT = results.MT(results.valid == 1);
else
    MT = [results.MT]';
    MT = MT([results.valid] == 1);
end
MT = MT(~isnan(MT));

[f, xi] = ksdensity(MT, 'Support', 'positive');   % movement time can't be negative
f = f(:)';  xi = xi(:)';

col = [0 0.45 0.85];
figure('Color', 'w'); hold on
fill([xi fliplr(xi)], [f zeros(size(f))], col, 'FaceAlpha', 0.25, 'EdgeColor', 'none');
plot(xi, f, 'Color', col, 'LineWidth', 2);
xline(mean(MT), 'k--', sprintf('mean = %.3f s', mean(MT)), 'LabelVerticalAlignment', 'bottom');
xlabel('Movement time (s)');
ylabel('Density');
title(sprintf('Movement time (n = %d trials)', numel(MT)));
box on

%% response likelihood against L-R
deltaLR = [results.L_minus_R];
LR = unique(deltaLR);
accuracy = [results.accuracy];
acc = [];
for i = 1:length(LR)
    idx_acc = deltaLR == LR(i);
    acc = [acc mean(accuracy(idx_acc))];
end
figure
plot(LR, acc)
xlabel('L-R')
ylabel('accuracy')
xlim([min(LR), max(LR)])

%% trajectories 
screenW = 1920;  screenH = 1080;     % screen used in the experiment
startX  = screenW * 0.5;             % start box x -> 0

deltaLR = results.L_minus_R;
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
nBlocks = 5;

% valid trials only, in presentation order
if istable(results)
    acc = results.accuracy(results.valid == 1);
else
    acc = [results.accuracy]';
    acc = acc([results.valid] == 1);
end
acc = acc(~isnan(acc));

n     = numel(acc);
edges = round(linspace(0, n, nBlocks + 1));    % block boundaries, fine if n isn't divisible by nBlocks

m = nan(1, nBlocks);  sem = nan(1, nBlocks);
for b = 1:nBlocks
    a      = acc(edges(b)+1 : edges(b+1));
    m(b)   = mean(a);
    sem(b) = std(a) / sqrt(numel(a));
end

blockEnd = edges(2:end);                       % valid trials completed at the end of each block

figure('Color', 'w'); hold on
errorbar(blockEnd, m, sem, '-o', 'LineWidth', 1.5)
yline(0.5, 'k:', 'chance');
xlabel('Number of valid trials completed')
ylabel('Accuracy')
xlim([0, blockEnd(end) * 1.1])
ylim([0 1])
box on


%% x and y position against time
x_position = trajectories.x_pix;
y_position = trajectories.y_pix;
time = trajectories.time_s;
ss           = get(0,'ScreenSize');
screenX      = ss(3);             
screenY      = ss(4); 


figure; hold on;
for i=1:Ntrial
    this_trial = trajectories.trial==i;    
plot(1:sum(this_trial), time(this_trial),'Color',[0 0 1 .3]);
end


figure; hold on;
for i=1:Ntrial
    this_trial = trajectories.trial==i;    
plot(time(this_trial), x_position(this_trial) - screenX*0.5-200,'Color',[0 0 1 .7]);
end

xlabel('time (ms)')
ylabel('x position')

figure; hold on;
for i=1:Ntrial
    this_trial = trajectories.trial==i;    
plot(time(this_trial), y_position(this_trial) - screenX*0.5-200,'Color',[0 0 1 .7]);
end

xlabel('time (ms)')
ylabel('y position')

figure; hold on;
for i=1:Ntrial
    this_trial = trajectories.trial==i;    
plot(x_position(this_trial), y_position(this_trial),'Color',[0 0 1 .3]);
end
xlabel('x position')
ylabel('y position')
set(gca,'YDir','reverse')

%% MEAN TRAJECTORIES OF LEFT CHOICES, BY CLICK EVIDENCE (L clicks - R clicks)
% Only trials in which the participant reached the LEFT circle are used, so
% nothing is mirrored. Each trial's congruence with the choice is
%   L_minus_R = nLeft - nRight
%   positive -> more clicks on the chosen (left) side: congruent   (blue)
%   zero     -> tie                                                (grey)
%   negative -> more clicks on the other (right) side: incongruent (orange)
% Darker colour = larger click difference. The screen is rotated so the
% horizontal axis is progress towards the circles and the vertical axis is
% horizontal screen position relative to where the trajectories start (0 = start).

%% ---- Settings ----
nPts         = 1000;              % points per time-normalised trajectory
screenX      = 1536;              % screen width in px used in the experiment (CHANGE IF DIFFERENT)
screenY      = 864;               % screen height in px used in the experiment (CHANGE IF DIFFERENT)
circleXY     = [384 216];         % centre of the left response circle in screen px (x, y)
circleR      = 50;                % radius of the response circle in px
blueBase     = [0 0.45 0.85];     % congruent
orangeBase   = [0.95 0.5 0.05];   % incongruent
tieColor     = [0.55 0.55 0.55];
useValidOnly = true;
alignToTrialStart = true;         % true: every trial starts exactly at (0,0) (its own first sample is subtracted)
                                  % false: all trials share one origin (see originFromData below)
minTrials    = 1;                 % skip levels with fewer left-choice trials than this
originFromData = true;            % true: 0 = median starting point of the plotted trajectories
                                  % false: 0 = centre of the start box (from the screen size)

%% ---- Prepare data ----
% Expects: results      (table or struct array)
%          trajectories (table from the trajectories CSV)  OR
%          trajs / allTrajectories (cell array, one [time x y] matrix per trial number)
if istable(results), results = table2struct(results); end
trialNum = [results.trial];
if isfield(results, 'L_minus_R')
    LmR = [results.L_minus_R];                      % nLeft - nRight
else
    LmR = [results.deltaLR];
end

toLeft = strcmp({results.response}, 'left');        % only left choices
if useValidOnly
    ok = [results.valid] == 1 & toLeft;
else
    ok = toLeft;
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

levels = unique(LmR(ok));
levels = levels(:)';                                % row, so the loop gets one level at a time
maxLev = max(abs(levels));

%% ---- Geometry ----
% Origin (0,0): where the plotted trajectories start
if originFromData
    firstXY = nan(numel(trialNum), 2);
    for i = find(ok)
        T = trajs{trialNum(i)};
        if ~isempty(T), firstXY(i, :) = T(1, 2:3); end   % first sample of the trial [x y]
    end
    x0 = median(firstXY(:, 1), 'omitnan');
    y0 = median(firstXY(:, 2), 'omitnan');
else
    x0 = screenX / 2;                               % start box centre
    y0 = screenY * 0.9;
end
progress = @(y) y0 - y;                             % up the screen = positive

figure('Color', 'w', 'Position', [100 100 1000 600]); hold on
yline(0, 'k--', 'LineWidth', 1.5);
th = linspace(0, 2*pi, 100);
plot(progress(circleXY(2)) + circleR*cos(th), (circleXY(1) - x0) + circleR*sin(th), ...
     'Color', [0.6 0.6 0.6], 'LineWidth', 1.5);     % left response circle

plot(progress(circleXY(2)), circleXY(1) - x0, 'k+', 'MarkerSize', 8);   % circle centre
hLeg = []; legTxt = {};
for lev = levels
    idx = find(ok & LmR == lev);
    if numel(idx) < minTrials, continue, end

    w = 0.35 + 0.65 * abs(lev) / maxLev;
    if lev > 0
        col = blueBase * w + (1 - w);
        lab = 'Congruent';
    elseif lev < 0
        col = orangeBase * w + (1 - w);
        lab = 'Incongruent';
    else
        col = tieColor;
        lab = 'Tie';
    end

    M = nan(numel(idx), nPts, 2);
    for k = 1:numel(idx)
        T = trajs{trialNum(idx(k))};
        if isempty(T) || size(T, 1) < 2, continue, end
        if alignToTrialStart
            xx   = T(:, 2) - T(1, 2);               % lateral position: 0 at the start of the trial
            prog = T(1, 3) - T(:, 3);               % progress: 0 at the start of the trial
        else
            xx   = T(:, 2) - x0;                    % lateral position relative to the shared origin
            prog = progress(T(:, 3));
        end                          % 0 = where the trajectories start, no mirroring
        q = linspace(1, size(T, 1), nPts);
        M(k, :, 1) = interp1(1:size(T, 1), prog, q);
        M(k, :, 2) = interp1(1:size(T, 1), xx, q);
    end

    nUsed = nnz(~isnan(M(:, 1, 1)));
    if nUsed == 0, continue, end
    mx = squeeze(mean(M(:, :, 1), 1, 'omitnan'));
    my = squeeze(mean(M(:, :, 2), 1, 'omitnan'));
    h = plot(mx, my, 'Color', col, 'LineWidth', 2.5);
    hLeg(end+1) = h; %#ok<SAGROW>
    legTxt{end+1} = sprintf('%s, L-R = %+d (n=%d)', lab, lev, nUsed); %#ok<SAGROW>
end

xlabel('Progress towards the circles (px)');
ylabel('Horizontal position relative to trajectory start (px)');
title('Left choices: mean trajectories by click evidence (L - R clicks)');
legend(hLeg, legTxt, 'Location', 'eastoutside');
xlim([-20 progress(circleXY(2)) + circleR + 20]);
ylim([-0.3*screenX 0.3*screenX]);
set(gca,'YDir','reverse')
daspect([1 1 1]);                                   % equal scaling, so the circle looks round
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