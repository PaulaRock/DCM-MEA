function out = spm_shoot_norm(job)
% Spatially normalise and smooth fMRI/PET data to MNI space, using Shoot deformation fields
% FORMAT out = spm_shoot_norm(job)
% job - a structure generated by the configuration file
%   job.template - Shoot template for aligning to MNI space. Aligns to population
%                  average if no template is provided.
%   job.subj(n)  - Subject n
%       subj(n).def    - Shoot deformation field
%       subj(n).images - Images for this subject
%   job.vox      - Voxel sizes for spatially normalised images
%   job.bb       - Bounding box for spatially normalised images
%   job.preserve - How to transform
%                  0 = preserve concentrations
%                  1 = preserve integral (cf "modulation")
%
% Normally, Shoot generates deformations that align with the average-
% shaped template.  This routine includes the option to compose the
% shoot deformations with an affine transform derived from an affine
% registration of the template (the final one generated by Shoot),
% with the TPM data released with SPM.
%
% Note that trilinear interpolation is used, and no masking is done.  It
% is therefore essential that the images are realigned and resliced
% before they are spatially normalised.  Alternatively, contrast images
% generated from unsmoothed native-space fMRI/PET data can be spatially
% normalised for a 2nd level analysis.
%
% Two "preserve" options are provided.  One of them should do the
% equavalent of generating smoothed "modulated" spatially normalised
% images.  The other does the equivalent of smoothing the modulated
% normalised fMRI/PET, and dividing by the smoothed Jacobian determinants.
%
%__________________________________________________________________________
% Copyright (C) 2009 Wellcome Trust Centre for Neuroimaging

% John Ashburner
% $Id: spm_shoot_norm.m 7460 2018-10-29 15:55:12Z john $

% Hard coded stuff, that should maybe be customisable
tpm  = fullfile(spm('Dir'),'tpm','TPM.nii');
Mmni = spm_get_space(tpm);

% Shoot template
if ~isempty(job.template{1})
    Nt     = nifti(job.template{1});
    do_aff = true;
else
    Nt     = nifti(tpm);
    do_aff = false;
end

% Deal with desired bounding box and voxel sizes.
%--------------------------------------------------------------------------
bb   = job.bb;
vox  = job.vox;
Mt   = Nt.mat;
dimt = size(Nt.dat);

if any(isfinite(bb(:))) || any(isfinite(vox))
    [bb0,vox0] = spm_get_bbox(Nt, 'old');
    
    msk = ~isfinite(vox); vox(msk) = vox0(msk);
    msk = ~isfinite(bb);   bb(msk) =  bb0(msk);

    bb  = sort(bb);
    vox = abs(vox);

    % Adjust bounding box slightly - so it rounds to closest voxel.
    bb(:,1) = round(bb(:,1)/vox(1))*vox(1);
    bb(:,2) = round(bb(:,2)/vox(2))*vox(2);
    bb(:,3) = round(bb(:,3)/vox(3))*vox(3);
    dim = round(diff(bb)./vox+1);
    of  = -vox.*(round(-bb(1,:)./vox)+1);
    mat = [vox(1) 0 0 of(1) ; 0 vox(2) 0 of(2) ; 0 0 vox(3) of(3) ; 0 0 0 1];
    if det(Mt(1:3,1:3)) < 0
        mat = mat*[-1 0 0 dim(1)+1; 0 1 0 0; 0 0 1 0; 0 0 0 1];
    end
else
    dim = dimt(1:3);
    mat = Mt;
end

