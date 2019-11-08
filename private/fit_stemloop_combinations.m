function [solutions,trafo,libs,dvecs,best_combi] = fit_stemloop_combinations(restraints,snum0,snum,repname,modnum,options)

global model

best_combi = [];

if ~exist('modnum','var')
    modnum = [];
end

if ~exist('options','var') || isempty(options)
    options.refine = false;
end

forgive = 0.8;
clash_threshold = 1.5*forgive;
fine_clash_thr = 2500;
clash_fail = 10;

link_nt = zeros(1,length(restraints.RNA.bind)-1);
for k = 2:length(restraints.RNA.bind)
    link_nt(k-1) = restraints.RNA.bind(k).nta-restraints.RNA.bind(k-1).nte;
end
thr_length_per_nt = 6;
max_length_per_nt = 5;

nmod = length(model.structures{snum}(1).residues);
dvecs = zeros(nmod,12); 
if isempty(modnum)
    models = 1:nmod;
else
    models = modnum.model;
end
trafo = cell(nmod,3);
template = cell(1,3);
target = cell(1,3);

stag = mk_address(snum);
stag0 = mk_address(snum0);

libs = cell(1,length(restraints.stemlibs));
chains = zeros(1,length(restraints.stemlibs));
sls = zeros(1,length(restraints.stemlibs));
rrm_hulls(3).vertices = [];
rrm_hulls(3).faces = [];
for k = 1:length(restraints.stemlibs)
    lib = load(restraints.stemlibs{k}.name);
    libs{k} = lib.library;
    [~,xyz] = get_object(sprintf('%s%s{1}',stag0,restraints.stemlibs{k}.rrm),'xyz_heavy');
    template{k} = xyz;
    chains(k) = restraints.stemlibs{k}.rrm(2);
    sls(k) = restraints.stemlibs{k}.chaintag(2);
end

report = fopen(repname,'at');

