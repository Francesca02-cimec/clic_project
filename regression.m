%% Impact of single clicks on (1) choice [logistic] and (2) trajectory [linear]
% RAW-TIME version: trajectories are analysed and plotted in seconds from
% movement onset (no time normalisation).
% Click coding: L = +1, R = -1  -> positive coefficient = a LEFT click pushes
% towards a LEFT choice / LEFTWARD trajectory. Only valid trials (status == ok).
% Requires: Statistics and Machine Learning Toolbox (fitglm, fitlm).

clear; clc;
addpath('results - auditory discrimination task')
dataFile = uigetfile('.csv');
trajFile = uigetfile('.csv');
nClicks  = 8;

% ---- raw-time settings ----------------------------------------------------
dtGrid    = 0.01;    % s, spacing of the common raw-time grid
tMaxPrct  = 90;      % grid extends to this percentile of movement durations
minTrials = 30;      % min. trials still moving for a time point to be estimated

%% Load
d = readtable(dataFile, 'TextType', 'string');
t = readtable(trajFile);
v = d(d.valid == 1 & d.status == "ok", :);
fprintf('Valid trials: %d of %d\n', height(v), height(d));

chars = char(v.click_seq);            % trials x 8 characters
C  = double(chars == 'L') * 2 - 1;    % L = +1, R = -1
cn = "click" + (1:nClicks);           % click1 ... click8

T = array2table(C, 'VariableNames', cellstr(cn));
T.choiceLeft = double(v.response == "left");
T.sumClicks  = sum(C, 2);
assert(all(T.sumClicks == v.L_minus_R), 'Click coding does not match L_minus_R');

%% 1. LOGISTIC: P(choose left) ~ click1..click8
f1   = "choiceLeft ~ " + strjoin(cn, " + ");
mdl1 = fitglm(T, f1, 'Distribution', 'binomial');
disp(mdl1);

mdl0  = fitglm(T, 'choiceLeft ~ 1', 'Distribution', 'binomial');
lrAll = mdl0.Deviance - mdl1.Deviance;               % omnibus LR test
pAll  = 1 - chi2cdf(lrAll, nClicks);
mcF   = 1 - mdl1.LogLikelihood / mdl0.LogLikelihood; % McFadden R^2
predOK = mean((mdl1.Fitted.Probability > 0.5) == T.choiceLeft);
fprintf('LR chi2(%d) = %.2f, p = %.3g, McFadden R2 = %.3f, accuracy = %.3f\n', ...
    nClicks, lrAll, pAll, mcF, predOK);

% Are all clicks weighted equally? (8 free weights vs. one summed predictor)
mdlS = fitglm(T, 'choiceLeft ~ sumClicks', 'Distribution', 'binomial');
lrEq = mdlS.Deviance - mdl1.Deviance;
pEq  = 1 - chi2cdf(lrEq, nClicks - 1);
fprintf('Equal-weights test: LR chi2(%d) = %.2f, p = %.3g\n', nClicks-1, lrEq, pEq);

%% 2. Trajectory summaries in RAW time (lateral deviation, positive = LEFT)
trials = v.trial;
nTr    = numel(trials);
dur    = nan(nTr, 1);                 % movement duration (s)
meanDevRaw = nan(nTr, 1);             % time-averaged deviation over the movement
endDevRaw  = nan(nTr, 1);             % deviation at the end of the movement
trajT = cell(nTr, 1);                 % raw time (s from onset)
trajX = cell(nTr, 1);                 % raw lateral deviation (px)

for i = 1:nTr
    g = t(t.trial == trials(i), :);
    g = sortrows(g, 'time_s');
    if height(g) < 5, continue; end
    tt = g.time_s - g.time_s(1);                 % seconds from movement onset
    x  = -(g.x_pix - g.x_pix(1));                % positive = LEFT
    if tt(end) <= 0, continue; end
    trajT{i} = tt;  trajX{i} = x;
    dur(i)        = tt(end);
    meanDevRaw(i) = trapz(tt, x) / tt(end);      % time-weighted mean deviation
    endDevRaw(i)  = x(end);
