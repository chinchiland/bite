"""Packs MakeHuman's CC0 body for Bite's body view into Bite/Resources/Body/body.bin.

Run from the repo with MakeHuman's data checked out or downloaded (makehumancommunity/makehuman,
makehuman/data): python3 tools/body/pack_body.py <makehuman data folder> Bite/Resources/Body/body.bin
It reads 3dobjs/base.obj, rigs/default.mhskel, rigs/default_weights.mhw and the young targets in
targets/macrodetails.

The skin is the body group and the eyeballs, in MakeHuman's rest pose. A reduced skeleton of 20
bones poses it: every MakeHuman bone folds into the nearest kept ancestor, each vertex keeps its four
strongest bones, and each bone's head is the centre of a joint group of helper vertices, packed as
vertices too so every shape moves them.

Layout (little endian): 'BODY', u32 N, u32 T, f32 height span; f32[N*3] male base, f32[N*3] female
base; 18 x (f32 scale, i16[N*3]) universal deltas (male then female, muscle min/avg/max x weight
min/avg/max); u16[T*3] triangles; u8[N] eyes (1 left, 2 right); u8 bone count; per bone u8 parent
(255 for none), u8 name length, name, u32 n, u32[n] joint vertices; u8[N*4] bone indices; u8[N*4]
weights (sum 255).
"""
import sys, struct, os, array, json

raw, out = sys.argv[1], sys.argv[2]
SKIN = {'body', 'helper-l-eye', 'helper-r-eye'}

# The kept bones, parent first; each names the MakeHuman bone whose head is its head.
BONES = [
    ('root', None, 'root'),
    ('thigh.L', 'root', 'upperleg01.L'), ('shin.L', 'thigh.L', 'lowerleg01.L'), ('foot.L', 'shin.L', 'foot.L'),
    ('thigh.R', 'root', 'upperleg01.R'), ('shin.R', 'thigh.R', 'lowerleg01.R'), ('foot.R', 'shin.R', 'foot.R'),
    ('spineLow', 'root', 'spine05'), ('spineMid', 'spineLow', 'spine03'), ('chest', 'spineMid', 'spine01'),
    ('clavicle.L', 'chest', 'clavicle.L'), ('upperarm.L', 'clavicle.L', 'upperarm01.L'), ('lowerarm.L', 'upperarm.L', 'lowerarm01.L'), ('hand.L', 'lowerarm.L', 'wrist.L'),
    ('clavicle.R', 'chest', 'clavicle.R'), ('upperarm.R', 'clavicle.R', 'upperarm01.R'), ('lowerarm.R', 'upperarm.R', 'lowerarm01.R'), ('hand.R', 'lowerarm.R', 'wrist.R'),
    ('neck', 'chest', 'neck01'), ('head', 'neck', 'head'),
]
KEEP_AT = {mh: name for name, _, mh in BONES}
FOLD = {'pelvis.L': 'root', 'pelvis.R': 'root', 'spine04': 'spineLow', 'spine02': 'spineMid', 'breast.L': 'chest', 'breast.R': 'chest',
        'shoulder01.L': 'clavicle.L', 'shoulder01.R': 'clavicle.R', 'upperarm02.L': 'upperarm.L', 'upperarm02.R': 'upperarm.R',
        'lowerarm02.L': 'lowerarm.L', 'lowerarm02.R': 'lowerarm.R', 'upperleg02.L': 'thigh.L', 'upperleg02.R': 'thigh.R',
        'lowerleg02.L': 'shin.L', 'lowerleg02.R': 'shin.R', 'neck02': 'neck', 'neck03': 'neck'}

verts, faces = [], []
group = None
with open(os.path.join(raw, '3dobjs', 'base.obj'), encoding='utf-8', errors='replace') as f:
    for line in f:
        if line.startswith('v '):
            verts.append(tuple(float(v) for v in line.split()[1:4]))
        elif line.startswith('g '):
            group = line.split(None, 1)[1].strip()
        elif line.startswith('f ') and group in SKIN:
            faces.append((group, [int(p.split('/')[0]) - 1 for p in line.split()[1:]]))

