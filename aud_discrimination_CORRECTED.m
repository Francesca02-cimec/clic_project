%% AUDITORY DISCRIMINATION
clear
close all

cfg.nTrials         = 100;           % number of VALID trials to collect
cfg.clickRate       = 10;           % clicks per second (ISI = 1/clickRate)
cfg.clickTotal      = 8;            % total number of clicks % CHANGE TO 10 FOR OTHER TRIALS
cfg.clickDur        = 0.030;        % duration of each click, in seconds (30 ms)
cfg.clickFreq       = 2000;         % Hz, carrier frequency of the click "pip"
cfg.deltaAll           = [-3 -2 -1 0 1 2 3]; % click-count difference parameter (see generateTrial)
cfg.pEar            = 0.50;
cfg.audioLead       = 0;
cfg.iti             = 0;            % inter-trial interval range, in seconds
cfg.respTimeout     = 0.4;          % seconds allowed to reach a circle after audio ends
cfg.minVelocity     = 3;            % min. mean speed in pixels per sample, computed over 10 samples
cfg.velGraceSamples = 11;           % no velocity check before this many samples (~330 ms at 60 Hz)
cfg.allowEarlyResponse = true;      % true: a circle can be reached while the clicks are still playing
cfg.mouseSampleDT   = 1/60;         % seconds between trajectory samples (~60 Hz)
cfg.feedbackOn      = true;         % show "Correct" / "Incorrect" after each response
cfg.feedbackDur     = 0.6;          % seconds feedback is shown
cfg.circleRadius    = 50;           % pixels, radius of response circles
cfg.circleColor     = [200 200 200];
cfg.startBoxSize    = 30;           % pixels, half-width of the start-position square marker
cfg.bgColor         = [0 0 0];
cfg.textColor       = [255 255 255];
cfg.fs              = 48000;        % audio sampling rate, Hz
cfg.skipSyncTests   = 1;            % set to 0 for real data collection / timing-critical use
%% ================================================

subjID = input('Enter subject ID: ', 's');
if isempty(subjID); subjID = 'test'; end
stamp = datestr(now, 'yyyymmdd_HHMMSS');

screenFolder = 'image task';
resultsFolder = 'results - auditory discrimination task';
if ~exist(resultsFolder, 'dir'); mkdir(resultsFolder); end
if ~exist(screenFolder, 'dir');  mkdir(screenFolder);  end

outPath     = fullfile(resultsFolder, sprintf('data_%s_%s.csv', subjID, stamp));
trajCsvFile = fullfile(resultsFolder, sprintf('trajectories_%s_%s.csv', subjID, stamp));
matPath     = fullfile(resultsFolder, sprintf('trajectories_%s_%s.mat', subjID, stamp));

% Preallocate trial-level results (all fields are declared here, in the order they are logged)
results = struct('trial', {}, 'correctSide', {}, 'nLeft', {}, 'nRight', {}, ...
                 'startSide', {}, 'response', {}, 'accuracy', {}, 'MT', {}, ...
                 'trainDur', {}, 'L_minus_R', {}, 'delta', {}, 'status', {}, 'valid', {});
allTrajectories = cell(1, cfg.nTrials); % each cell: Nx3 [time_s, x_pix, y_pix]; time 0 = audio onset

trajFid = -1;