if isfield(job.data,'subj') || isfield(job.data,'subjs')
    if do_aff
        [pth,nam,ext] = fileparts(Nt.dat.fname); %#ok
        if exist(fullfile(pth,[nam '_2mni.mat']),'file')
            load(fullfile(pth,[nam '_2mni.mat']),'mni');
        else
            % Affine registration of Shoot Template with MNI space.
            %--------------------------------------------------------------
            fprintf('** Affine registering "%s" with MNI space **\n', nam);
            clear mni
            mni.affine = Mmni/spm_klaff(Nt,tpm,1);
            mni.code   = 'MNI152';
            save(fullfile(pth,[nam '_2mni.mat']),'mni', spm_get_defaults('mat.format'));
        end
        M = mat\mni.affine/Mt;
        mat_intent = mni.code;
    else
        M = mat\eye(4);
        mat_intent = 'Aligned';
    end
    fprintf('\n');

    if isfield(job.data,'subjs')
        % Re-order data
        %------------------------------------------------------------------
        subjs = job.data.subjs;
        subj  = struct('deformation',cell(numel(subjs.deformations),1),...
                       'images',   cell(numel(subjs.deformations),1));
        for i=1:numel(subj)
            subj(i).deformation = {subjs.deformations{i}};
            subj(i).images   = cell(numel(subjs.images),1);
            for j=1:numel(subjs.images)
                subj(i).images{j} = subjs.images{j}{i};
            end
        end
    else
        subj = job.data.subj;
    end

    % Loop over subjects
    %----------------------------------------------------------------------
    out = cell(1,numel(subj));
    for i=1:numel(subj)
        % Spatially normalise data from this subject
        [pth,nam,ext] = fileparts(subj(i).deformation{1}); %#ok
        fprintf('** "%s" **\n', nam);
        out{i} = deal_with_subject(subj(i).deformation,subj(i).images, mat,dim,M,job.preserve,job.fwhm,mat_intent);
    end

    if isfield(job.data,'subjs')
        out1 = out;
        out  = cell(numel(subj),numel(subjs.images));
        for i=1:numel(subj)
            for j=1:numel(subjs.images)
                out{i,j} = out1{i}{j};
            end
        end
    end
end
%__________________________________________________________________________