skel = json.load(open(os.path.join(raw, 'rigs', 'default.mhskel'), encoding='utf-8'))
weights = json.load(open(os.path.join(raw, 'rigs', 'default_weights.mhw'), encoding='utf-8'))['weights']
mh = skel['bones']


def kept(name):
    """The kept bone a MakeHuman bone folds into."""
    while name is not None:
        if name in KEEP_AT:
            return KEEP_AT[name]
        if name in FOLD:
            return FOLD[name]
        name = mh[name].get('parent')
    return 'root'


joint_groups = [skel['joints'][mh[m]['head']] for _, _, m in BONES]
used = sorted({i for _, idx in faces for i in idx} | {i for g in joint_groups for i in g})
remap = {v: k for k, v in enumerate(used)}
N = len(used)


def target(name):
    d = {}
    with open(os.path.join(raw, 'targets', 'macrodetails', name), encoding='utf-8', errors='replace') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                p = line.split()
                d[int(p[0])] = (float(p[1]), float(p[2]), float(p[3]))
    return d


def dense(d):
    a = [0.0] * (N * 3)
    for i, (dx, dy, dz) in d.items():
        k = remap.get(i)
        if k is not None:
            a[k * 3], a[k * 3 + 1], a[k * 3 + 2] = dx, dy, dz
    return a


bases = {}
for g in ('male', 'female'):
    races = [dense(target(f'{r}-{g}-young.target')) for r in ('african', 'asian', 'caucasian')]
    bases[g] = [verts[used[k // 3]][k % 3] + sum(r[k] for r in races) / 3 for k in range(N * 3)]
ys = [bases['male'][k * 3 + 1] for k in range(N)]
span = max(ys) - min(ys)

skin = []
eye = bytearray(N)
for g, idx in faces:
    r = [remap[i] for i in idx]
    skin += [(r[0], r[k], r[k + 1]) for k in range(1, len(r) - 1)]
    if g != 'body':
        for k in r:
            eye[k] = 1 if g == 'helper-l-eye' else 2

# Skin weights onto the kept bones, four strongest per vertex.
index_of = {name: i for i, (name, _, _) in enumerate(BONES)}
acc = [dict() for _ in range(N)]
for bone, pairs in weights.items():
    k_bone = index_of[kept(bone)]
    for i, w in pairs:
        k = remap.get(i)
        if k is not None:
            acc[k][k_bone] = acc[k].get(k_bone, 0.0) + w
bidx, bw = bytearray(N * 4), bytearray(N * 4)
for k in range(N):
    top = sorted(acc[k].items(), key=lambda x: -x[1])[:4] or [(0, 1.0)]
    total = sum(w for _, w in top) or 1.0
    q = [int(round(255 * w / total)) for _, w in top]
    q[0] += 255 - sum(q)
    for j, ((b, _), w) in enumerate(zip(top, q)):
        bidx[k * 4 + j], bw[k * 4 + j] = b, w

buf = bytearray(b'BODY' + struct.pack('<IIf', N, len(skin), span))
for g in ('male', 'female'):
    buf += array.array('f', bases[g]).tobytes()
for g in ('male', 'female'):
    for m in ('min', 'average', 'max'):
        for w in ('min', 'average', 'max'):
            d = dense(target(f'universal-{g}-young-{m}muscle-{w}weight.target'))
            scale = max(max(abs(v) for v in d), 1e-6) / 32767
            buf += struct.pack('<f', scale) + array.array('h', [int(round(v / scale)) for v in d]).tobytes()
buf += array.array('H', [i for t in skin for i in t]).tobytes()
buf += bytes(eye)
buf += struct.pack('<B', len(BONES))
for (name, parent, m), group_ in zip(BONES, joint_groups):
    ids = [remap[i] for i in group_]
    nb = name.encode('ascii')
    buf += struct.pack('<BB', 255 if parent is None else index_of[parent], len(nb)) + nb
    buf += struct.pack('<I', len(ids)) + array.array('I', ids).tobytes()
buf += bytes(bidx) + bytes(bw)
with open(out, 'wb') as f:
    f.write(bytes(buf))
print('N', N, 'tris', len(skin), 'bones', len(BONES), 'bytes', len(buf))