end
ok = ~isnan(dur);
fprintf('Trials with usable trajectories: %d\n', sum(ok));
fprintf('Movement duration: median %.3f s, %d-th prctile %.3f s, max %.3f s\n', ...
    median(dur(ok)), tMaxPrct, prctile(dur(ok), tMaxPrct), max(dur(ok)));

% Common raw-time grid; NaN after a trial's movement has ended (no extrapolation)
tMax = prctile(dur(ok), tMaxPrct);
grid = 0:dtGrid:tMax;
nTime = numel(grid);
Y = nan(nTr, nTime);
for i = find(ok)'
    Y(i, :) = interp1(trajT{i}, trajX{i}, grid, 'linear');   % NaN beyond end
end

T2 = T(ok, :);
Y  = Y(ok, :);
T2.meanDev = meanDevRaw(ok);
T2.endDev  = endDevRaw(ok);
T2.duration = dur(ok);

%% LINEAR: trajectory ~ click1..click8
for dv = ["meanDev", "endDev"]
    mdl = fitlm(T2, dv + " ~ " + strjoin(cn, " + "));
    fprintf('\n=== LINEAR: %s ===\n', dv);
    disp(mdl);
    fprintf('R2 = %.3f, adjR2 = %.3f\n', mdl.Rsquared.Ordinary, mdl.Rsquared.Adjusted);
    if dv == "meanDev", mMean = mdl; end
end

%% Time-resolved click effects in raw time
% At each time point only trials that are still moving (have data) are used.
X = [ones(sum(ok), 1), table2array(T2(:, cellstr(cn)))];
B = nan(nClicks, nTime);
nAvail = sum(~isnan(Y), 1);                  % trials contributing at each time
for j = 2:nTime                              % j = 1 (t = 0): deviation is 0 by construction
    idx = ~isnan(Y(:, j));
    if nnz(idx) < minTrials, continue; end
    b = X(idx, :) \ Y(idx, j);
    B(:, j) = b(2:end);
end

%% Figure
figure('Position', [100 100 1800 400]);

subplot(1, 4, 1);
ci = coefCI(mdl1);
errorbar(1:nClicks, mdl1.Coefficients.Estimate(2:end), ...
    mdl1.Coefficients.Estimate(2:end) - ci(2:end, 1), ...
    ci(2:end, 2) - mdl1.Coefficients.Estimate(2:end), 'o-', 'LineWidth', 1.2);
yline(0, '-', 'Color', [.5 .5 .5]);
xlabel('Click position'); ylabel('Log-odds of left choice per left click');
title('Logistic: click \rightarrow choice');

subplot(1, 4, 2);
ci = coefCI(mMean);
errorbar(1:nClicks, mMean.Coefficients.Estimate(2:end), ...
    mMean.Coefficients.Estimate(2:end) - ci(2:end, 1), ...
    ci(2:end, 2) - mMean.Coefficients.Estimate(2:end), 'o-', 'LineWidth', 1.2);
yline(0, '-', 'Color', [.5 .5 .5]);
xlabel('Click position'); ylabel('Mean lateral deviation (px) per left click');
title('Linear: click \rightarrow trajectory');

subplot(1, 4, 3); hold on;
cols = parula(nClicks);
for i = 1:nClicks
    plot(grid, B(i, :), 'Color', cols(i, :), 'LineWidth', 1.2);
end
yline(0, '-', 'Color', [.5 .5 .5]);
xlabel('Time from movement onset (s)'); ylabel('Coefficient (px)');
title('Click effect over movement'); legend(cellstr(cn), 'NumColumns', 2, 'Location', 'northwest');
xlim([0 tMax]);

subplot(1, 4, 4);
plot(grid, nAvail, 'k', 'LineWidth', 1.2); hold on;
yline(minTrials, '--', 'Color', [.5 .5 .5]);
xlabel('Time from movement onset (s)'); ylabel('Trials still moving');
title('Trials contributing at each time'); xlim([0 tMax]);

saveas(gcf, 'click_effects_matlab_rawtime.png');