%__________________________________________________________________________
function out = deal_with_subject(Py,PI,mat,dim,M,jactransf,fwhm,mat_intent)
% Py         - Filename of shoot deformation.
% PI         - Filenames of images to spatially normalise.
% mat        - Voxel-to-world matrix for header of warped images.
% dim        - Dimensions of warped images.
% M          - Matrix for adjusting the deformation fields (eg when using
%              different bounding boxes or origins, or when an additional
%              affine transform is included.
% jactransf  - Whether or not to "modulate".
% fwhm       - FWHM for smoothing.
% mat_intent - Something for the header to indicate average space or MNI
%              space.
% 
% Generate deformation, which is the inverse of the usual one (it is for "pushing"
% rather than the usual "pulling"). This deformation is affine transformed to
% allow for different voxel sizes and bounding boxes, and also to incorporate
% the affine mapping between MNI space and the population average shape.
%--------------------------------------------------------------------------
NY  = nifti(Py{1});
M   = M*NY.mat;
y   = single(squeeze(NY.dat(:,:,:,:,:)));
d   = size(y);

if norm(M-eye(4))>1e-3 || any(d(1:3) ~= dim(1:3))
    y0  = zeros([dim(1:3),3],'single');
    for d=1:3
        yd = y(:,:,:,d);
        for x3=1:dim(3)
            y0(:,:,x3,d) = single(spm_slice_vol(yd,M\spm_matrix([0 0 x3]),dim(1:2),[1 NaN]));
        end
    end
else
    y0 = y;
end

odm = zeros(1,3);
oM  = zeros(4,4);
out = cell(1,numel(PI));
for m=1:numel(PI)

    % Generate headers etc for output images
    %----------------------------------------------------------------------
    [pth,nam,ext,num] = spm_fileparts(PI{m}); %#ok
    NI = nifti(fullfile(pth,[nam ext]));
    NO = NI;
    if jactransf
        if fwhm==0
            NO.dat.fname=fullfile(pth,['mw' nam ext]);
        else
            NO.dat.fname=fullfile(pth,['smw' nam ext]);
        end
        NO.dat.scl_slope = 1.0;
        NO.dat.scl_inter = 0.0;
        NO.dat.dtype     = 'float32-le';
    else
        if fwhm==0
            NO.dat.fname=fullfile(pth,['w' nam ext]);
        else
            NO.dat.fname=fullfile(pth,['sw' nam ext]);
        end
    end
    NO.dat.dim = [dim NI.dat.dim(4:end)];
    NO.mat  = mat;
    NO.mat0 = mat;
    NO.mat_intent  = mat_intent;
    NO.mat0_intent = mat_intent;

    if strcmp(mat_intent,'Aligned'), to_what = 'Average';  else
                                     to_what = mat_intent; end
    if fwhm==0
        NO.descrip = ['Shoot-normed (' to_what ')'];
    else
        NO.descrip = sprintf('Smoothed (%g) Shoot normed (%s)',fwhm, to_what);
    end
    out{m} = NO.dat.fname;
    NO.extras = [];
    create(NO);


    % Smoothing settings
    vx  = sqrt(sum(mat(1:3,1:3).^2));
    krn = max(fwhm./vx,0.1);

    % Loop over volumes within the file
    %----------------------------------------------------------------------
    fprintf('%s',nam); drawnow;
    for j=1:size(NI.dat,4)

        % Check if it is an "imported" image to normalise
        if sum(sum((NI.mat - NY.mat ).^2)) < 0.0001 && ...
           sum(sum((NI.mat - NI.mat0).^2)) > 0.0001
            % No affine transform necessary
            M0 = NI.mat0;
        else
            % Need to resample the mapping by an affine transform
            % so that it maps from voxels in the native space image
            % to voxels in the spatially normalised image.
            %--------------------------------------------------------------
            M0 = NI.mat;
            if ~isempty(NI.extras) && isstruct(NI.extras) && isfield(NI.extras,'mat')
                M1 = NI.extras.mat;
                if size(M1,3) >= j && sum(sum(M1(:,:,j).^2)) ~=0
                    M0 = M1(:,:,j);
                end
            end
        end
        M   = inv(M0);
        dm  = [size(NI.dat),1,1,1,1];
        if ~all(dm(1:3)==odm) || ~all(M(:)==oM(:))
            % Generate new deformation (if needed)
            y   = zeros(size(y0),'single');
            y(:,:,:,1) = M(1,1)*y0(:,:,:,1) + M(1,2)*y0(:,:,:,2) + M(1,3)*y0(:,:,:,3) + M(1,4);
            y(:,:,:,2) = M(2,1)*y0(:,:,:,1) + M(2,2)*y0(:,:,:,2) + M(2,3)*y0(:,:,:,3) + M(2,4);
            y(:,:,:,3) = M(3,1)*y0(:,:,:,1) + M(3,2)*y0(:,:,:,2) + M(3,3)*y0(:,:,:,3) + M(3,4);

            % Generate Jacobian determinants.
            c          = spm_diffeo('jacdet',y)*abs(det(NI.mat(1:3,1:3))/det(NO.mat(1:3,1:3)));
            c(:,:,[1 end]) = NaN; % Boundary voxels are not handled well - so remove
            c(:,[1 end],:) = NaN;
            c([1 end],:,:) = NaN;
        end
        odm = dm(1:3);
        oM  = M;

        % Write the warped data for this time point.
        %------------------------------------------------------------------
        for k=1:size(NI.dat,5)
            for l=1:size(NI.dat,6)
                f  = single(NI.dat(:,:,:,j,k,l));
                if ~jactransf
                    % Unmodulated 
                    f = spm_diffeo('pull',f,y).*c;
                    if fwhm>0
                        spm_smooth(f,f,krn); % Side effects
                        cs = zeros(size(c),'like',c);
                        spm_smooth(c,cs,krn); % Side effects
                        f  = f./max(cs,0.000001);
                    else
                        f  = f./max(c ,0.000001);
                    end
                else
                    % Modulated, by pushing
                    f = spm_diffeo('pull',f,y).*c;
                    spm_smooth(f,f,krn); % Side effects
                end
                NO.dat(:,:,:,j,k,l) = f;
                fprintf('\t%d,%d,%d', j,k,l); drawnow;
            end
        end
    end
    fprintf('\n'); drawnow;
end
%__________________________________________________________________________

