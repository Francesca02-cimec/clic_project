%% AUDITORY DISCRIMINATION PILOT - graded difficulty (blocks get harder)
clear
close all

cfg.nBlocks         = 3;
cfg.blockTrials     = [20 10 10];  % valid trials per block
cfg.clickTotal      = 8;           % total clicks per trial (CHANGE TO 10 FOR OTHER TRIALS; max |delta| = clickTotal/2)
cfg.clickDur        = 0.030;       % click duration, s
cfg.clickFreq       = 2000;        % Hz (unused while clic.wav is used)

% ---- DIFFICULTY RAMP: one entry per block, easy -> hard ----------------
% delta = shift from an even split. Click difference (L-R) = 2*delta.
% Smaller |delta| = harder. delta 0 = tie (no true answer, correct side random).
cfg.blockDeltas     = {[-4 -3 3 4], [-3 -2 2 3], [-2 -1 0 1 2]};
% Seconds allowed to reach a circle after the audio ends (shorter = harder).
% Inf = no time limit (block 1).
cfg.blockTimeout    = [Inf 0.8 0.4];
% Minimum movement speed (0 = no check). Same formula as your trackSpeed:
% mean pixels/sample over 10 samples must exceed this, else "DON'T STOP"
cfg.blockMinVel     = [0 0 5];
% Click rate in Hz per block (faster = harder). Kept constant by default
% so only evidence strength and time pressure change; try [8 10 12] to ramp it.
cfg.blockClickRate  = [10 10 10];

cfg.mouseSampleDT   = 1/60;
cfg.feedbackOn      = true;
cfg.feedbackDur     = 0.6;
cfg.circleRadius    = 50;
cfg.circleColor     = [200 200 200];
cfg.startBoxSize    = 30;          % half-width of start square, px
cfg.bgColor         = [0 0 0];
cfg.textColor       = [255 255 255];
cfg.fs              = 48000;
cfg.skipSyncTests   = 1;           % set to 0 for real data collection
%% ================================================

assert(numel(cfg.blockDeltas) == cfg.nBlocks && numel(cfg.blockTimeout) == cfg.nBlocks && ...
       numel(cfg.blockMinVel) == cfg.nBlocks && numel(cfg.blockClickRate) == cfg.nBlocks && ...
       numel(cfg.blockTrials) == cfg.nBlocks, ...
       'Every cfg.block* setting needs one entry per block');

subjID = input('Enter subject ID: ', 's');
if isempty(subjID); subjID = 'test'; end
stamp = datestr(now, 'yyyymmdd_HHMMSS');

resultsFolder = 'results - auditory discrimination task';
if ~exist(resultsFolder, 'dir'); mkdir(resultsFolder); end
outFile     = fullfile(resultsFolder, sprintf('data_%s_%s.csv', subjID, stamp));
trajCsvFile = fullfile(resultsFolder, sprintf('trajectories_%s_%s.csv', subjID, stamp));
trajMatFile = fullfile(resultsFolder, sprintf('trajectories_%s_%s.mat', subjID, stamp));

% One row per ATTEMPT (including too-slow / stopped trials that get repeated)
results = struct('row',{}, 'block',{}, 'trialInBlock',{}, 'delta',{}, 'nLeft',{}, 'nRight',{}, ...
                 'deltaLR',{}, 'correctSide',{}, 'response',{}, 'accuracy',{}, 'MT',{}, ...
                 'status',{}, 'valid',{}, 'timeout',{}, 'minVel',{}, 'clickRate',{});
allTrajectories = {};   % allTrajectories{row} = Nx3 [time_s, x_pix, y_pix]
trajFid = -1;

