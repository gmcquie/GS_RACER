function [passFailFlag] = waitForAcknowledgement(commandType)
% =========================================================================
% [passFailFlag] = waitForAcknowledgement(commandType)
%     This function should be called after a command is sent to the serial
%     port and poles the serial port for an acknowledgement from the MR.
%     Returns 1 when acknowledgement is received. Also has the capability
%     to return the CR and MR status strings for further processing within
%     the 'request_status_Callback(' function.
%
% Inputs: 
%   commandType - Character that was sent as the command identifier.
%
% Outputs:
%   passFailFlag - This is a boolean flag stating whether the command was
%                   successfully executed. (Acknowledgement received)
%
% UPDATE LOG ==============================================================
% Creation: 1/9/2015 by John Russo
% Update 1: 1/12/2015 by Thomas Green
%    - Added a case statement for different processing if it's a status
%    request. This will also need to be done for an image.
% Update 2: 1/19/2015 by Thomas Green
%    - Added support for receiving images through the serial port! Further
%    work will include adding support for comm dropouts as well as all
%    command types.
% Update 3: 2/22/2015 by Thomas Green
%    - There have been miscellaneous updates over the past couple weeks but
%    the major change is to have individual timeouts for each different
%    command type. Also adding functionality to the rappelling command to
%    detect if a rappelling failure was reported.
% =========================================================================
global gsSerialBuffer CR_status MR_status % globally shared serial port to XBee/MR
% globally shared status strings
CR_status = cell(2,1);
MR_status = cell(1,1);

% Other variables =========================================================
passFailFlag = 0;
fullPicString = '';
tic
time_elapsed = toc;

% Determine the proper timeout duration ===================================
switch commandType
    case 'I'
        timeout_dur = 300;   % seconds
    case 'R'
        timeout_dur = 200;  % seconds
        % Set up the data save file
        date_str = datestr(now);
        date_str = date_str(end-8:end);
        date_str(date_str == ':') = '_';
        fname_str = ['Rappelling Testing\rappelData' date_str '.txt'];
        rappelDataFID = fopen(fname_str,'w+');
    case 'S'
        timeout_dur = 10;   % seconds
    case 'D'
        timeout_dur = 100;   % seconds
        % Set up the data save file
        date_str = datestr(now);
        date_str = date_str(end-8:end);
        date_str(date_str == ':') = '_';
        fname_str = ['Driving Testing\driveData' date_str '.txt'];
        driveDataFID = fopen(fname_str,'w+');
    otherwise
        timeout_dur = 30;   % seconds
end
        
while ~passFailFlag && time_elapsed < timeout_dur
    
    % wait for serial data ================================================
    if gsSerialBuffer.BytesAvailable > 0
        switch commandType
            case 'D' % DRIVING COMMAND
                response = fscanf(gsSerialBuffer,'%s'); % Get the response string
                fprintf('%.2f s: %s\n',time_elapsed,response);
                
                fprintf(driveDataFID,'%.2f \t %s\n',time_elapsed,response);
                
                % Make sure we got back the appropriate response
                if length(response) >= 3 && strcmp(response(end-2:end),'$DP')
                    passFailFlag = 1;
                end
                
            case 'I' % IMAGING COMMAND
                % If we have an image command then we need to collect the
                % image as a response and write it to the 'picString.txt'
                % file. We need to keep collecting the string until we get
                % to the 'ENDOFFILE' delimiter at the end of the
                % transmitted message.
                response = char(fread(gsSerialBuffer,gsSerialBuffer.BytesAvailable,'char')'); % Get the response string
%                 disp(['Got imaging response: ' response])
                
                % Concatenate the response onto the full string
                fullPicString = [fullPicString response];
                
                % Check to see if we've received the EOF delimeter. It
                % should be noted that when using 'fscanf(' it is not
                % possible to detect a newline character as a delimeter
                if length(fullPicString) > 10
                    if strcmp(fullPicString(end-9:end-1),'ENDOFFILE')
                        passFailFlag = 1;
                    end
                end
            case 'R' % RAPPELLING COMMAND
                
                response = fscanf(gsSerialBuffer,'%s'); % Get the response string
                fprintf('%.2f s: %s\n',time_elapsed,response);
                
                fprintf(rappelDataFID,'%.2f \t %s\n',time_elapsed,response);
                
                % See if we got the 'Pass' response
                if ~isempty(response) && strcmp(response,'$R0P')
                    passFailFlag = 1;
                elseif strcmp(response,'$R0F') % A 'Failure' response
                    passFailFlag = 0;
                    break
                else
%                     disp(response)
                end
                
            case 'S' % STATUS REQUEST
                % For now this functionality is not yet implemented on the
                % MR or CR so just output simulated responses -- 1/19/15
                response = char(fread(gsSerialBuffer,gsSerialBuffer.BytesAvailable,'char')');
                if strcmp(response,sprintf('$SP\n'))
                    CR_status{1,1} = sprintf('$SCB014795\n'); % CR Battery in mV
                    CR_status{2,1} = sprintf('$SCP3620021\n'); % CR Depth and Distance in cm
                    MR_status{1,1} = sprintf('$SMB014622\n'); % MR Battery in mV
                    passFailFlag = 1;
                else
                    passFailFlag = 0;
                end
            otherwise
                pause(0.25); % allow buffer to fill(should be more than enough)
                response = fscanf(gsSerialBuffer,'%s'); % Get the response string
                % Make sure we got back the appropriate response
                if response(1) == '$' && response(2) == commandType && response(3) == 'P'
                    passFailFlag = 1;
                end
        end % end of switch commandType
    end % end of checking if bytes are available on serial object
    
    time_elapsed = toc; % For timeout purposes
    
end % end of while ~passFailFlag

% Write the fullPicString to the picString.txt file =======================
if commandType == 'I' && passFailFlag == 1
for ii = 1:10
    if strcmp(fullPicString(ii),'I') && strcmp(fullPicString(ii-1),'$')
        break
    end
end
startInd = ii + 1;
numChars = 0;
for ii = length(fullPicString)-12:-1:length(fullPicString)-50
    if strcmp(fullPicString(ii:ii+12),'NUMCHARACTERS')
        for jj = (ii+13):ii+30
            if strcmp(fullPicString(jj),'E')
                numChars = str2double(fullPicString(ii+13:jj-1));
                break
            end
        end
        break
    end
end
% endInd = startInd+numChars-1;
endInd = ii - 1;
fprintf('Got %d out of expected %d characters\n',endInd-startInd+1,numChars);
if strcmp(fullPicString(endInd+1:endInd+3),'NUM') && (endInd-startInd+1) == numChars
    picStringFile = fopen('ImageFiles\picString.txt','w+');
    fprintf(picStringFile,fullPicString(startInd:endInd)); % Don't include the '$I' at
    fclose(picStringFile);                                 % the beginning or the
else                                                       % 'ENDOFFILE' at the end
    passFailFlag = 1;
    str = sprintf('ERROR: Failed to receive expected number of characters! Got %d out of expected %d',endInd-startInd,numChars);
    waitfor(errordlg(str,'Error in image string received!'));
end

end % end of if commandType == 'I'

if commandType == 'R'
    fclose(rappelDataFID);
elseif commandType == 'D'
    fclose(driveDataFID);
end

