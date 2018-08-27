function [message,info]=wr_pdb_paradigm(fname,idCode,modnum,chain,cleaned)
% function wr_pdb_paradigm(fname,idCode,modnum,chain,cleaned)
%
% This function is mainly intended for providing a PDB template file for
% Modeller and the corresponding sequence information
% Writes a PDB file in format V 3.20 of the current structure
% only the 
%   header, (HEADER)
%   title, (TITLE)
%   remarks on format and the originating program (REMARK 4, REMARK 5)
%   sequence information, (SEQRES)
%   sequence modifications, (MODRES)
%   information on nonstandard residues without their names (HET)
%   secondary structure information, this comes from an original PDB
%   structure (if any) or from HELIX, SHEET, LOOP definitions within MMM,
%   sheets are stored only in single-strand format (no registration)
%   definitions within MMM take precedence (HELIX, SHEET)
%   unit cell information (CRYST1), if present in the original file
%   atom coordinates, (ATOM, HETATM)
%   connection information (CONECT)
%   model numbers (MODEL, ENDMDL)
%   master record (MASTER)
% are written
%
% for spin labels, only one paradigmatic rotamer is written which best
% approximates the mean N-O coordinate
%
% fname     file name for output, extension .pdb is appended, if no
%           extension is present
% idCode    four-letter PDB code or pseudo-PDB code
% modnum    optional argument, model (dataset) number for an ensemble
%           structure, if present, only this particular model (dataset) is
%           written, if provided, but empty, first model is used
%           if the requested model does not exist, the whole structure is
%           written
%           if there are several chains, the requested model must exist in
%           all of them (or in none)
% chain     optional argument, chain number for a structure with multiple
%           chains, if present, only this particular chain is written
%           if the requested chain does not exist, no file is written
%           if chain=':' all chains are written
% cleaned   optional flag, if present and true, only residues with complete
%           backbone are written out, furthermore, hetero amino acids are
%           replaced by glycine needed for SCWRL4, in this case SEQRES,
%           MODRES, and HET records are missing
%
% message   error or warning message
% info      information on sequence and residue numbering
%
% Limitations and remarks: 
% - only residues R1A and IA1 are currently recognized as spin labels
% - to obtain a proper info record, only one model from an ensemble must
%   be requested (provide modnum!)
% - residue numbers of cofactors associated with a peptide chain are
%   changed, all these cofactors get consecutive residue numbers starting
%   with the number immediately following the terminating residue, this
%   conforms to Modeller input format (without introducing sequence gaps of
%   several hundred residues)
% - cofactors are encoded as rigid-body (BLK) residues in the sequence
%   (single-letter code '.')
%
% G. Jeschke, 2009-11

global model
global chemistry
global residue_defs

if nargin<5,
    cleaned=false;
end;

if nargin>=3,
    if isempty(modnum),
        modnum=1;
    end;
else
    modnum=1;
end;

message.error=0;
message.text='';

% initialize checksum values

numRemark=0; % number of REMARK records
numHet=0; % number of HET records
numHelix=0; % number of HELIX records
numSheet=0; % number of SHEET records
numTurn=0;
numSite=0;
numXform=0;
numCoord=0;
numTer=0;
numConect=0;
numSeq=0;


% append proper extension, if extension is missing
if isempty(strfind(fname,'.')), fname=strcat(fname,'.pdb'); end;

snum=model.current_structure;

% generate header line
header=sprintf('HEADER    %s',model.info{snum}.class);
header=fillstr(header,50);
today=date;
today=[today(1:7) today(10:11)];
header=sprintf('%s%s   %s',header,today,idCode);
% state supported format and originating program
format=sprintf('REMARK   4 %s COMPLIES WITH FORMAT V. 3.20, 01-DEC-08',idCode);
numRemark=numRemark+1;
origin=sprintf('REMARK   5 WRITTEN BY MMM (MODIFIED STRUCTURE)');
numRemark=numRemark+1;