solutions = zeros(10000,5);
valid_rbas = zeros(1,nmod);
spoi = 0;
for k = models % 1:nmod loop over all models
    % determine the transformations
    for kc = 1:length(chains)
        adr = sprintf('%s(%c){%i}',stag,chains(kc),k);
        [~,xyz_new] = get_object(adr,'xyz_heavy');
        target{kc} = xyz_new;
        faces = convhulln(xyz_new);
        [na,~] = size(faces);
        [kpa,ar] = reducepatch(faces,xyz_new,na);
        rrm_hulls(kc).vertices = double(ar);
        rrm_hulls(kc).faces = kpa;
        [~,~,transmat] = rmsd_superimpose(xyz_new,template{kc});
        trafo{k,kc} = transmat;
    end
    % find non-clashing RNA stemloops
    valid_decoys = zeros(length(libs),100);
    vpoi = zeros(1,length(libs));
    for ksl = 1:length(libs)
        library = libs{ksl};
        for kdecoy = 1:length(library.chains)
            xyz_sl = library.xyz_stem{kdecoy};
            hull_vert = library.hulls(kdecoy).vertices;
            transmat = trafo{k,ksl};
            xyz_sl = affine_trafo_coor(xyz_sl,transmat);
            hull_vert = affine_trafo_coor(hull_vert,transmat);
            full_cost = 0;
            all_costs = zeros(1,3);
            % all_costs1 = zeros(1,3);
            for kc = 1:length(chains)
                xyz_rrm = target{kc};
                % cost = clash_cost(xyz_rrm,xyz_sl,clash_threshold);
                cost = clash_cost_super_fast(rrm_hulls(kc).vertices,...
                    rrm_hulls(kc).faces,hull_vert,library.hulls(kdecoy).faces,...
                    xyz_rrm,xyz_sl,clash_threshold,fine_clash_thr);
                all_costs(kc) = cost;
                full_cost = full_cost + cost;
            end
            if full_cost < clash_fail
                vpoi(ksl) = vpoi(ksl) + 1;
                valid_decoys(ksl,vpoi(ksl)) = kdecoy;
            end
        end
    end
    full_expand = prod(vpoi);
    if isempty(vpoi)
        full_expand = 0;
    end
    if full_expand > 0
        % check link restraints
        nlinks = length(restraints.RNA.bind) - 1;
        link_libs = zeros(nlinks,2);
        % anchor assignment array, first column: stemloop libraries (0 if binding motif)
        % second column: link site index in stemloop library or pointer to bindng
        % motif coordinate array bmcoor
        anchors = cell(nlinks,2);
        all_anchor_coor = cell(nlinks,2);
        maxr = zeros(1,nlinks);
        for klink = 1:nlinks
            ntf = restraints.RNA.bind(klink).nte;
            anchors{klink,1} = restraints.RNA.bind(klink).anchore;
            ntl = restraints.RNA.bind(klink+1).nta;
            anchors{klink,2} = restraints.RNA.bind(klink+1).anchora;
            maxr(klink) = (ntl-ntf)*thr_length_per_nt;
            % identify stemloop, if any, otherwise extract coordinate of binding
            % motif
            affound = false; % first anchor found in stemloop library
            alfound = false; % last anchor found in stemloop library
            for ksl = 1:length(libs)
                transmat = trafo{k,ksl};
                for klsl = 1:length(libs{ksl}.linksites)
                    if strcmpi(anchors{klink,1},libs{ksl}.linksites(klsl).adr)
                        affound = true;
                        anchor_coor = libs{ksl}.linksites(klsl).coor;
                        anchor_coor = affine_trafo_coor(anchor_coor,transmat);
                        all_anchor_coor{klink,1} = anchor_coor;
                        link_libs(klink,1) = ksl;
                    end
                    if strcmpi(anchors{klink,2},libs{ksl}.linksites(klsl).adr)
                        alfound = true;
                        anchor_coor = libs{ksl}.linksites(klsl).coor;
                        anchor_coor = affine_trafo_coor(anchor_coor,transmat);
                        all_anchor_coor{klink,2} = anchor_coor;
                        link_libs(klink,2) = ksl;
                    end
                end
            end
            if ~affound % this must be an anchor in a binding site
                poi = strfind(anchors{klink,1},')');
                ctag = anchors{klink,1}(1:poi);
                nttag = anchors{klink,1}(poi+1:end);
                [~,anchor_coor] = get_object(sprintf('%s%s{%i}%s.C5''',stag,ctag,k,nttag),'coor');
                all_anchor_coor{klink,1} = anchor_coor;
            end
            if ~alfound % this must be an anchor in a binding site
                poi = strfind(anchors{klink,2},')');
                ctag = anchors{klink,2}(1:poi);
                nttag = anchors{klink,2}(poi+1:end);
                [~,anchor_coor] = get_object(sprintf('%s%s{%i}%s.C5''',stag,ctag,k,nttag),'coor');
                all_anchor_coor{klink,2} = anchor_coor;
            end
        end


        expand = 1;
        all_combis = zeros(length(libs),full_expand);
        for ksl = 1:length(libs)
            decoys = valid_decoys(ksl,1:vpoi(ksl));
            for kk = 1:length(decoys)
                bas = 1+(kk-1)*expand;
                all_combis(ksl,bas:bas+expand-1) = decoys(kk)*ones(1,expand);
                for kp = 1:ksl-1
                    all_combis(kp,bas:bas+expand-1) = all_combis(kp,1:expand);
                end
            end
            expand = expand*vpoi(ksl);
        end

        min_stretch = 1e6;
        best_r = 1e6*ones(1,nlinks);
        best_combi = zeros(1,length(libs));
        for kcombi = 1:full_expand
            stretch = 0;
            all_r = zeros(1,nlinks);
            for klink = 1:nlinks
                facoors = all_anchor_coor{klink,1};
                lacoors = all_anchor_coor{klink,2};
                if link_libs(klink,1) ~= 0
                    facoor = facoors(all_combis(link_libs(klink,1),kcombi),:);
                else
                    facoor = facoors;
                end
                if link_libs(klink,2) ~= 0
                    lacoor = lacoors(all_combis(link_libs(klink,2),kcombi),:);
                else
                    lacoor = lacoors;
                end
                rmod = norm(facoor-lacoor);
                all_r(klink) = rmod;
                lnt = rmod/link_nt(klink);
                if lnt > max_length_per_nt
                    stretch = stretch + (lnt-max_length_per_nt)^2;
                end
            end
            valid_combi = true;
            for klink = 1:nlinks
                if all_r(klink) > link_nt(klink)*thr_length_per_nt
                    valid_combi = false;
                end
            end
            if valid_combi
                failed = false;
                for ksl1 = 1:length(libs)-1
                    library1 = libs{ksl1};
                    kdecoy1 = all_combis(ksl1,kcombi);
                    xyz_sl1 = library1.chains{kdecoy1}.xyz{1};
                    hull_vert1 = library1.hulls(kdecoy1).vertices;
                    transmat1 = trafo{k,ksl1};
                    xyz_sl1 = affine_trafo_coor(xyz_sl1,transmat1);
                    hull_vert1 = affine_trafo_coor(hull_vert1,transmat1);
                    for ksl2 = ksl1+1:length(libs)
                        library2 = libs{ksl2};
                        kdecoy2 = all_combis(ksl2,kcombi);
                        xyz_sl2 = library2.chains{kdecoy2}.xyz{1};
                        hull_vert2 = library2.hulls(kdecoy2).vertices;
                        transmat2 = trafo{k,ksl2};
                        xyz_sl2 = affine_trafo_coor(xyz_sl2,transmat2);
                        hull_vert2 = affine_trafo_coor(hull_vert2,transmat2);
                        cost = clash_cost_super_fast(hull_vert1,...
                            library1.hulls(kdecoy1).faces,...
                            hull_vert2,library2.hulls(kdecoy2).faces,...
                            xyz_sl1,xyz_sl2,clash_threshold,fine_clash_thr);
                        if cost > clash_fail
                            failed = true;
                        end
                        if failed
                            break
                        end
                    end
                    if failed
                        break
                    end
                end
                if failed
                    valid_combi = false;
                end
            end
            if valid_combi
                if stretch < min_stretch
                    min_stretch = stretch;
                    best_r = all_r;
                    best_combi = all_combis(:,kcombi).';
                end
                spoi = spoi + 1;
                valid_rbas(k) = 1;
                solutions(spoi,1) = k;
                solutions(spoi,2) = stretch;
                for ksl = 1:length(libs)
                    solutions(spoi,2+ksl) = all_combis(ksl,kcombi);
                end
            end
        end

        fprintf(report,'Best combination:\n');
        if ~isempty(modnum)
            fprintf(report,'R%i.%i|',modnum.block,modnum.num);
        end
        fprintf(report,'M(%i)SL(%i',k,best_combi(1));
        for ksl = 2:length(libs)
            fprintf(report,', %i',best_combi(ksl));
        end
        fprintf(report,')\n');
        fprintf(report,'r = %5.1f',best_r(1));
        for kr = 2:length(best_r)
            fprintf(report,', %5.1f',best_r(kr));
        end
        fprintf(report,' �\n');
    end
end
solutions = solutions(1:spoi,:);
fclose(report);

