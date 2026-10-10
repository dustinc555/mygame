"""glTF body decoding for the stable, welded shared cage, not garment vertices.

Garment arrays always come from native_bridge.gd. This retains the exact source
precision and lexicographic cage IDs used by the visually checked registration.
"""
import base64
import hashlib
import json
import math
from pathlib import Path
import struct
from urllib.parse import unquote
import numpy as np
from binding import points_array, matrix
from provenance import gltf_document

DTYPES = {5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}
COUNTS = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT2':4,'MAT3':9,'MAT4':16}

def node_matrix(n):
    if 'matrix' in n:
        return np.array(n['matrix'], dtype=float).reshape((4,4),order='F')
    x,y,z,w = n.get('rotation',[0,0,0,1])
    r = np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                  [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                  [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    m = np.eye(4)
    m[:3,:3] = r @ np.diag(n.get('scale',[1,1,1]))
    m[:3,3] = n.get('translation',[0,0,0])
    return m

def transform(m,p):
    return p @ m[:3,:3].T + m[:3,3]

class Asset:
    def __init__(self, path):
        self.path=Path(path)
        raw=self.path.read_bytes()
        gltf_document(raw)  # Validate GLB framing/LFS before decoding.
        self.files={self.path:(len(raw),hashlib.sha256(raw).hexdigest())}
        bins=[]
        if raw[:4]==b'glTF':
            magic,version,length=struct.unpack_from('<4sII',raw)
            if version != 2 or length != len(raw): raise ValueError("invalid GLB header")
            offset=12
            while offset<len(raw):
                size,kind=struct.unpack_from('<II',raw,offset); offset+=8
                content=raw[offset:offset+size];offset+=size
                if kind==0x4e4f534a: self.doc=json.loads(content)
                elif kind==0x004e4942: bins.append(content)
        else:
            self.doc=json.loads(raw)
        self.buffers=[]
        for b in self.doc.get('buffers',[]):
            uri=b.get('uri')
            if uri is None:
                content=bins.pop(0)
            elif uri.startswith('data:'):
                header,data=uri.split(',',1)
                content=base64.b64decode(data) if ';base64' in header else unquote(data).encode()
            else:
                bp=self.path.parent/unquote(uri)
                content=bp.read_bytes()
                self.files[bp]=(len(content),hashlib.sha256(content).hexdigest())
            if len(content) < b['byteLength']: raise ValueError('truncated glTF buffer')
            self.buffers.append(content)
        self.cache={}
        self.nodes=self.doc.get('nodes',[])
        self.parents={child:i for i,n in enumerate(self.nodes) for child in n.get('children',[])}
        self.local=[node_matrix(n) for n in self.nodes]
        self.world={}
        visiting = set()
        def world(i):
            if i in visiting: raise ValueError("cyclic glTF node graph")
            if i not in self.world:
                visiting.add(i)
                self.world[i]=(world(self.parents[i]) if i in self.parents else np.eye(4))@self.local[i]
            visiting.discard(i)
            return self.world[i]
        for i in range(len(self.nodes)): world(i)
        self.mesh_nodes=[i for i,n in enumerate(self.nodes) if 'mesh' in n]
        self.skins=self.doc.get('skins',[])

    def accessor(self,i,normalized=True):
        key=(i,normalized)
        if key in self.cache: return self.cache[key]
        a=self.doc['accessors'][i]
        dtype=np.dtype(DTYPES[a['componentType']]); n=COUNTS[a['type']]
        if a['type'].startswith('MAT'):
            side=int(a['type'][3:]); column_stride=math.ceil(side*dtype.itemsize/4)*4
            offsets=[col*column_stride+row*dtype.itemsize for col in range(side) for row in range(side)]
            element_stride=side*column_stride
        else:
            offsets=list(range(0,n*dtype.itemsize,dtype.itemsize));element_stride=n*dtype.itemsize
        def fetch(view_id,byte_offset,count,stride=None):
            view=self.doc['bufferViews'][view_id];start=view.get('byteOffset',0)+byte_offset
            step=stride or view.get('byteStride',element_stride)
            if count < 0 or (count and byte_offset+(count-1)*step+offsets[-1]+dtype.itemsize > view['byteLength']): raise ValueError('accessor exceeds buffer view')
            return np.stack([np.ndarray((count,),dtype=dtype,buffer=self.buffers[view['buffer']],offset=start+o,strides=(step,)) for o in offsets],axis=1).copy()
        result=fetch(a['bufferView'],a.get('byteOffset',0),a['count']) if 'bufferView' in a else np.zeros((a['count'],n),dtype=dtype)
        if 'sparse' in a:
            s=a['sparse'];v=self.doc['bufferViews'][s['indices']['bufferView']]
            idx=np.frombuffer(self.buffers[v['buffer']],dtype=np.dtype(DTYPES[s['indices']['componentType']]),count=s['count'],offset=v.get('byteOffset',0)+s['indices'].get('byteOffset',0))
            result[idx]=fetch(s['values']['bufferView'],s['values'].get('byteOffset',0),s['count'],element_stride)
        if normalized and a.get('normalized'):
            if dtype.kind=='u': result=result.astype(float)/np.iinfo(dtype).max
            else: result=np.maximum(result.astype(float)/np.iinfo(dtype).max,-1)
        if not np.isfinite(result).all(): raise ValueError("nonfinite glTF accessor")
        self.cache[key]=result
        return result

    def prim(self,node,prim=0): return self.doc['meshes'][self.nodes[node]['mesh']]['primitives'][prim]
    def attrs(self,node,prim=0): return {k:self.accessor(i) for k,i in self.prim(node,prim)['attributes'].items()}
    def indices(self,node,prim=0):
        p=self.prim(node,prim)
        return self.accessor(p['indices']).reshape(-1) if 'indices' in p else np.arange(len(self.attrs(node,prim)['POSITION']))
    def joints(self,node): return self.skins[self.nodes[node]['skin']]['joints']
    def joint_names(self,node): return [self.nodes[i].get('name',str(i)) for i in self.joints(node)]
    def ibm(self,node):
        s=self.skins[self.nodes[node]['skin']]
        if 'inverseBindMatrices' not in s:return np.repeat(np.eye(4)[None],len(s['joints']),axis=0)
        return self.accessor(s['inverseBindMatrices']).astype(float).reshape((-1,4,4)).transpose(0,2,1)
    def skin_graph(self,node):
        joints=self.joints(node); jset=set(joints); out={}
        for i in joints:
            parent=self.parents.get(i)
            while parent is not None and parent not in jset: parent=self.parents.get(parent)
            out[self.nodes[i].get('name',str(i))]=self.nodes[parent].get('name',str(parent)) if parent is not None else None
        return out
    def body_node(self):
        return max(self.mesh_nodes,key=lambda i:sum(len(self.attrs(i,p)['POSITION']) for p in range(len(self.doc['meshes'][self.nodes[i]['mesh']]['primitives']))))
    def skin_weights(self,node,prim=0,order=None):
        a=self.attrs(node,prim);names=self.joint_names(node);order=order or sorted(names); ix={name:i for i,name in enumerate(order)}
        weights=np.zeros((len(a['POSITION']),len(order)))
        for key in a:
            if not key.startswith('JOINTS_'):continue
            joints=a[key].astype(int); w=a['WEIGHTS_'+key[7:]]
            for k in range(joints.shape[1]):
                columns=np.array([ix[names[j]] for j in joints[:,k]])
                np.add.at(weights,(np.arange(len(weights)),columns),w[:,k])
        return weights,order
    def rest_positions(self,node,prim=0):
        a=self.attrs(node,prim)
        if 'skin' not in self.nodes[node]:return transform(self.world[node],a['POSITION'])
        out=np.zeros_like(a['POSITION'],dtype=float)
        matrices=np.array([self.world[j]@ib for j,ib in zip(self.joints(node),self.ibm(node))])
        for key in a:
            if not key.startswith('JOINTS_'):continue
            js=a[key].astype(int);ws=a['WEIGHTS_'+key[7:]]
            for k in range(js.shape[1]):
                m=matrices[js[:,k]]
                out+=(np.einsum('nij,nj->ni',m[:,:3,:3],a['POSITION'])+m[:,:3,3])*ws[:,k,None]
        return out


def mesh_data(path, mesh_name, weld_decimals=6):
    asset = Asset(path)
    matches = [i for i in asset.mesh_nodes if asset.nodes[i].get("name") == mesh_name]
    if len(matches) != 1:
        raise ValueError(f"expected exactly one registration mesh {mesh_name!r}, found {len(matches)}")
    node = matches[0]
    primitives = asset.doc["meshes"][asset.nodes[node]["mesh"]]["primitives"]
    if len(primitives) != 1 or primitives[0].get("mode", 4) != 4:
        raise ValueError("registration mesh requires one triangle primitive; choose the body, not apparel")
    if primitives[0].get("targets"):
        raise ValueError("registration of morph-target bodies is not implemented")
    xyz = points_array(asset.rest_positions(node), "body positions")
    indices = asset.indices(node)
    if len(indices) % 3 or len(indices) == 0 or indices.min() < 0 or indices.max() >= len(xyz):
        raise ValueError("invalid body triangle indices")
    weights, names = asset.skin_weights(node)
    if len(names) != len(set(names)) or not np.isfinite(weights).all() or np.any(weights < 0):
        raise ValueError("invalid body skin names/weights")
    if not np.allclose(weights.sum(axis=1), 1, atol=1e-4, rtol=0):
        raise ValueError("body skin weights must sum to one")
    rests = {asset.nodes[j]["name"]: matrix(asset.world[j], "body rest") for j in asset.joints(node)}
    # Exact study rule: keep the first source vertex at every rounded position.
    _, first, inverse = np.unique(np.round(xyz, weld_decimals), axis=0, return_index=True, return_inverse=True)
    return xyz[first], inverse[indices.reshape(-1, 3).astype(int)], weights[first], names, rests


def world_to_skeleton(raw_rests, imported_rests, tolerance=1e-5):
    transforms = []
    for name, rest in raw_rests.items():
        if name not in imported_rests:
            raise ValueError(f"imported body is missing source joint {name}")
        transforms.append(matrix(imported_rests[name], name) @ np.linalg.inv(rest))
    if not transforms or not np.allclose(transforms, transforms[0], atol=tolerance, rtol=0):
        raise ValueError("source/import rest frames are not related by one consistent transform")
    return transforms[0]
