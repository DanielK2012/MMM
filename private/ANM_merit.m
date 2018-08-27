function [overlap,correlation,collectivity,rmsd,similarity] = ANM_merit(network0,target,detail)
% function [overlap,correlation,collectivity,rmsd,similarity] = ANM_merit(network0,target,detail)
%
% characterizes the merits of an anisotropic network model for modeling a 
% structural change by computing the overlap of the modes with the change 
%
% References:
% F. Tama, Y.-H. Sanejouand, 2001, Protein Eng. 14: 1-6
% R. Br�schweiler, 1995, J. Chem. Phys. 102: 3396-3403.
%
% Input:
% network0  matrix [n,3] of coordinates of network points (knots) of the 
%           original structure
% target    target structure
% detail    optional parameter, if present, specifies the number of low 
%           frequency modes that should be compared 
%
% Output:
% overlap       vector of overlap of the normal modes with the structural 
%               change (Tama & Sanejouand, 2001, Eq. (2))
%               cumulative overlap        :  sqrt(cumsum(overlap.^2))
%               mode with largest overlap :  [maxovl,modenum]=max(overlap)
% correlation   vector of correlation of the normal modes with the
%               structural change (Tama & Sanejouand, 2001, Eq. (3))
% collectivity  collectivity of the structural change (Tama & Sanejouand,
%               2001, Eq. (4); originally: Br�schweiler, 1995)
% rmsd          r.m.s.d. between the two structures (C_alpha)
%           
% G. Jeschke, 2010


[rmsd,starget]=rmsd_superimpose(network0,target);

% make vector of atomic displacements
diff0=starget-network0;
DelR2=sum(diff0.^2,2);
DelR=sqrt(DelR2);
meanDelR=mean(DelR);
sigDelR=std(DelR);

% compute collectivity of motion
[m,n]=size(network0);
nodes=m;
alpha=1/sum(DelR2);
collectivity=exp(-sum(alpha*DelR2.*log(alpha*DelR2)))/nodes;

% make coordinate vectors
initial=reshape(network0',m*n,1);
final=reshape(starget',m*n,1);
diff=final-initial;
diff=diff/norm(diff);

% make eigenvectors and eigenvalues of anisotropic network model
Hessian=setup_ANM_bonded(network0);
[u,d]=eig(Hessian);
clear Hessian
[m,n]=size(d);
lambda=zeros(1,m);
for k=1:m,
    lambda(k)=d(k,k);
end;
clear d

overlap=zeros(1,m-6); % first six modes are rotation/translation
for k=7:m, % first six modes are rotation/translation
    overlap(k-6)=abs(sum(u(:,k).*diff));
end;
overlap=overlap/sqrt(sum(overlap.^2));

correlation=zeros(1,m-6);
for k=7:m,
    mode=reshape(u(:,k),3,nodes);
    Aij=sqrt(sum((mode').^2,2));
    meanAj=mean(Aij);
    sigAj=std(Aij);
    correlation(k-6)=sum((Aij-meanAj).*(DelR-meanDelR))/(nodes*sigDelR*sigAj);
end;

if nargin>2,
	similarity=zeros(detail,2);
        % make eigenvectors and eigenvalues of anisotropic network model
        Hessian=setup_ANM_bonded(target);
        [ut,d]=eig(Hessian);
        clear Hessian
	clear d
	simmat=zeros(detail);
	for k=1:detail,
	    for kk=1:detail,
	        simmat(k,kk)=sum(u(:,k).*ut(:,kk));
        end;
	end;
	for k=1:detail,
	    [cp,poi]=max(simmat(k,:));
	    similarity(k,1)=poi;
	    similarity(k,2)=cp;
	end;
else
	similarity=[];
end;