try
    %% ---- Setup ----
    PsychDefaultSetup(2);
    KbName('UnifyKeyNames');
    Screen('Preference', 'SkipSyncTests', cfg.skipSyncTests);

    screens = Screen('Screens');
    screenNumber = max(screens);
    [win, winRect] = PsychImaging('OpenWindow', screenNumber, cfg.bgColor);

    [screenXpix, screenYpix] = Screen('WindowSize', win);
    [xC, yC] = RectCenter(winRect);
    Screen('TextSize', win, 30);
    Screen('TextFont', win, 'Arial');
    ListenChar(2);
    % Cursor stays visible throughout: this is a reaching task, the
    % participant needs continuous visual feedback of cursor position.

    % Response circle centers: upper-left quadrant / upper-right quadrant
    posLeft  = [screenXpix * 0.25, screenYpix * 0.25];
    posRight = [screenXpix * 0.75, screenYpix * 0.25];
    r = cfg.circleRadius;
    rectLeft  = CenterRectOnPoint([0 0 2*r 2*r], posLeft(1),  posLeft(2));
    rectRight = CenterRectOnPoint([0 0 2*r 2*r], posRight(1), posRight(2));

    % Start position for the cursor: bottom-center of the screen
    startPos = [screenXpix * 0.5, screenYpix * 0.9];
    sb = cfg.startBoxSize;
    startRect = CenterRectOnPoint([0 0 2*sb 2*sb], startPos(1), startPos(2));

    %% ---- Audio setup ----
    InitializePsychSound(1)
    % master device runs continuously, so the hardware never has to wake up
    pamaster = PsychPortAudio('Open', [], 1+8, 1, cfg.fs, 2);
    PsychPortAudio('Start', pamaster, 0, 0, 1);      % repetitions = 0: run until stopped
    % slave device used for the trial sounds
    pahandle = PsychPortAudio('OpenSlave', pamaster, 1, 2);

    %% ---- Trajectory CSV file ----
    trajFid = fopen(trajCsvFile, 'w');
    fprintf(trajFid, 'trial,time_s,x_pix,y_pix\n');

    %% Trials setup
    trialList = zeros(cfg.nTrials,4);
    for k = 1:cfg.nTrials
        [nLeft, nRight, correctSide, delta] = generateTrial(cfg.deltaAll, cfg.clickTotal);
        trialList(k,:) = [nLeft nRight correctSide delta];
    end

    %% ---- Instructions ----
    instrText = [ ...
        'AUDITORY DISCRIMINATION TASK\n\n' ...
        'On each trial you will hear a single stream of clicks played through\n' ...
        'your headphones, jumping back and forth between your LEFT ear and\n' ...
        'your RIGHT ear.\n\n' ...
        'One ear will always end up receiving MORE clicks overall \n\n' ...
        'Before each trial your cursor will reset to a box at the bottom of\n' ...
        'the screen,\n\n'...
        'Your task is to decide which ear received the LARGER number of clicks and\n' ...
        'MOVE THE MOUSE CURSOR to touch the corresponding circle as quickly and\n' ...
        'accurately as you can.\n\n' ...
        'Left ear had more clicks -> reach the UPPER-LEFT circle.\n' ...
        'Right ear had more clicks -> reach the UPPER-RIGHT circle.\n\n' ...
        'Each trial will start as soon as you leave the start box. \n\n',...
        'Press SPACE to begin.'];
    DrawFormattedText(win, instrText, 'center', 'center', cfg.textColor);
    Screen('Flip', win);
    WaitForSpecificKey('space');

    %% ---- Trial loop ----
    % Response screen: reset cursor again, draw the two circles
    Screen('TextSize', win, 50);

    Screen('FrameRect', win, cfg.textColor, startRect, 2);
    Screen('FillOval', win, cfg.circleColor, rectLeft);
    Screen('FillOval', win, cfg.circleColor, rectRight);
    Screen('Flip', win, 0, 1)

    SetMouse(startPos(1), startPos(2), win)

    nValid    = 0;
    attempt   = 0;
    preloaded = false;

    while nValid < cfg.nTrials

        % ESC aborts the experiment; the data is saved in the catch block below
        CheckEscape();

        if ~preloaded

            PsychPortAudio('Stop', pahandle, 1)

            attempt     = attempt + 1;
            nLeft       = trialList(attempt, 1);
            nRight      = trialList(attempt, 2);
            correctSide = trialList(attempt, 3);
            delta       = trialList(attempt, 4);

            % prepare the audio
            startSide = randi(2);
            stereoBuffer = BuildInterleavedClickTrain(nLeft, nRight, cfg.clickRate, ...
                                     cfg.clickDur, cfg.clickFreq, cfg.fs, startSide);
            PsychPortAudio('FillBuffer', pahandle, stereoBuffer);

            trainDurSec = size(stereoBuffer, 2) / cfg.fs;
            preloaded = true;
        end

        [x, y, buttons] = GetMouse;

        if max(abs(x - startPos(1)), abs(y - startPos(2))) > cfg.startBoxSize

            % Audio starts inside TrackReach; the mouse is sampled DURING the audio
            [respSide, MT, traj, status] = TrackReach(win, posLeft, posRight, r, ...
                                                      trainDurSec, pahandle, cfg);
            abortNow = strcmp(status, 'aborted');   % ESC pressed during the reach

            % ---- Score the trial and decide whether it counts ----
            switch status
                case 'ok'
                    acc   = double(respSide == correctSide);
                    valid = 1;
                    nValid = nValid + 1;
                    if acc == 1
                        fbStr = 'Correct';
                    else
                        fbStr = 'Incorrect';
                    end
                case 'not finished'
                    acc   = NaN;
                    valid = 0;
                    fbStr = 'DONT STOP';
                    trialList(end+1, :) = [nLeft nRight correctSide delta]; % repeat later
                case 'aborted'   % ESC mid-trial: keep what was recorded, don't repeat the trial
                    acc   = NaN;
                    valid = 0;
                    fbStr = '';
                otherwise % 'timeout'
                    acc   = NaN;
                    valid = 0;
                    fbStr = 'Too slow!';
                    trialList(end+1, :) = [nLeft nRight correctSide delta]; % repeat later
            end

            % ---- Feedback (write it, then erase it) ----
            if cfg.feedbackOn && ~abortNow
                screenRect = Screen('Rect', win);
                color = cfg.textColor;
                if strcmp(fbStr, 'DONT STOP')
                    color = [255 0 0];
                end
                [~, ~, boundsText] = DrawFormattedText(win, fbStr, 'center', 'center', color, [], [], [], [], [], screenRect);
                Screen('Flip', win, 0, 1);
                if WaitSecsOrEsc(cfg.feedbackDur)   % true if ESC was pressed meanwhile
                    abortNow = true;                % finish logging this trial, then abort
                end

                padding = 10;
                coveredText = InsetRect(boundsText, -padding, -padding);
                Screen('FillRect', win, cfg.bgColor, coveredText)
                Screen('Flip', win, 0, 1)
            end

            % ---- Log trial-level data ----
            results(attempt).trial       = attempt;
            results(attempt).correctSide = SideLabel(correctSide);
            results(attempt).nLeft       = nLeft;
            results(attempt).nRight      = nRight;
            results(attempt).startSide   = SideLabel(startSide);
            results(attempt).response    = SideLabel(respSide);   % 'none' if no circle was reached
            results(attempt).accuracy    = acc;                   % NaN if no circle was reached
            results(attempt).MT          = MT;                    % s from audio onset to circle (NaN if none)
            results(attempt).trainDur    = trainDurSec;           % MT - trainDur = time after audio end
            results(attempt).L_minus_R   = nLeft - nRight;
            results(attempt).delta       = delta;
            results(attempt).status      = status;
            results(attempt).valid       = valid;

            % ---- Store + write out full trajectory for this trial ----
            allTrajectories{attempt} = traj;
            if ~isempty(traj)
                fprintf(trajFid, '%d,%.4f,%.2f,%.2f\n', ...
                        [attempt * ones(1, size(traj, 1)); traj']);
            end

            % ESC was pressed during this trial: it is now logged, so abort
            if abortNow
                error('Experiment:abort', 'Experiment aborted by user (ESC key).');
            end

            % ---- Wait until the mouse goes back to the starting position ----
            [~, ~, boundsText] = DrawFormattedText(win, 'Go back to the box', 'center', 'center', [255 255 255]);
            Screen('Flip', win, 0, 1)

            [x, y] = GetMouse(win);
            while max(abs(x - startPos(1)), abs(y - startPos(2))) > cfg.startBoxSize
                CheckEscape();
                [x, y] = GetMouse(win);
            end

            padding = 10;
            coveredText = InsetRect(boundsText, -padding, -padding);
            Screen('FillRect', win, cfg.bgColor, coveredText)
            Screen('Flip', win, 0, 1)

            preloaded = false;
        end
    end

    %% ---- End screen ----
    Screen('Flip', win)
    DrawFormattedText(win, 'Thank you! The experiment is complete.', ...
                       'center', 'center', cfg.textColor);
    Screen('Flip', win);
    WaitSecs(2);

    %% ---- Save data ----
    fclose(trajFid);      % close the trajectory CSV so everything is flushed to disk
    trajFid = -1;

    SaveData(results, allTrajectories, cfg, outPath, matPath);

    fprintf('Trial data saved to: %s\n', outPath);
    fprintf('Trajectories saved to: %s and %s\n', trajCsvFile, matPath);

    %% ---- Cleanup ----
    ListenChar(0);
    PsychPortAudio('Close', pahandle);
    sca;

catch err
    % Runs on ESC and on any error: clean up, then save whatever is available
    ListenChar(0);
    if trajFid ~= -1
        fclose(trajFid);      % flushes the trajectory CSV written so far
        trajFid = -1;
    end
    try PsychPortAudio('Close'); end
    sca;

    try
        SaveData(results, allTrajectories, cfg, outPath, matPath);
        fprintf('Partial data saved to: %s\n', outPath);
        fprintf('Trajectories saved to: %s and %s\n', trajCsvFile, matPath);
    catch saveErr
        warning('Could not save partial data: %s', saveErr.message);
    end

    if strcmp(err.identifier, 'Experiment:abort')
        fprintf('Experiment aborted by user (ESC key).\n');
    else
        rethrow(err);
    end
end

%% ================= LOCAL FUNCTIONS =================

function SaveData(results, allTrajectories, cfg, outPath, matPath)
    % Writes trial-level CSV (if there is any data) and the trajectories .mat
    if ~isempty(results)
        writetable(struct2table(results), outPath);
    end
    % drop the unused preallocated cells at the end
    last = find(~cellfun(@isempty, allTrajectories), 1, 'last');
    allTrajectories = allTrajectories(1:last);   % 1:[] gives an empty cell array
    save(matPath, 'allTrajectories', 'cfg');
end

function click = GenerateClick(fs, dur, freq)
    % Brief windowed tone pip used as a single "click"
    nsamples_dur = round(dur*fs);

    [audio_samples, fs_file] = audioread("clic.wav");
    audio_samples = audio_samples';
    length_clic = length(audio_samples);

    samples_clic_dur = round(length_clic/2-nsamples_dur/2);
    click = audio_samples(1, samples_clic_dur : samples_clic_dur + nsamples_dur - 1);

end

function stereo = BuildInterleavedClickTrain(nLeft, nRight, rate, dur, freq, fs, startSide)
    % Builds a 2 x nSamples stereo buffer containing a SINGLE click
    % stream at a constant rate of `rate` clicks/second (one click event
    % every 1/rate seconds), with each individual click routed entirely
    % to the left or right channel. Click order is randomly shuffled.
    click = GenerateClick(fs, dur, freq);
    isi = 1 / rate;

    totalClicks = nLeft + nRight;

    seq = [1*ones(1,nLeft) 2*ones(1,nRight)];   % 1 = left channel, 2 = right channel
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

function WaitForSpecificKey(keyName)
    % Blocks until the named key is pressed (ignores all other keys)
    targetCode = KbName(keyName);
    while true
        CheckEscape();
        [keyIsDown, ~, keyCode] = KbCheck(-1);
        if keyIsDown && keyCode(targetCode)
            while KbCheck(-1); end % wait for release
            break;
        end
    end
end

function [respSide, MT, traj, status] = TrackReach(win, posLeft, posRight, radius, ...
                                                   trainDurSec, pahandle, cfg)
    % Starts the audio and samples the mouse at a fixed rate (cfg.mouseSampleDT)
    % from audio onset until a response circle is entered, the mouse stalls,
    % or trainDurSec + cfg.respTimeout seconds have elapsed. The mouse is
    % sampled WHILE the clicks are playing (no blocking wait).
    %
    % Returns:
    %   respSide - 1 (left circle), 2 (right circle), or NaN if no circle was reached
    %   MT       - seconds from audio onset to circle entry, or NaN
    %   traj     - Nx3 matrix [time_s, x_pix, y_pix]; time 0 = audio onset
    %   status   - 'ok'           a circle was reached
    %              'not finished' the mouse stalled (velocity criterion)
    %              'timeout'      no circle reached in time
    %              'aborted'      ESC was pressed during the reach

    respSide = NaN;
    MT       = NaN;
    status   = 'timeout';
    trialEnd = trainDurSec + cfg.respTimeout;

    traj = nan(ceil(trialEnd / cfg.mouseSampleDT) + 20, 3);   % preallocated
    n = 0;

    tResp   = PsychPortAudio('Start', pahandle, 1, 0, 1);     % t = 0 is audio onset
    tNext   = tResp;
    audioOn = true;

    while true
        t = GetSecs - tResp;
        if t > trialEnd
            break
        end

        % ESC pressed: stop here but still return the trajectory recorded so far
        if IsEscapePressed()
            status = 'aborted';
            break
        end

        % stop the audio once the click train is over (non-blocking)
        if audioOn && t >= trainDurSec
            PsychPortAudio('Stop', pahandle, 0);
            audioOn = false;
        end

        [mx, my] = GetMouse(win);
        n = n + 1;
        if n > size(traj, 1)
            traj = [traj; nan(100, 3)]; %#ok<AGROW>
        end
        traj(n, :) = [t, mx, my];

        % velocity check every 10 samples (10 intervals, so n-10 .. n), after a grace period
        if n >= cfg.velGraceSamples && mod(n, 10) == 0
            s = hypot(traj(n,2) - traj(n-10,2), traj(n,3) - traj(n-10,3));
            if s / 10 <= cfg.minVelocity
                status = 'not finished';
                break
            end
        end

        % circle check (optionally only after the audio has ended)
        if cfg.allowEarlyResponse || t >= trainDurSec
            if hypot(mx - posLeft(1), my - posLeft(2)) <= radius
                respSide = 1;  MT = t;  status = 'ok';  break
            elseif hypot(mx - posRight(1), my - posRight(2)) <= radius
                respSide = 2;  MT = t;  status = 'ok';  break
            end
        end

        % fixed-rate sampling, scheduled against absolute time
        tNext = tNext + cfg.mouseSampleDT;
        WaitSecs('UntilTime', tNext);
    end

    if audioOn && strcmp(status, 'aborted')
        PsychPortAudio('Stop', pahandle, 0);   % response before the audio ended
    end

    traj = traj(1:n, :);
end

function tf = IsEscapePressed()
    % true if ESC is currently down on any keyboard
    persistent escCode
    if isempty(escCode); escCode = KbName('ESCAPE'); end
    [down, ~, keyCode] = KbCheck(-1);
    tf = down && keyCode(escCode);
end

function CheckEscape()
    % Throws a dedicated error if ESC is down; the catch block saves the data
    if IsEscapePressed()
        error('Experiment:abort', 'Experiment aborted by user (ESC key).');
    end
end

function escPressed = WaitSecsOrEsc(durSec)
    % Like WaitSecs, but returns true as soon as ESC is pressed
    tEnd = GetSecs + durSec;
    escPressed = false;
    while GetSecs < tEnd
        if IsEscapePressed()
            escPressed = true;
            return
        end
        WaitSecs(0.005);
    end
end

function label = SideLabel(sideCode)
    % Converts 1/2/NaN side codes to readable labels for the data file
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

function [nLeft, nRight, correctSide, delta] = generateTrial(deltaAll, clickTotal)

        delta = deltaAll(randi(numel(deltaAll)));
        nLeft = clickTotal/2 - delta;
        nRight = clickTotal - nLeft;

        if nLeft > nRight
            correctSide = 1;
        elseif nLeft < nRight
            correctSide = 2;
        elseif nLeft == nRight
             correctSide = randi(2);
        end
end