fid=fopen(fname,'wt');
if fid==-1,
    message.error=1;
    message.text='File could not be written';
    return;
end;

fprintf(fid,'%s\n',header);
[tl,n]=size(model.info{snum}.title);
for k=1:tl, % loop over all title lines
    if k==1,
        fprintf(fid,'TITLE     %s\n',model.info{snum}.title(k,:));
    else
        fprintf(fid,'TITLE   %2i%s\n',k,model.info{snum}.title(k,:));
    end;
end;
fprintf(fid,'%s\n',format);
fprintf(fid,'%s\n',origin);

chains=length(model.structures{snum}(:));

if nargin>=4 && ~strcmp(chain,':'),
    if chain<=chains && chain>=1,
        cnumbers=chain;
    else
        message.error=2;
        message.text='Chain number does not exist';
        return;
    end;
else
    cnumbers=1:chains;
end;

if ~cleaned,
    % write SEQRES records
    for cnum=cnumbers,
        seqline=0;
        cid=model.structures{snum}(cnum).name;
        restags=model.structures{snum}(cnum).restags;
        poi=0;
        residues=(length(restags)-1)/4;
        while poi<residues,
            seqline=seqline+1;
            tline=sprintf('SEQRES %3i %s %4i ',seqline,cid,residues); % initialize SEQRES line
            field=0;
            while field<13,
                poi=poi+1;
                field=field+1;
                tline=sprintf('%s%4s',tline,restags(4*poi-2:4*poi));
                if poi>=residues, break; end;
            end;
            if length(tline)<70, tline=fillstr(tline,70); end;
            fprintf(fid,'%s\n',tline);
            numSeq=numSeq+1;
        end;
    end;

    % write MODRES records
    for cnum=cnumbers,
        cid=model.structures{snum}(cnum).name;
        if isfield(model.structures{snum}(cnum),'mutations'),
            mutated=length(model.structures{snum}(cnum).mutations);
            for k=1:mutated,
                fprintf(fid,'MODRES %s %s ',idCode,model.structures{snum}(cnum).mutations(k).modified);
                fprintf(fid,'%s %4i  ',cid,model.structures{snum}(cnum).mutations(k).number);
                fprintf(fid,'%s  ',model.structures{snum}(cnum).mutations(k).original);
                if isfield(model.structures{snum}(cnum).mutations(k),'comment'),
                    fprintf(fid,'%s',model.structures{snum}(cnum).mutations(k).comment);
                end;
                fprintf(fid,'\n');
            end;
        end;
    end;

    % write HET records
    for cnum=cnumbers,
        cid=model.structures{snum}(cnum).name;
        if isfield(model.structures{snum}(cnum),'het'),
            hetrecs=length(model.structures{snum}(cnum).het);
            for k=1:hetrecs,
                fprintf(fid,'HET    %3s  %s',model.structures{snum}(cnum).het(k).id,cid);
                fprintf(fid,'%4i   ',model.structures{snum}(cnum).het(k).number);
                fprintf(fid,'%5i   ',model.structures{snum}(cnum).het(k).hetrecs);
                if isfield(model.structures{snum}(cnum).het(k),'descriptor'),
                    fprintf(fid,'%s',model.structures{snum}(cnum).het(k).descriptor);
                end;
                fprintf(fid,'\n');
                numHet=numHet+1;
            end;
        end;
    end;
end;