try
    %% ---- Setup ----
    PsychDefaultSetup(2);
    KbName('UnifyKeyNames');
    Screen('Preference', 'SkipSyncTests', cfg.skipSyncTests);

    screenNumber = max(Screen('Screens'));
    [win, winRect] = PsychImaging('OpenWindow', screenNumber, cfg.bgColor);
    [screenXpix, screenYpix] = Screen('WindowSize', win);
    Screen('TextSize', win, 30);
    Screen('TextFont', win, 'Arial');
    ListenChar(2);

    posLeft  = [screenXpix * 0.25, screenYpix * 0.25];
    posRight = [screenXpix * 0.75, screenYpix * 0.25];
    r = cfg.circleRadius;
    rectLeft  = CenterRectOnPoint([0 0 2*r 2*r], posLeft(1),  posLeft(2));
    rectRight = CenterRectOnPoint([0 0 2*r 2*r], posRight(1), posRight(2));

    startPos  = [screenXpix * 0.5, screenYpix * 0.9];
    sb = cfg.startBoxSize;
    startRect = CenterRectOnPoint([0 0 2*sb 2*sb], startPos(1), startPos(2));
    inBox = @(x, y) max(abs(x - startPos(1)), abs(y - startPos(2))) <= sb;

    %% ---- Audio ----
    InitializePsychSound(1);
    pahandle = PsychPortAudio('Open', [], 1, 1, cfg.fs, 2);

    %% ---- Trajectory CSV ----
    trajFid = fopen(trajCsvFile, 'w');
    fprintf(trajFid, 'row,block,time_s,x_pix,y_pix\n');

    %% ---- Instructions ----
    instrText = [ ...
        'AUDITORY DISCRIMINATION TASK\n\n' ...
        'On each trial you will hear a single stream of clicks played through\n' ...
        'your headphones, jumping back and forth between your LEFT ear and\n' ...
        'your RIGHT ear.\n\n' ...
        'One ear will always end up receiving MORE clicks overall.\n\n' ...
        'Before each trial your cursor will reset to a box at the bottom of\n' ...
        'the screen.\n\n' ...
        'Your task is to decide which ear received the LARGER number of clicks and\n' ...
        'MOVE THE MOUSE CURSOR to touch the corresponding circle as quickly and\n' ...
        'accurately as you can.\n\n' ...
        'Left ear had more clicks -> reach the UPPER-LEFT circle.\n' ...
        'Right ear had more clicks -> reach the UPPER-RIGHT circle.\n\n' ...
        'Each trial will start as soon as you leave the start box.\n' ...
        'The task gets harder as it goes on.\n\n' ...
        'Press SPACE to begin.'];
    DrawFormattedText(win, instrText, 'center', 'center', cfg.textColor);
    Screen('Flip', win);
    WaitForSpecificKey('space');
    Screen('TextSize', win, 50);

    %% ---- Blocks ----
    row = 0;
    for b = 1:cfg.nBlocks
        nPerBlock = cfg.blockTrials(b);
        rate   = cfg.blockClickRate(b);
        tmo    = cfg.blockTimeout(b);
        minVel = cfg.blockMinVel(b);
        queue  = BuildBlockQueue(cfg.blockDeltas{b}, nPerBlock, cfg.clickTotal);

        msg = sprintf('Block %d of %d\n\nPress SPACE to start', b, cfg.nBlocks);
        DrawFormattedText(win, msg, 'center', 'center', cfg.textColor);
        Screen('Flip', win);
        WaitForSpecificKey('space');
        
        nValid = 0;
        q = 0;
        while nValid < nPerBlock
            q = q + 1;   % invalid trials are appended to the queue, so q never overruns
            nLeft = queue(q,1); nRight = queue(q,2);
            correctSide = queue(q,3); delta = queue(q,4);

            stereoBuffer = BuildInterleavedClickTrain(nLeft, nRight, rate, ...
                                cfg.clickDur, cfg.clickFreq, cfg.fs);
            PsychPortAudio('FillBuffer', pahandle, stereoBuffer);
            trainDurSec = size(stereoBuffer, 2) / cfg.fs;

            % Wait for the participant to get into the start box
            DrawScene(win, cfg, startRect, rectLeft, rectRight, '', cfg.textColor);
            [x, y, buttons] = GetMouse;
            while  ~inBox(x, y)
                [x, y, buttons] = GetMouse;
            end
            
            % Wait for them to get out
            [x, y] = GetMouse(win);
            while inBox(x, y)
                if EscPressed()
                    SaveAll(results, allTrajectories, cfg, outFile, trajMatFile);
                    error('Experiment aborted by user (ESC key).');
                end
                WaitSecs(0.001);
                [x, y] = GetMouse(win);
            end

            [respSide, MT, traj, status] = TrackReach(win, posLeft, posRight, r, tmo, ...
                                cfg.mouseSampleDT, trainDurSec, minVel, pahandle);

            if strcmp(status, 'abort')
                SaveAll(results, allTrajectories, cfg, outFile, trajMatFile);
                error('Experiment aborted by user (ESC key).');
            end

            valid = ~strcmp(status, 'stopped') && ~isnan(respSide);
            acc = double(respSide == correctSide);   % NaN == x is false -> 0
            if valid; nValid = nValid + 1; else; queue(end+1,:) = queue(q,:); end %#ok<SAGROW>

            if cfg.feedbackOn
                fbColor = cfg.textColor;
                if strcmp(status, 'stopped')
                    fbStr = 'DON''T STOP'; fbColor = [255 0 0];
                elseif isnan(respSide)
                    fbStr = 'Too slow!';
                elseif acc == 1
                    fbStr = 'Correct';
                else
                    fbStr = 'Incorrect';
                end
                DrawScene(win, cfg, startRect, rectLeft, rectRight, fbStr, fbColor);
                WaitSecs(cfg.feedbackDur);
            end

            % Log
            row = row + 1;
            results(row).row          = row;
            results(row).block        = b;
            results(row).trialInBlock = q;
            results(row).delta        = delta;
            results(row).nLeft        = nLeft;
            results(row).nRight       = nRight;
            results(row).deltaLR      = nLeft - nRight;
            results(row).correctSide  = SideLabel(correctSide);
            results(row).response     = SideLabel(respSide);
            results(row).accuracy     = acc;
            results(row).MT           = MT;
            results(row).status       = status;
            results(row).valid        = valid;
            results(row).timeout      = tmo;
            results(row).minVel       = minVel;
            results(row).clickRate    = rate;
            allTrajectories{row} = traj; %#ok<SAGROW>
            for k = 1:size(traj, 1)
                fprintf(trajFid, '%d,%d,%.4f,%.2f,%.2f\n', row, b, traj(k,1), traj(k,2), traj(k,3));
            end

            % Back to the start box
            DrawScene(win, cfg, startRect, rectLeft, rectRight, 'Go back to the box', cfg.textColor);
            [x, y] = GetMouse(win);
            while ~inBox(x, y)
                if EscPressed()
                    SaveAll(results, allTrajectories, cfg, outFile, trajMatFile);
                    error('Experiment aborted by user (ESC key).');
                end
                WaitSecs(0.001);
                [x, y] = GetMouse(win);
            end
        end
    end

    %% ---- End ----
    DrawFormattedText(win, 'Thank you! The experiment is complete.', 'center', 'center', cfg.textColor);
    Screen('Flip', win);
    WaitSecs(2);

    SaveAll(results, allTrajectories, cfg, outFile, trajMatFile);
    fprintf('Trial data saved to: %s\n', outFile);
    fprintf('Trajectories saved to: %s and %s\n', trajCsvFile, trajMatFile);

    fclose(trajFid);
    ListenChar(0);
    PsychPortAudio('Close', pahandle);
    sca;

