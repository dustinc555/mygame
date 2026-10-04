"""Common-body registration migrated from the visually checked cage study.

Named-rest initial alignment, weight-constrained surface ICP, Laplacian smoothing.
This is body-owned work; no garment participates in registration.
"""
import numpy as np
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix, eye, diags
from scipy.sparse.linalg import factorized


def transform(m, points):
    return points @ m[:3, :3].T + m[:3, 3]


def norm(x):
    return x/np.maximum(np.linalg.norm(x,axis=-1,keepdims=True),1e-10)

def normals(x,f):
    n=np.zeros_like(x)
    fn=np.cross(x[f[:,1]]-x[f[:,0]],x[f[:,2]]-x[f[:,0]])
    for i in range(3):np.add.at(n,f[:,i],fn)
    return norm(n)

def bone_scale(s,t,name):
    # Semantic lengths are initial alignment only, not the final body surface fit.
    candidates=[]
    for n in s:
        if n==name or n not in t:continue
        d=np.linalg.norm(s[n][:3,3]-s[name][:3,3])
        if d>1e-4:candidates.append((d,n))
    d,n=min(candidates)
    return np.linalg.norm(t[n][:3,3]-t[name][:3,3])/d

def align(x,w,names,source,target):
    y=np.zeros_like(x)
    for i,n in enumerate(names):
        if n not in target:raise ValueError('Missing target joint '+n)
        scale=bone_scale(source,target,n)
        m=target[n]@np.diag([scale,scale,scale,1])@np.linalg.inv(source[n])
        y+=transform(m,x)*w[:,i,None]
    return y

def closest_triangle(p,tri):
    # Projection onto triangle plane, plus all edges; choose true closest point.
    a,b,c=tri[...,0,:],tri[...,1,:],tri[...,2,:]
    ab=b-a;ac=c-a;ap=p-a
    d00=np.sum(ab*ab,axis=-1);d01=np.sum(ab*ac,axis=-1);d11=np.sum(ac*ac,axis=-1)
    d20=np.sum(ap*ab,axis=-1);d21=np.sum(ap*ac,axis=-1)
    denom=d00*d11-d01*d01
    v=(d11*d20-d01*d21)/np.maximum(denom,1e-20)
    w=(d00*d21-d01*d20)/np.maximum(denom,1e-20)
    point=a+v[...,None]*ab+w[...,None]*ac
    valid=(v>=0)&(w>=0)&(v+w<=1)&(denom>1e-18)
    candidates=[point];dists=[np.where(valid,np.sum((point-p)**2,axis=-1),np.inf)]
    for e0,e1 in [(a,b),(b,c),(c,a)]:
        edge=e1-e0
        frac=np.clip(np.sum((p-e0)*edge,axis=-1)/np.maximum(np.sum(edge*edge,axis=-1),1e-20),0,1)
        point=e0+frac[...,None]*edge
        candidates.append(point);dists.append(np.sum((point-p)**2,axis=-1))
    candidates=np.stack(candidates,axis=-2);dists=np.stack(dists,axis=-1)
    best=dists.argmin(axis=-1)
    point=np.take_along_axis(candidates,best[...,None,None],axis=-2)[...,0,:]
    return point,np.min(dists,axis=-1)


