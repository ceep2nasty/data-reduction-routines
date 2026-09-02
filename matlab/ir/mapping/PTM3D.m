function [PTM_3D] = PTM3D(X,Y,Z,uu,vv)
%Calculates the PTM matrix based on the inputs of real location X,Y,Z and
%image location uu and vv.

N = length(X);

A3D = [X', Y', Z', ones(N,1), zeros(N,4), (-uu.*X)', (-uu.*Y)', (-uu.*Z)';
     zeros(N,4), X', Y', Z', ones(N,1), (-vv.*X)', (-vv.*Y)', (-vv.*Z)'];

F3D = [uu, vv];

P3D = inv(A3D'*A3D)*(A3D'*F3D'); 

PTM_3D = [P3D(1),P3D(2),P3D(3), P3D(4); P3D(5),P3D(6),P3D(7),P3D(8); P3D(9), P3D(10), P3D(11), 1];

end