% write helix records
helices=0;
for cnum=cnumbers,
    cid=model.structures{snum}(cnum).name;
    if isfield(model.structures{snum}(cnum),'helix_defs') % user-defined helix records
        hnum=length(model.structures{snum}(cnum).helix_defs);
        for k=1:hnum,
            helices=helices+1;
            if isfield(model.structures{snum}(cnum).helix_defs{k},'class') % user has defined helix class
                hclass=model.structures{snum}(cnum).helix_defs{k}.class;
            else
                hclass=1; % default alpha-helix
            end;
            htag=model.structures{snum}(cnum).helix_defs{k}.name;
            if length(htag)>3, htag=htag(1:3); end;
            fprintf(fid,'HELIX  %3i %3s ',helices,htag);
            numHelix=numHelix+1;
            start_res=model.structures{snum}(cnum).helix_defs{k}.range(1);
            cr_tag=sprintf('%i',start_res);
            start_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{1}.residue_tags);
            start_name=model.structures{snum}(cnum).residues{1}.info(start_id).name; 
            end_res=model.structures{snum}(cnum).helix_defs{k}.range(2);
            end_id=[];
            while isempty(end_id) && end_res>1,
                cr_tag=sprintf('%i',end_res);
                end_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{1}.residue_tags);
                if isempty(end_id), end_res=end_res-1; end;
            end;
            if ~isempty(end_id),
                end_name=model.structures{snum}(cnum).residues{1}.info(end_id).name; 
                fprintf(fid,'%3s %s %4i  %3s %s %4i ',start_name,cid,start_res,end_name,cid,end_res);
                comment=model.structures{snum}(cnum).helix_defs{k}.name;
                if length(comment)>29, 
                    comment=comment(1:29);
                else
                    comment=fillstr(comment,29);
                end;
                fprintf(fid,'%2i %s %5i\n',hclass,comment,end_res-start_res+1);
            end;
        end;
    elseif model.structures{snum}(cnum).helices>0 % input PDB defined helix records
        hnum=model.structures{snum}(cnum).helices;
        for k=1:hnum,
            helices=helices+1;
            hclass=model.structures{snum}(cnum).helix(k).class;
            htag=model.structures{snum}(cnum).helix(k).name;
            if length(htag)>3, htag=htag(1:3); end;
            fprintf(fid,'HELIX  %3i %3s ',helices,htag);
            numHelix=numHelix+1;
            start_res=model.structures{snum}(cnum).helix(k).start;
            cr_tag=sprintf('%i',start_res);
            start_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{modnum}.residue_tags);
            start_name=model.structures{snum}(cnum).residues{modnum}.info(start_id).name; 
            end_res=model.structures{snum}(cnum).helix(k).end;
            cr_tag=sprintf('%i',end_res);
            end_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{modnum}.residue_tags);
            end_name=model.structures{snum}(cnum).residues{modnum}.info(end_id).name; 
            fprintf(fid,'%3s %s %4i  %3s %s %4i ',start_name,cid,start_res,end_name,cid,end_res);
            comment=sprintf('DEFINITION BY PDB ID %s',model.info{snum}.idCode);
            if length(comment)>29, 
                comment=comment(1:29);
            else
                comment=fillstr(comment,29);
            end;
            fprintf(fid,'%2i %s %5i\n',hclass,comment,end_res-start_res+1);
        end;
    end;
end;