catch err
    ListenChar(0);
    if trajFid ~= -1
        fclose(trajFid);
    end
    try PsychPortAudio('Close'); end %#ok<TRYNC>
    sca;
    rethrow(err);
end

%% ================= LOCAL FUNCTIONS =================

function queue = BuildBlockQueue(deltaList, nPerBlock, clickTotal)
    % Balanced, shuffled list of trials for one block.
    % Columns: [nLeft nRight correctSide delta]
    idx = mod(0:nPerBlock-1, numel(deltaList)) + 1;
    deltas = deltaList(idx);
    deltas = deltas(randperm(numel(deltas)));
    queue = zeros(nPerBlock, 4);
    for k = 1:nPerBlock
        nLeft  = clickTotal/2 - deltas(k);
        nRight = clickTotal - nLeft;
        if nLeft > nRight
            correctSide = 1;
        elseif nLeft < nRight
            correctSide = 2;
        else
            correctSide = randi(2);
        end
        queue(k,:) = [nLeft nRight correctSide deltas(k)];
    end
end

function DrawScene(win, cfg, startRect, rectLeft, rectRight, msg, msgColor)
    Screen('FrameRect', win, cfg.textColor, startRect, 2);
    Screen('FillOval', win, cfg.circleColor, rectLeft);
    Screen('FillOval', win, cfg.circleColor, rectRight);
    if ~isempty(msg)
        DrawFormattedText(win, msg, 'center', 'center', msgColor);
    end
    Screen('Flip', win);
