
%% Get pixel locations
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------
Load_Reg_Points_Dir = strcat([MainDir,'/Subroutines/Saved_Reg_Points/']);
Load_or_Click = 'load' ;
filenameStringRegPoints = 'RegPoints_01.mat';
switch Load_or_Click
    case 'click'
        FrameView = 100;
        figure; pcolor(Data_Distort_Corrected(:,:,FrameView)); shading interp; axis equal tight
        colormap((gray));colorbar;  hold on
        clim([10 30]);
        [xi,yi] = getpts;
        x0=10; y0=10; width=1500*1.25; height=1500*1.25; set(gcf,'position',[x0,y0,width,height])
        plot(xi,yi,'rO')

    case 'load'
        cd(Load_Reg_Points_Dir)
        load(filenameStringRegPoints)
end


SaveReg = 0;
if SaveReg == 1
    cd(Load_Reg_Points_Dir)
    filenameStringRegPoints = strcat(['RegPoints_02', '.mat']);
    save(filenameStringRegPoints,'xi','yi')
end

%% map all your points to 3D 
close all; clc; cd(MainDir)

% force ROW vectors (1xN) to match PTM3D's internal transposes
uu = xi(:)';     
vv = yi(:)';     

halfanglecone = 7;         
xAx   = [.62 .67 .73 .875 .925 .975];   % Nx = 6
phiDeg = [-60 0 60];                    % Nphi = 3  

% sanity
Nx   = numel(xAx);
Nphi = numel(phiDeg);
Npts = Nx * Nphi;


% ---- build cone surface coordinates for each (x,phi) ----
Rax = tand(halfanglecone) .* xAx;

% ordering: all x for phi1, then all x for phi2, ...
X   = repmat(xAx, 1, Nphi);            % 1xNpts
R   = repmat(Rax, 1, Nphi);            % 1xNpts
phi = repelem(phiDeg, Nx);             % 1xNpts

Y = R .* sind(phi);
Z = R .* cosd(phi);

% ---- call PTM ----
PTM_3D = PTM3D(X, Y, Z, uu, vv);

%% create analytical cone geometry
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

nx = 640; % # points axial       %put enough points here to avoid NaNs
np = 500; % # points azimuthal

%axial vector for theoretical cone
cone_length = 1.0 ;
xc = linspace((X(1)-.1), cone_length, nx);  % add the length prior to the viewing area

%radius for theoretical cone
rc = xc.*tand(halfanglecone); %starting radius at beginning of viewing area

%azimuthal range for theoretical cone
phic = linspace(-60, 60, np);

[XC,PhiC] = meshgrid(xc,phic);
[Rc,lol] = meshgrid(rc,phic);

ZC = zeros(np, nx);
YC = zeros(np, nx);

for i = 1:np
    for j = 1:nx
        ZC(i,j) = rc(j)*cosd(PhiC(i,j));
        YC(i,j) = rc(j)*sind(PhiC(i,j));
    end    
end 


figure; tiledlayout('flow')
nexttile
surf(Data_Distort_Corrected(:,:,FrameView)); shading interp; view(2)
axis equal tight; title('Image pixel space')

nexttile
surf(XC,YC,ZC); shading interp
hold on; axis equal; view(2)
plot3(X,Y,Z,'or'); title('Analytical model')
x0=10; y0=10; width=350*1.25; height=800*1.25; set(gcf,'position',[x0,y0,width,height])


%% calculate viewing angle
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

%visualize Cone
figure('visible', 'off')
cone_pixel = surf(XC, YC, ZC, 'linestyle', 'none', 'visible', 'off');
axis equal

%save normal vectors from that surface
normals_pixel = cone_pixel.VertexNormals;

%define matricies
[m, n] = size(XC);
dot_products_pixel = zeros(size(XC));
view_ang_pixel = zeros(size(XC));

%position of center of camera lens relative to the nose of the cone

cam_x = 25; %inches (VERIFY THIS - HOW?)
cam_y = 1;                  
cam_z = 27;

%create dot products
for i = 1:n
    for k = 1:m
        nom = [normals_pixel(k, i, 1) normals_pixel(k, i, 2) normals_pixel(k, i, 3)];
        cam_vect = [XC(k, i)-cam_x YC(k,i)-cam_y ZC(k,i)-cam_z];
        dot_products_pixel(k, i) = dot(nom, cam_vect);
        view_ang_pixel(k, i) = 180-acosd(dot_products_pixel(k,i)/norm(cam_vect));
    end
end

figure
imagesc(xc.*2.54,phic,view_ang_pixel)
h=gca; 
get(h,'fontSize') 
set(h,'fontSize',14)
xlabel('x (cm)')
ylabel('\phi (^\circ)')
% xticks([40 45 50 55 60 65 70 75])
% yticks([-90 -75 -60 -45 -30 -15 0 15 30 45 60 75 90])
colorbar
a=colorbar;
% clim([0 90])
ylabel(a,'\theta (^\circ)','FontSize',16)

%% apply PTM
close all;clc; cd(MainDir)
%--------------------------------------------------------------------------

% Do you want to correct for directional emissivity drop off?
DirectionalEmissivityCorrection = 'yes';
NumFrames2Map = total_frames;
clear Tc Uc ep overc imagecords vtemp utemp

Tc = zeros(np,nx,2);
Uc = zeros(np,nx,2);
ep = zeros(np,nx,2);

for k = 1:NumFrames2Map
    Frame2Map = (Data_Distort_Corrected(:,:,k));
    for i = 1:np
        for j = 1:nx
            imagecords = PTM_3D*[XC(i,j);rc(j)*sind(PhiC(i,j));rc(j)*cosd(PhiC(i,j));1];
            utemp = round(imagecords(2)/imagecords(3));
            vtemp = round(imagecords(1)/imagecords(3));

            if utemp < 641 && vtemp < 513 && utemp>0&&vtemp>0
                switch DirectionalEmissivityCorrection
                    case 'yes'
                        % Do the emmisivity correction
                        ep(i,j,k) = 0.91*cosd(view_ang_pixel(i,j))^(0.03/1.35/cosd(view_ang_pixel(i,j)));
                        Uc(i,j,k) = 0.91*29992/(exp(717.89/(Frame2Map(utemp, vtemp)+273.15))-6.1222)+16214+(1-0.91)*29992/(5.277);
                        Tc(i,j,k) = 717.89/log(6.1222+ep(i,j)*29992/(Uc(i,j)-16214-(1-ep(i,j))*29992/(5.277)))-273.15;
                    case 'no'
                        Tc(i,j,k) = Frame2Map(utemp,vtemp);
                end
            else
                Tc(i,j,k) = NaN;
            end
        end
    end
    if mod(k,50)==0
        fprintf('%d of %d\n', k, NumFrames2Map)
    end
end

%Check mapping results
FrameView = 1;

figure; tiledlayout('flow')
    nexttile
        surf(Data_Distort_Corrected(:,:,FrameView)); shading interp; view(2)
        axis equal tight; xlabel('i (pixels)'); ylabel('j (pixels)'); colorbar
    nexttile
        surf(XC,YC,ZC,real(Tc(:,:,FrameView))); shading interp
        axis equal tight
        x0=10; y0=10; width=1000*1.25; height=400*1.25; set(gcf,'position',[x0,y0,width,height]);colorbar