% write sheet (strand) records
strands=0;
for cnum=cnumbers,
    cid=model.structures{snum}(cnum).name;
    if isfield(model.structures{snum}(cnum),'sheet_defs') % user-defined helix records
        shnum=length(model.structures{snum}(cnum).sheet_defs);
        for k=1:shnum,
            strands=strands+1;
            stag=model.structures{snum}(cnum).sheet_defs{k}.name;
            if length(stag)>3, stag=stag(1:3); end;
            fprintf(fid,'SHEET  %3i %3s 1 ',strands,stag);
            numSheet=numSheet+1;
            start_res=model.structures{snum}(cnum).sheet_defs{k}.range(1);
            cr_tag=sprintf('%i',start_res);
            start_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{modnum}.residue_tags);
            start_name=model.structures{snum}(cnum).residues{modnum}.info(start_id).name; 
            end_res=model.structures{snum}(cnum).sheet_defs{k}.range(2);
            cr_tag=sprintf('%i',end_res);
            end_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{modnum}.residue_tags);
            end_name=model.structures{snum}(cnum).residues{modnum}.info(end_id).name; 
            fprintf(fid,'%3s %s%4i  %3s %s%4i  0\n',start_name,cid,start_res,end_name,cid,end_res);
        end;
    elseif model.structures{snum}(cnum).strands>0 % input PDB defined sheet records
        shnum=model.structures{snum}(cnum).strands;
        for k=1:shnum,
            strands=strands+1;
            stag=model.structures{snum}(cnum).strand(k).name;
            if length(stag)>3, stag=stag(1:3); end;
            fprintf(fid,'SHEET  %3i %3s 1 ',strands,stag);
            numSheet=numSheet+1;
            start_res=model.structures{snum}(cnum).strand(k).start;
            cid1=char(model.structures{snum}(cnum).strand(k).s_c);
            cr_tag=sprintf('%i',start_res);
            start_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{modnum}.residue_tags);
            start_name=model.structures{snum}(cnum).residues{modnum}.info(start_id).name; 
            end_res=model.structures{snum}(cnum).strand(k).end;
            cid2=char(model.structures{snum}(cnum).strand(k).e_c);
            cr_tag=sprintf('%i',end_res);
            end_id=tag2id(cr_tag,model.structures{snum}(cnum).residues{modnum}.residue_tags);
            end_name=model.structures{snum}(cnum).residues{modnum}.info(end_id).name; 
            fprintf(fid,'%3s %s%4i  %3s %s%4i  0\n',start_name,cid1,start_res,end_name,cid2,end_res);
        end;
    end;
end;

if ~isempty(model.info{snum}.SSbonds),
    for k=1:length(model.info{snum}.SSbonds),
        bond=model.info{snum}.SSbonds(k);
        fprintf(fid,'SSBOND %3i CYS %s %4i%s   CYS %s %4i%s',k,bond.chainID1,bond.res1,bond.icode1,bond.chainID2,bond.res2,bond.icode2);
        fprintf(fid,'                       %s %s %5.2f\n',bond.symop1,bond.symop2,bond.distance);
    end;
end;

% write CRYST1 record, if unit cell information is present

if isfield(model.info{snum},'cryst'),
    cryst=model.info{snum}.cryst;
    fprintf(fid,'CRYST1%9.3f%9.3f%9.3f%7.2f%7.2f%7.2f %s%4i\n',cryst.a,cryst.b,cryst.c,cryst.alpha,cryst.beta,cryst.gamma,cryst.sGroup,cryst.Z);
    if isfield(model.info{snum}.cryst,'origx1'),
        origx=model.info{snum}.cryst.origx1;
        fprintf(fid,'ORIGX1    %10.6f%10.6f%10.6f     %10.5f\n',origx(1),origx(2),origx(3),origx(4));
    end;
    if isfield(model.info{snum}.cryst,'origx2'),
        origx=model.info{snum}.cryst.origx2;
        fprintf(fid,'ORIGX2    %10.6f%10.6f%10.6f     %10.5f\n',origx(1),origx(2),origx(3),origx(4));
    end;
    if isfield(model.info{snum}.cryst,'origx3'),
        origx=model.info{snum}.cryst.origx3;
        fprintf(fid,'ORIGX3    %10.6f%10.6f%10.6f     %10.5f\n',origx(1),origx(2),origx(3),origx(4));
    end;
    if isfield(model.info{snum}.cryst,'scale1'),
        origx=model.info{snum}.cryst.scale1;
        fprintf(fid,'SCALE1    %10.6f%10.6f%10.6f     %10.5f\n',origx(1),origx(2),origx(3),origx(4));
    end;
    if isfield(model.info{snum}.cryst,'scale2'),
        origx=model.info{snum}.cryst.scale2;
        fprintf(fid,'SCALE2    %10.6f%10.6f%10.6f     %10.5f\n',origx(1),origx(2),origx(3),origx(4));
    end;
    if isfield(model.info{snum}.cryst,'scale3'),
        origx=model.info{snum}.cryst.scale3;
        fprintf(fid,'SCALE3    %10.6f%10.6f%10.6f     %10.5f\n',origx(1),origx(2),origx(3),origx(4));
    end;
end;

% write ATOM and HETATM records

