function [Indicator] = SaveFigure(WishtoSave,str_folder,str_filename,FolderPathSave,MainDir,Format)

if WishtoSave == 1
    cd(FolderPathSave)
    
    if ~isfolder(str_folder)
        mkdir(str_folder)
    end
    cd(str_folder)

    % Default format is 'png'
    if nargin < 6 || isempty(Format)
        Format = 'png';
    end

    switch lower(Format)
        case 'jpeg'
            print(gcf, strcat(str_filename,'.jpeg'), '-djpeg', '-r300');
        case 'png'
            print(gcf, strcat(str_filename,'.png'), '-dpng', '-r300');
        case 'eps'
            % set(gca, 'Layer','top','XGrid','on','YGrid','on','GridColor',[0.5 0.5 0.5],'GridAlpha',0.3,'GridLineStyle',':');
            % set(gcf, 'InvertHardcopy','off');
            print(gcf, strcat(str_filename,'.eps'), '-depsc', '-r300');
        case 'fig'
            savefig(gcf, strcat(str_filename,'.fig'));
        otherwise
            warning('Unsupported format. Saving as JPEG by default.');
            print(gcf, strcat(str_filename,'.jpeg'), '-djpeg', '-r300');
    end

    Indicator = 1;
    disp(['Figure saved as ', upper(Format)]);
else
    Indicator = 1;
    disp('Figure not saved');
end

cd(MainDir)
end