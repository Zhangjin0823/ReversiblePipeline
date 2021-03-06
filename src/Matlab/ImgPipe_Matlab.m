%==============================================================
% Image Processing Pipeline
% 
% This is a Matlab implementation of a pre-learned image 
% processing model. A description of the model can be found in
% "A New In-Camera Imaging Model for Color Computer Vision 
% and its Application" by Seon Joo Kim, Hai Ting Lin, 
% Michael Brown, et al. Code for learning a new model can 
% be found at the original project page. This particular 
% implementation was written by Mark Buckler.
%
% Original Project Page:
% http://www.comp.nus.edu.sg/~brown/radiometric_calibration/
%
% Model Format Readme:
% http://www.comp.nus.edu.sg/~brown/radiometric_calibration/datasets/Model_param/readme.pdf
% 
%==============================================================

function ImgPipe_Matlab
    % Model directory
    model_dir      = '../../camera_models/NikonD7000/';

    % White balance index (select from the transform file)
    % First white balance in file has wb_index of 1
    % For more information see the model readme
    wb_index       = 6;
    
    % Image directory
    image_dir      = '../../imgs/NikonD7000FL/';
    
    % Results directory
    results_dir    = 'pipe_results/';
    
    % Raw image
    raw_image_name = 'DSC_0916.NEF.raw_1C.tiff';
    
    % Jpg image
    jpg_image_name = 'DSC_0916.JPG';
    
    % Create directories for results
    mkdir(pwd, results_dir);
    mkdir(pwd, strcat(results_dir,'forward_images/'));
    mkdir(pwd, strcat(results_dir,'backward_images/'));
    
    % Patch start locations
    %   [xstart,ystart]
    %
    % NOTE: Must align patch start in raw file with the demosiac 
    % pattern start. Otherwise colors will be switched in the 
    % final result.
    patchstarts = [ ...
        [551,  2751]; ... % 1
        [1001, 2751]; ... % 2
        [1501, 2751]; ... % 3
        [2001, 2751]; ... % 4
        [551,  2251]; ... % 5
        [1001, 2251]; ... % 6
        [1501, 2251]; ... % 7
        [2001, 2251]; ... % 8
        [551,  1751]; ... % 9
        [1001, 1751]; ... % 10
        [1501, 1751]; ... % 11
        [2001, 1751]; ... % 12
    ];
    
    % Number of patch tests to run
    patchnum = 12;

    % Define patch size (patch width and height in pixels
    patchsize = 10;
    
    % Initialize results
    forward_results  = zeros(patchnum,3,3);
    backward_results = zeros(patchnum,3,3);

    % Process patches
    for i=1:patchnum

        % Run the forward model on the patch
        [demosaiced, transformed, gamutmapped, tonemapped, forward_ref] = ...
            ForwardPipe(model_dir, image_dir, results_dir, wb_index, ...
            raw_image_name, jpg_image_name, ... 
            patchstarts(i,2), patchstarts(i,1), patchsize, i);
        
        % Compare the pipeline output to the reference
        [refavg, resultavg, error] = ...
            patch_compare(tonemapped, forward_ref);
        forward_results(i,1,:) = resultavg;
        forward_results(i,2,:) = refavg;
        forward_results(i,3,:) = error;
        
        % Run the backward model on the patch
        [revtonemapped, revgamutmapped, revtransformed, remosaiced, backward_ref] = ...
            BackwardPipe(model_dir, image_dir, results_dir, wb_index, ...
            jpg_image_name, raw_image_name, ... 
            patchstarts(i,2), patchstarts(i,1), patchsize, i);
        
        % Compare the pipeline output to the reference
        [refavg, resultavg, error] = ...
            patch_compare(remosaiced, backward_ref);
        backward_results(i,1,:) = resultavg;
        backward_results(i,2,:) = refavg;
        backward_results(i,3,:) = error;
    
    end
    
    write_results(forward_results,  patchnum, ...
        strcat(results_dir,'forward_results.txt'));
    write_results(backward_results, patchnum, ...
        strcat(results_dir,'backward_results.txt'));
    
    disp(strcat('Avg % color channel error for forward:  ', ...
        num2str(mean(mean(abs(forward_results(:,3,:)))))));
    disp(strcat('Avg % color channel error for backward: ', ...
        num2str(mean(mean(abs(backward_results(:,3,:)))))));

    disp(strcat('Max % color channel error for forward:  ', ...
        num2str(max(max(abs(forward_results(:,3,:)))))));
    disp(strcat('Max % color channel error for backward: ', ...
        num2str(max(max(abs(backward_results(:,3,:)))))));

    disp('See results folder for error per patch and per color channel');
    
end


function [demosaiced, transformed, gamutmapped, tonemapped, ref_image] = ...
    ForwardPipe(model_dir, image_dir, results_dir, wb_index, ...
    in_image_name, ref_image_name, ystart, xstart, patchsize, patchid)

    % Establish patch
    xend = xstart + patchsize - 1;
    yend = ystart + patchsize - 1;

    %==============================================================
    % Import Forward Model Data
    %
    % Note: This assumes a camera model folder with a single 
    % camera setting and transform. This is not the case for 
    % every folder, but it is for the Nikon D40 on the Normal
    % setting and with Fl(L14)/florescent color.

    % Model file reading
    transforms_file  = dlmread( ...
        strcat(model_dir,'raw2jpg_transform.txt'));
    ctrl_points_file = dlmread( ...
        strcat(model_dir,'raw2jpg_ctrlPoints.txt'));
    coeficients_file = dlmread( ...
        strcat(model_dir,'raw2jpg_coefs.txt'));
    resp_funct_file  = dlmread( ...
        strcat(model_dir,'raw2jpg_respFcns.txt'));

    % Color space transform
    Ts             = transforms_file(2:4,:);

    % Calculate base for the white balance transform selected
    % For more details see the camera model readme
    wb_base        = 6 + 5*(wb_index-1);
    
    % White balance transform
    Tw             = diag(transforms_file(wb_base+3,:));

    % Combined transforms
    TsTw           = Ts*Tw;
    TsTw_file      = transforms_file(wb_base:wb_base+2,:);

    % Perform quick check to determine equivalence with provided model
    % Round to nearest 4 decimal representation for check
    TsTw_4dec      = round(TsTw*10000)/10000;
    TsTw_file_4dec = round(TsTw_file*10000)/10000;
    assert( isequal( TsTw_4dec, TsTw_file_4dec), ...
        'Transform multiplication not equal to result found in model file, or import failed' ) 

    % Gamut mapping: Control points
    ctrl_points    = ctrl_points_file(2:end,:);

    % Gamut mapping: Weights
    weights        = coeficients_file(2:(size(coeficients_file,1)-4),:);

    % Gamut mapping: c
    c              = coeficients_file((size(coeficients_file,1)-3):end,:);

    % Tone mapping (reverse function is what is contained within model
    % file)
    frev           = resp_funct_file(2:end,:);

    %==============================================================
    % Import Raw Image Data

    % NOTE: Can use RAW2TIFF.cpp to convert raw to tiff. This isn't
    % automatically called by this script yet, but could be.

    in_image         = imread(strcat(image_dir,in_image_name));
    
    %==============================================================
    % Import Reference image
    
    ref_image        = imread(strcat(image_dir,ref_image_name));
    
    % Downsize to match patch size
    ref_image        = ref_image(ystart:yend,xstart:xend,:);
    
    %==============================================================
    % Forward pipeline function

    % Convert to uint16 representation for demosaicing
    in_image_unit16  = im2uint16(in_image);
    
    % Demosaic image
    demosaiced       = im2uint8(demosaic(in_image_unit16,'rggb'));%gbrg %rggb 
    
    % Convert to double precision for transforming and gamut mapping
    image_float      = im2double(demosaiced);
    
    % Downsize image to patch size
    demosaiced       = demosaiced(ystart:yend,xstart:xend,:);
    image_float      = image_float(ystart:yend,xstart:xend,:);

    % Pre-allocate memory
    height           = size(image_float,1);
    width            = size(image_float,2);
    transformed      = zeros(height,width,3);
    gamutmapped      = zeros(height,width,3);
    tonemapped       = zeros(height,width,3);
    
    
    for y = 1:height
        for x = 1:width 
            
            % transformed = RAWdemosaiced * Ts * Tw
            transformed(y,x,:) = transpose(squeeze(image_float(y,x,:))) ...
                * transpose(TsTw);

            % gamut mapping
            gamutmapped(y,x,:) = RBF(squeeze(transformed(y,x,:)), ...
                ctrl_points, weights, c);
            
            % tone mapping
            tonemapped(y,x,:)  = tonemap(im2uint8(squeeze(gamutmapped(y,x,:))), frev);
            
        end
        % Let user know how far along we are
        disp((y/size(image_float,1))*100)
    end
    
    %==============================================================
    % Export Image(s)
    
    ref_image   = im2uint8(ref_image);
    image_float = im2uint8(image_float);
    transformed = im2uint8(transformed);
    gamutmapped = im2uint8(gamutmapped);
    tonemapped  = im2uint8(tonemapped);
    
    imwrite(ref_image,  strcat(results_dir, ...
        'forward_images/', in_image_name, ... 
        '.p',int2str(patchid),'.forward_reference.tif'));
    imwrite(tonemapped,  strcat(results_dir, ...
        'forward_images/', in_image_name, ... 
        '.p',int2str(patchid),'.forward_result.tif'));
    
    
end 

function [revtonemapped, revgamutmapped, revtransformed, remosaiced, ref_image_colored] = ...
    BackwardPipe(model_dir, image_dir, results_dir, wb_index, ...
    in_image_name, ref_image_name, ystart, xstart, patchsize, patchid)

    % Establish patch
    xend = xstart + patchsize - 1;
    yend = ystart + patchsize - 1;

    %==============================================================
    % Import Backward Model Data
    %
    % Note: This assumes a camera model folder with a single 
    % camera setting and transform. This is not the case for 
    % every folder, but it is for the Nikon D40 on the Normal
    % setting and with Fl(L14)/florescent color.

    % Model file reading
    % Model file reading
    transforms_file  = dlmread( ...
        strcat(model_dir,'jpg2raw_transform.txt'));
    ctrl_points_file = dlmread( ...
        strcat(model_dir,'jpg2raw_ctrlPoints.txt'));
    coeficients_file = dlmread( ...
        strcat(model_dir,'jpg2raw_coefs.txt'));
    resp_funct_file  = dlmread( ...
        strcat(model_dir,'jpg2raw_respFcns.txt'));

    % Color space transform
    Ts             = transforms_file(2:4,:);

    % Calculate base for the white balance transform selected
    % For more details see the camera model readme
    wb_base        = 6 + 5*(wb_index-1);
    
    % White balance transform
    Tw             = diag(transforms_file(wb_base+3,:));

    % Combined transforms
    TsTw           = Ts*Tw;
    TsTw_file      = transforms_file(wb_base:wb_base+2,:);

    % Perform quick check to determine equivalence with provided model
    % Round to nearest 4 decimal representation for check
    TsTw_4dec      = round(TsTw*10000)/10000;
    TsTw_file_4dec = round(TsTw_file*10000)/10000;
    assert( isequal( TsTw_4dec, TsTw_file_4dec), ...
        'Transform multiplication not equal to result found in model file, or import failed' ) 

    % Gamut mapping: Control points
    ctrl_points    = ctrl_points_file(2:end,:);

    % Gamut mapping: Weights
    weights        = coeficients_file(2:(size(coeficients_file,1)-4),:);

    % Gamut mapping: c
    c              = coeficients_file((size(coeficients_file,1)-3):end,:);

    % Tone mapping (reverse function is what is contained within model
    % file)
    frev           = resp_funct_file(2:end,:);

    %==============================================================
    % Import Image Data

    in_image         = imread(strcat(image_dir,in_image_name));
    ref_image        = imread(strcat(image_dir,ref_image_name));
    
    % Convert the input image to double represenation
    ref_image        = im2double(ref_image);
    
    %==============================================================
    % Backward pipeline function
 
    % Convert to double precision for processing
    image_float      = im2double(in_image);
    
    % Extract patches
    image_float      = image_float(ystart:yend,xstart:xend,:);
    ref_image        = ref_image  (ystart:yend,xstart:xend);

    % Pre-allocate memory
    height           = size(image_float,1);
    width            = size(image_float,2);
    revtransformed      = zeros(height,width,3);
    revtonemapped       = zeros(height,width,3);
    revgamutmapped      = zeros(height,width,3);
    remosaiced          = zeros(height,width,3);
    ref_image_colored   = zeros(height,width,3);
    
    for y = 1:height
        for x = 1:width 
            
            % Reverse tone mapping
            revtonemapped(y,x,:)  = revtonemap(squeeze(image_float(y,x,:)), frev);
            
            % Reverse gamut mapping
            revgamutmapped(y,x,:) = RBF(squeeze(revtonemapped(y,x,:)), ...
                ctrl_points, weights, c);
            
            % Reverse color mapping and white balancing
            % RAWdemosaiced = transformed * inv(TsTw) = transformed / TsTw
            revtransformed(y,x,:) = transpose(squeeze(revgamutmapped(y,x,:))) ...
                * inv(transpose(TsTw));
            
            % Re-mosaicing
            % Note: This is not currently parameterizable, assumes rggb
            yodd = mod(y,2);
            xodd = mod(x,2);
            % If a red pixel
            if yodd && xodd
                remosaiced(y,x,:) = [revtransformed(y,x,1), 0, 0];
            % If a green pixel
            elseif xor(yodd,xodd)
                remosaiced(y,x,:) = [0, revtransformed(y,x,2), 0];
            % If a blue pixel
            elseif ~yodd && ~xodd
                remosaiced(y,x,:) = [0, 0, revtransformed(y,x,3)];
            end
            
            %======================================================
            % Reorganize reference image
            % Note: This is not currently parameterizable, assumes rggb
            % If a red pixel
            if yodd && xodd
                ref_image_colored(y,x,:) = [ref_image(y,x), 0, 0];
            % If a green pixel
            elseif xor(yodd,xodd)
                ref_image_colored(y,x,:) = [0, ref_image(y,x), 0];
            % If a blue pixel
            elseif ~yodd && ~xodd
                ref_image_colored(y,x,:) = [0, 0, ref_image(y,x)];
            end
            
        end
        % Let user know how far along we are
        disp((y/size(image_float,1))*100)
    end
    
    
    %==============================================================
    % Export Image(s)
      
    ref_image         = im2uint8(ref_image);
    ref_image_colored = im2uint8(ref_image_colored);
    revtransformed    = im2uint8(revtransformed);
    revtonemapped     = im2uint8(revtonemapped);
    revgamutmapped    = im2uint8(revgamutmapped);
    remosaiced        = im2uint8(remosaiced);

    imwrite(ref_image,  strcat(results_dir, ...
        'backward_images/', in_image_name, ...
        '.p',int2str(patchid),'.back_ref.tif'));
    imwrite(ref_image_colored,  strcat(results_dir, ...
        'backward_images/', in_image_name, ... 
        '.p',int2str(patchid),'.back_ref_colored.tif'));
    imwrite(remosaiced,  strcat(results_dir, ...
        'backward_images/', in_image_name, ...
        '.p',int2str(patchid),'.back_result.tif'));
    
   
end


% Radial basis function for forward and reverse gamut mapping
function out = RBF (in, ctrl_points, weights, c)

    out      = zeros(3,1);

    % Weighted control points
    for idx = 1:size(ctrl_points,1)
        dist = norm(transpose(in) - ctrl_points(idx,:));
        for color = 1:3
            out(color)  = out(color) + weights(idx,color) * dist;
        end
    end

    % Biases
    for color = 1:3
        out(color) = out(color) +  c(1,color);
        out(color) = out(color) + (c(2,color) * in(1));
        out(color) = out(color) + (c(3,color) * in(2));
        out(color) = out(color) + (c(4,color) * in(3));
    end
    
end

% Forward mapping function
function out = tonemap (in, revf)

    out = zeros(3,1);

    for color = 1:3 % 1-R, 2-G, 3-B
        % Find index of value which is closest to the input
        [~,idx] = min(abs(revf(:,color)-im2double(in(color))));
        
        % If index is zero, bump up to 1 to prevent 0 indexing in Matlab
        if idx == 0
           idx = 1; 
        end
        
        % Convert the index to float representation of image value
        out(color) = idx/256;
    end

end

% Reverse tone mapping function
function out = revtonemap (in, revf)

    out = zeros(3,1);

    for color = 1:3 % 1-R, 2-G, 3-B
        % Convert the input to an integer between 1 and 256
        idx = round(in(color)*256);
        
        % If index is zero, bump up to 1 to prevent 0 indexing in Matlab
        if idx == 0
           idx = 1; 
        end
        
        % Index the reverse tone mapping function
        out(color) = revf(idx,color);        
    end

end

% Patch color analysis and comparison function
function [refavg, resultavg, error] = patch_compare(resultpatch, referencepatch)

    refavg    = zeros(3,1);
    resultavg = zeros(3,1);
    error     = zeros(3,1);
    
    for color = 1:3 % 1-R, 2-G, 3-B
        % Take two dimensional pixel averages
        refavg(color)    = mean(mean(referencepatch(:,:,color)));
        resultavg(color) = mean(mean(resultpatch(:,:,color)));
        % Compute error
        diff             = resultavg(color)-refavg(color);
        error(color)     = (diff/256.0)*100;
    end

end

% Write the pipeline data results to an output file
function write_results(results, patchnum, file_name)

    outfileID = fopen(file_name, 'w');
    
    % Display results
    fprintf(outfileID, 'res(red), res(green), res(blue)\n');
    fprintf(outfileID, 'ref(red), ref(green), ref(blue)\n');
    fprintf(outfileID, 'err(red), err(green), err(blue)\n');
    fprintf(outfileID, '\n');
    for i=1:patchnum
       fprintf(outfileID, 'Patch %d: \n', i);
       % Print results
       fprintf(outfileID, '%4.2f, %4.2f, %4.2f \n', ... 
           results(i,1,1), results(i,1,2), results(i,1,3));
       % Print reference
       fprintf(outfileID, '%4.2f, %4.2f, %4.2f \n', ... 
           results(i,2,1), results(i,2,2), results(i,2,3));
       % Print error
       fprintf(outfileID, '%4.2f, %4.2f, %4.2f \n', ... 
           results(i,3,1), results(i,3,2), results(i,3,3));
       fprintf(outfileID, '\n');
    end
    
end