end

function click = GenerateClick(fs, dur, ~)
    nsamples_dur = round(dur*fs);
    audio_samples = audioread('clic.wav');
    audio_samples = audio_samples';
    length_clic = size(audio_samples, 2);
    startSample = round(length_clic/2 - nsamples_dur/2);
    click = audio_samples(1, startSample : startSample + nsamples_dur - 1);
end

function stereo = BuildInterleavedClickTrain(nLeft, nRight, rate, dur, freq, fs)
    % Single click stream at `rate` clicks/s; each click goes to one ear.
    % Order of left/right clicks is random.
    click = GenerateClick(fs, dur, freq);
    isi = 1 / rate;
    totalClicks = nLeft + nRight;
    seq = [1*ones(1,nLeft) 2*ones(1,nRight)];
    seq = seq(randperm(length(seq)));

    nSamplesTotal = round((totalClicks - 1) * isi * fs) + length(click) + 1;
    stereo = zeros(2, nSamplesTotal);
    for k = 1:totalClicks
        startIdx = round((k - 1) * isi * fs) + 1;
        ch = seq(k);
        stereo(ch, startIdx:startIdx + length(click) - 1) = ...
            stereo(ch, startIdx:startIdx + length(click) - 1) + click;
    end
end

function tf = EscPressed()
    [keyIsDown, ~, keyCode] = KbCheck(-1);
    tf = keyIsDown && keyCode(KbName('ESCAPE'));
end

function WaitForSpecificKey(keyName)
    targetCode = KbName(keyName);
    while true
        [keyIsDown, ~, keyCode] = KbCheck(-1);
        if keyIsDown && keyCode(targetCode)
            while KbCheck(-1); end
            break;
        end
    end
end

function [respSide, MT, traj, status] = TrackReach(win, posLeft, posRight, radius, ...
        timeoutSec, sampleDT, trainDurSec, minVelocity, pahandle)
    % Plays the click train, then samples the mouse until a circle is
    % entered, the movement stalls, or timeoutSec has passed after audio end.
    % timeoutSec may be Inf (no limit). status: 'ok' | 'timeout' | 'stopped' | 'abort'
    tResp = PsychPortAudio('Start', pahandle, 1, 0, 1);
    WaitSecs('UntilTime', tResp + trainDurSec);
    PsychPortAudio('Stop', pahandle, 1);

    tEnd = tResp + trainDurSec + timeoutSec;
    traj = zeros(0, 3);
    respSide = NaN;
    MT = NaN;
    status = 'timeout';
    n = 0;

    while GetSecs < tEnd
        [mx, my] = GetMouse(win);
        t = GetSecs - tResp;
        n = n + 1;
        traj(n, :) = [t, mx, my];

        if EscPressed()   % needed because the window can now be unlimited
            status = 'abort'; break;
        end

        if hypot(mx - posLeft(1), my - posLeft(2)) <= radius
            respSide = 1; MT = t; status = 'ok'; break;
        elseif hypot(mx - posRight(1), my - posRight(2)) <= radius
            respSide = 2; MT = t; status = 'ok'; break;
        end

        % Stall check every 10 samples (same formula as the original)
        if minVelocity > 0 && n >= 10 && mod(n, 10) == 0
            s = hypot(traj(n,2) - traj(n-9,2), traj(n,3) - traj(n-9,3));
            if s/10 <= minVelocity
                status = 'stopped'; break;
            end
        end
        WaitSecs(sampleDT);
    end
end

function SaveAll(results, allTrajectories, cfg, outFile, matFile)
    if ~isempty(results)
        writetable(struct2table(results), outFile);
    end
    save(matFile, 'allTrajectories', 'cfg', 'results');
end

function label = SideLabel(sideCode)
    if isnan(sideCode)
        label = 'none';
    elseif sideCode == 1
        label = 'left';
    elseif sideCode == 2
        label = 'right';
    else
        label = 'invalid';
    end
end