def preserve_foot_shape(source, target, registered, settings):
    """Fit each complete foot coherently when calf/ankle skin weights differ.

    This body-owned registration uses geometry, not per-joint animation weights,
    within the calf/foot/ball chain. Independent closest-point displacements can
    collapse the heel into the instep; a positive affine fit preserves its cut.
    The canonical humanoid sources are Y-up and ground-aligned. Blend back to
    ordinary registration between 1.4 and 2.4 reference ankle heights.
    """
    x, faces, weights, names, rests = source
    y, target_faces, target_weights, target_names, target_rests = target
    result = registered.copy()
    source_normals = normals(x, faces)
    reports = {}
    for side in ("l", "r"):
        chain = [name + "_" + side for name in ("calf", "foot", "ball")]
        if any(name not in names or name not in target_names for name in chain):
            raise ValueError("foot shape registration requires calf/foot/ball joints on both bodies")
        source_influence = weights[:, [names.index(name) for name in chain]].sum(axis=1)
        target_influence = target_weights[:, [target_names.index(name) for name in chain]].sum(axis=1)
        ankle = rests["foot_" + side][:3, 3]
        target_ankle = target_rests["foot_" + side][:3, 3]
        if ankle[1] <= 0:
            raise ValueError("foot shape registration requires ground-aligned humanoid sources")
        full_height, blend_height = ankle[1] * 1.4, ankle[1] * 2.4
        region = (source_influence > .9) & (x[:, 1] < blend_height)
        seed = x[region].copy()
        seed[:, [0, 2]] += (target_ankle - ankle)[[0, 2]]
        valid = ((target_influence[target_faces].min(axis=1) > .9)
                 & (y[target_faces][:, :, 1].mean(axis=1) < blend_height))
        triangles = y[target_faces[valid]]
        core = seed[:, 1] < full_height
        if core.sum() < 4 or not len(triangles):
            raise ValueError("foot shape registration has insufficient foot surface geometry")
        tree = cKDTree(triangles.mean(axis=1))
        _, candidates = tree.query(seed, k=min(64, len(triangles)))
        candidates = candidates.reshape(len(seed), -1)
        points, distances = closest_triangle(seed[:, None, :], triangles[candidates])
        target_normals = norm(np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0]))
        facing = (target_normals[candidates] * source_normals[region, None, :]).sum(axis=-1)
        cost = distances + settings["opposed_normal_penalty"] * np.minimum(facing, 0) ** 2
        goal = points[np.arange(len(seed)), cost.argmin(axis=1)]
        local = np.column_stack((x[region], np.ones(region.sum())))
        affine, _, rank, _ = np.linalg.lstsq(local[core], goal[core], rcond=None)
        if rank != 4 or not np.isfinite(affine).all() or np.linalg.det(affine[:3]) <= 0:
            raise ValueError("foot shape registration produced a folded or degenerate fit")
        # Average surface matching can underestimate the widest toe/heel edge.
        # Retain the actual body's width, not an added clothing-clearance margin.
        target_core = (target_influence > .9) & (y[:, 1] < target_ankle[1] * 1.4)
        predicted = local[core] @ affine
        low, high = predicted[:, 0].min(), predicted[:, 0].max()
        if not target_core.any() or high - low <= 1e-6:
            raise ValueError("foot shape registration has no measurable foot width")
        target_low, target_high = y[target_core, 0].min(), y[target_core, 0].max()
        width_scale = (target_high - target_low) / (high - low)
        affine[:, 0] *= width_scale
        affine[3, 0] += target_low - low * width_scale
        blend = np.clip((blend_height - x[region, 1]) / (blend_height - full_height), 0, 1)
        blend = blend * blend * (3 - 2 * blend)
        result[region] += (local @ affine - registered[region]) * blend[:, None]
        reports[side] = {"point_count": int(region.sum()), "affine": affine.tolist(),
                         "max_change_m": float(np.linalg.norm(result[region] - registered[region], axis=1).max())}
    return result, reports


def register(source,target,settings=None):
    # Defaults exactly match the inspected study; manifest overrides are explicit.
    from manifest import DEFAULT_REGISTRATION
    settings = settings or DEFAULT_REGISTRATION
    x,f,w,names,rest=source;y,tf,tw,tnames,trest=target
    tw=tw[:,[tnames.index(n) for n in names]]
    initial=align(x,w,names,rest,trest)
    if np.max(np.abs(initial-x))<1e-5 and len(x)==len(y) and np.allclose(x,y):return x.copy(),{'identity':True}
    centers=y[tf].mean(axis=1); fw=tw[tf].mean(axis=1)
    tn=norm(np.cross(y[tf[:,1]]-y[tf[:,0]],y[tf[:,2]]-y[tf[:,0]]))
    tree=cKDTree(centers)
    edges=np.concatenate([f[:,[0,1]],f[:,[1,2]],f[:,[2,0]]]);edges=np.unique(np.sort(edges,axis=1),axis=0)
    rows=np.r_[edges[:,0],edges[:,1]];cols=np.r_[edges[:,1],edges[:,0]]
    adjacency=coo_matrix((np.ones(len(rows)),(rows,cols)),shape=(len(x),len(x))).tocsr()
    degree=np.asarray(adjacency.sum(axis=1)).ravel();lap=eye(len(x))-diags(1/np.maximum(degree,1))@adjacency
    current=initial.copy();metrics=[]
    for strength in settings['stiffness']:
        solve=factorized((eye(len(x))+strength*(lap.T@lap)).tocsc())
        for iteration in range(settings['iterations_per_stage']):
            _,candidates=tree.query(current,k=min(settings['candidate_triangles'], len(tf)))
            candidates = candidates.reshape(len(current), -1)
            points,d2=closest_triangle(current[:,None,:],y[tf[candidates]])
            cn=normals(current,f)
            mismatch=np.sum((fw[candidates]-w[:,None,:])**2,axis=-1)
            facing=np.sum(tn[candidates]*cn[:,None,:],axis=-1)
            cost=d2+settings['skin_weight_penalty']*mismatch+settings['opposed_normal_penalty']*np.minimum(facing,0)**2
            chosen=cost.argmin(axis=1);goal=points[np.arange(len(x)),chosen]
            displacement=goal-initial
            current=initial+np.column_stack([solve(displacement[:,i]) for i in range(3)])
        error=np.linalg.norm(current-goal,axis=1)
        metrics.append({'stiffness':strength,'median_m':float(np.median(error)),'p95_m':float(np.quantile(error,.95)),'max_m':float(error.max())})
    report = {'iterations':metrics}
    if settings.get('preserve_foot_shape', False):
        current, report['foot_shape'] = preserve_foot_shape(source, target, current, settings)
    return current,report