models=length(model.structures{snum}(1).residues);
modvec=1:models;
if nargin>2 && modnum<=models && modnum>=1,
    modvec=modnum;
end;

info.first=0;
info.last=0;
info.first_chain='';
info.last_chain='';
info.seq='';
info.offsets=[];

offsets=zeros(1,100);
offset=0;
curr_chain=0;

started=false;
atoms=0;
for cnum=cnumbers,
    [catoms,n]=size(model.structures{snum}(cnum).xyz{1});
    atoms=atoms+catoms+1;
end;
atom_table=zeros(atoms,3); % preallocate atom number translation table
for mnum=modvec,
    atnum=0; % initialize atom serial number
    if models>1,
        fprintf(fid,'MODEL     %4i\n',mnum);
    end;
    for cnum=cnumbers,
        new_chain=true;
        curr_chain=curr_chain+1;
        cid=model.structures{snum}(cnum).name;
        if cnum==cnumbers(1),
            info.first_chain=cid;
        else
            info.seq=[info.seq '/'];
        end;
        if cnum==cnumbers(end),
            info.last_chain=cid;
        end;
        residues=length(model.structures{snum}(cnum).residues{mnum}.info);
        currnum=0;
        terminated=false;
        for rnum=1:residues,
            rtag=model.structures{snum}(cnum).residues{mnum}.info(rnum).name;
            if strcmpi(rtag,'R1A') || strcmpi(rtag,'IA1'),
                paradigm=true;
                Nid=tag2id('N1',model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_tags);
                Oid=tag2id('O1',model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_tags);
                Nat=model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_numbers{Nid};
                Oat=model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_numbers{Oid};
                [mN,nN]=size(Nat);
                if nN>1,
                    pop=Nat(:,2);
                else
                    pop=1;
                end;
                Ncoor=model.structures{snum}(cnum).xyz{mnum}(Nat(:,1),:);
                Ocoor=model.structures{snum}(cnum).xyz{mnum}(Oat(:,1),:);
                NOcoor=(Ncoor+Ocoor)/2;
                coor=sum(pop'*NOcoor,1);
                [mNO,nNO]=size(NOcoor);
                diffcoor=NOcoor-repmat(coor,mNO,1);
                [mindiff,paradigm_num]=min(sqrt(sum(diffcoor.^2,2)));
                add_msg_board(sprintf('Residue %i paradigm is %5.2f � from average NO midpoint coordinate.\n',model.structures{snum}(cnum).residues{1}.info(rnum).number,mindiff));
                add_msg_board(sprintf('This is the %ith rotamer with a population of %6.4f, relative population %6.4f.\n',paradigm_num,pop(paradigm_num),pop(paradigm_num)/pop(1)));
            else
                paradigm=false;
            end;
            backbone=true;
            if cleaned,
                atags=model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_tags;
                id=tag2id('N',atags);
                if isempty(id), backbone=false; end;
                id=tag2id('O',atags);
                if isempty(id), backbone=false; end;
                id=tag2id('CA',atags);
                if isempty(id), backbone=false; end;
                id=tag2id('C',atags);
                if isempty(id), backbone=false; end;
                if model.structures{snum}(cnum).residues{mnum}.info(rnum).hetflag,
                    rtag='GLY';
                end;
            end;
            if backbone,
                rnumid=model.structures{snum}(cnum).residues{mnum}.info(rnum).number;
                if terminated,
                    rnumid=currnum+1;
                end;
                rid=sprintf('%4i ',rnumid);
                if started,
                    currnum=currnum+1;
                    while rnumid>currnum,
                        info.seq=[info.seq '-'];
                        currnum=currnum+1;
                    end;
                end;
                cslc=tag2id(upper(rtag),upper(residue_defs.restags),residue_defs.single_letter_code);
                if isempty(cslc), % check for labels and cofactors
                    if strcmpi(rtag,'R1A'),
                        cslc='!';
                    elseif strcmpi(rtag,'IA1'),
                        cslc=';';
                    elseif strcmpi(rtag,'SOD'),
                        cslc='i';
                    elseif strcmpi(strtrim(rtag),'NA'),
                        cslc='i';
                    elseif strcmpi(strtrim(rtag),'MG'),
                        cslc='$';
                    elseif strcmpi(strtrim(rtag),'ZN2'),
                        cslc='z';
                    elseif strcmpi(strtrim(rtag),'ZN'),
                        cslc='z';
                    elseif strcmpi(strtrim(rtag),'CA'),
                        cslc='3';
                    elseif strcmpi(strtrim(rtag),'CAL'),
                        cslc='3';
                    elseif strcmpi(strtrim(rtag),'OXY'),
                        cslc='o';
                    elseif strcmpi(strtrim(rtag),'O2'),
                        cslc='o';
                    elseif strcmpi(strtrim(rtag),'CO'),
                        cslc='b';
                    elseif strcmpi(strtrim(rtag),'CMO'),
                        cslc='b';
                    elseif strcmpi(strtrim(rtag),'MSE'),
                        cslc='m';
                    elseif strcmpi(strtrim(rtag),'HEM'),
                        cslc='h';
                    else
                        cslc='.'; % encode unknown residues as rigid BLK residues
                    end;
                end;
                if ~strcmpi(rtag,'HOH'), % suppress water
                    info.seq=[info.seq cslc];
                else
                    continue;
                end;
                offset=offset+1;
                if new_chain,
                    offsets(curr_chain)=offset-model.structures{snum}(cnum).residues{mnum}.info(rnum).number;
                    new_chain=false;
                end;
                if ~started,
                    info.first=model.structures{snum}(cnum).residues{mnum}.info(rnum).number;
                    started=true;
                    currnum=info.first;
                elseif ~strcmpi(rtag,'HOH'),
                    info.last=rnumid;
                end;
                rid0=id2tag(rnum,model.structures{snum}(cnum).residues{mnum}.residue_tags);
                if double(rid0(end))<double('0') || double(rid0(end))>double('9'),
                    rid(end)=rid0(end);
                end;
                if model.structures{snum}(cnum).residues{mnum}.info(rnum).hetflag,
                    if ~cleaned,
                        tline='HETATM';
                        hetflag=1;
                    else
                        tline='ATOM  ';
                        hetflag=0;
                    end;
                else
                    tline='ATOM  ';
                    hetflag=0;
                end;
                pointers=model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_numbers;
                if isfield(model.structures{snum}(cnum).residues{mnum}.info(rnum),'location_tags')
                    ltags=model.structures{snum}(cnum).residues{mnum}.info(rnum).location_tags;
                else
                    ltags=': :';
                end;
                for anum=1:length(pointers), % loop over atoms
                    pointer=model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_numbers{anum};
                    atag=id2tag(anum,model.structures{snum}(cnum).residues{mnum}.info(rnum).atom_tags);
                    if cleaned && model.structures{snum}(cnum).residues{mnum}.info(rnum).hetflag,
                        id=tag2id(atag,':N:CA:C:O:');
                        if isempty(id),
                            continue;
                        end;
                    end;
                    elnum=model.structures{snum}(cnum).residues{mnum}.info(rnum).elements(anum);
                    element=upper(id2tag(elnum,chemistry.element_tags));
                    if length(element)<2 && length(atag)<4,
                        atag=[' ' atag];
                    end;
                    if length(atag)<4,
                        atag=fillstr(atag,4);
                    end;
                    [loc,n]=size(pointer);
                    if loc>26, loc=26; end;
                    if paradigm,
                        n=1;
                        locs=paradigm_num;
                    else
                        locs=1:loc;
                    end;
                    for lnum=locs, % loop over locations
                        poi=pointer(lnum,1); % actual coordinate set number
                        ltag='';
                        if n>1,
                            occupancy=pointer(lnum,2);
                            ltag=id2tag(pointer(lnum,3),ltags);
                        else
                            occupancy=1.00;
                        end;
                        if isempty(ltag), ltag=' '; end;
                        xyz=model.structures{snum}(cnum).xyz{mnum}(poi,:);
                        Bfactor=model.structures{snum}(cnum).Bfactor{mnum}(poi);
                        atnum=atnum+1;
                        atom_table(atnum,1)=poi;
                        atom_table(atnum,2)=cnum;
                        atom_table(atnum,3)=hetflag;
                        fprintf(fid,'%s%5i %4s%s%s %s%4s   %8.3f%8.3f%8.3f',tline,atnum,atag,ltag,rtag,cid,rid,xyz);
                        fprintf(fid,'%6.2f%6.2f          %2s\n',occupancy,Bfactor,element);
                        numCoord=numCoord+1;
                        if sum(model.structures{snum}(cnum).Btensor{mnum}(poi,:))>=1, % write ANISOU record
                            Btensor=model.structures{snum}(cnum).Btensor{mnum}(poi,:);
                            fprintf(fid,'ANISOU%5i %4s%s%3s %s%4s %7i%7i%7i%7i%7i%7i',atnum,atag,ltag,rtag,cid,rid,Btensor);
                            fprintf(fid,'      %2s\n',element);
                        end;
                    end;
                end;
                if isfield(model.structures{snum}(cnum).residues{mnum}.info(rnum),'terminal')
                    if model.structures{snum}(cnum).residues{mnum}.info(rnum).terminal==1,
                        atnum=atnum+1;
                        fprintf(fid,'TER   %5i      %3s %s%4s\n',atnum,rtag,cid,rid);
                        numTer=numTer+1;
                        terminated=true;
                    end;
                end;
            end;
        end;
    end;
    if models>1,
        fprintf(fid,'ENDMDL\n');
    end;
end;

info.offsets=offsets(1:curr_chain);

% write CONECT records
for cnum=cnumbers,
    cid=model.structures{snum}(cnum).name;
    [conny,n]=size(atom_table);
    [mb,nb]=size(model.structures{snum}(cnum).conn);
    if nb>1,
        for k=1:conny,
            if atom_table(k,2)==cnum,
                poi=atom_table(k,1);
                hetflag1=atom_table(k,3);
                bonds=zeros(1,n);
                hetflags=zeros(1,n);
                for kk=1:n, % translate atom numbers of bonded atoms
                    bond=model.structures{snum}(cnum).conn(poi,kk);
                    if bond,
                        poi2=find(atom_table(:,1)==bond);
                        for kkk=1:length(poi2),
                            if atom_table(poi2(kkk),2)==cnum,
                                bonds(kk)=poi2(kkk);
                                hetflags(kk)=atom_table(poi2(kkk),3);
                            end;
                        end;
                    end;
                end;
                abonds=bonds(1:length(find(bonds>0)));
                poi=0;
                while poi<length(abonds),
                    tline=sprintf('CONECT%5i',k);
                    apoi=0;
                    flush=0;
                    while apoi<4 && poi<length(abonds),
                        poi=poi+1;
                        if hetflag1 || hetflags(poi),
                            apoi=apoi+1;
                            flush=1;
                            tline=sprintf('%s%5i',tline,abonds(poi));
                        end;
                    end;
                    if flush,
                        fprintf(fid,'%s\n',tline);
                        numConect=numConect+1;
                    end;
                end;
            end;
        end;
    end;
end;

% write MASTER record
fprintf(fid,'MASTER    %5i%5i%5i%5i%5i%5i%5i%5i%5i%5i%5i%5i\n',numRemark,0,numHet,numHelix,numSheet,0,numSite,numXform,numCoord,numTer,numConect,numSeq);

% don't forget to close it politely
fprintf(fid,'END   \n');
fclose(fid);


function newstring=fillstr(string,newlength)
% pads a string with spaces

format=sprintf('%%s%%%is',newlength-length(string));
newstring=sprintf(format,string,' ');
% newstring = char(padarray(uint8(string)', newlength-length(string), 32,'post')');
