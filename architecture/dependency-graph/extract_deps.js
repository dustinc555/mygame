// GDScript dependency + coupling + architecture-rule analyzer.
// Emits graphdata.js for the ECharts viewer (index.html). Run: node extract_deps.js
//
// Detects two rule violations:
//   1. TRUTH-RULE   — a GECS system/component depending on a live node (Actors/UI/World-Content).
//                     Rule: "GECS owns truth; systems read components, not nodes."
//   2. TICK-CADENCE — a durable-domain node running real work on _process/_physics_process
//                     every frame, ungated by LOD, and not driven by the world-sim ticker.
//                     Rule: "a tick is only OK if it's projection-side (stops outside LOD)
//                     or driven by the controlled world-sim ticker at O(1) cadence."
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const ROOT = path.resolve(__dirname, '..', '..');     // repo root (architecture/dependency-graph/../../)
const SRC = path.join(ROOT, 'scripts');

const EXCLUDE = ['validation','benchmark','test_levels','test_scenes','showcase','dev','tools','debug','conditions'];
function layerOf(rel) {
  const seg = rel.replace(/\\/g,'/').split('/');
  const d0 = seg[0], d1 = seg[1] || '';
  if (d0 === 'ecs' && d1 === 'components') return 'GECS·Components';
  if (d0 === 'ecs' && d1 === 'systems') return 'GECS·Systems';
  if (d0 === 'ecs') return 'GECS·Core';
  if (d0 === 'controllers') return 'Controllers';
  if (d0 === 'characters' || d0 === 'actors') return 'Actors';
  if (d0 === 'projection') return 'Projection';
  if (d0 === 'ai') return 'AI';
  if (d0 === 'world_sim' || d0 === 'simulation') return 'World-Sim';
  if (d0 === 'world') return 'World-Content';
  if (d0 === 'items') return 'Items';
  if (d0 === 'ui') return 'UI';
  if (d0 === 'jobs' || d0 === 'conversation' || d0 === 'skills' || d0 === 'ownership' || d0 === 'roles') return 'Social/Jobs';
  if (d0 === 'character_appearance' || d0 === 'navigation') return 'Appearance/Nav';
  if (d0 === 'bootstrap') return 'Bootstrap';
  if (d0 === 'resources') return 'Resources';
  return 'Other';
}

function walk(dir) {
  let out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out = out.concat(walk(full));
    else if (e.name.endsWith('.gd')) out.push(full);
  }
  return out;
}
let files = walk(SRC).filter(f => !EXCLUDE.includes(path.relative(SRC, f).split(path.sep)[0]));

// ---- git working-tree status (raw diffs): tag new / modified ----
const changed = {};   // repo-relative path -> 'new' | 'modified'
try {
  const out = execSync('git status --porcelain', { cwd: ROOT, encoding: 'utf8' });
  for (const line of out.split('\n')) {
    if (!line.trim()) continue;
    const xy = line.slice(0, 2);
    let p = line.slice(3).trim();
    if (p.includes(' -> ')) p = p.split(' -> ').pop();   // renames
    if (xy.includes('?') || xy.includes('A')) changed[p] = 'new';
    else if (/[MRC]/.test(xy)) changed[p] = 'modified';
  }
} catch (e) { /* not a git repo / git unavailable */ }
const statusOf = f => changed[path.relative(ROOT, f).split(path.sep).join('/')] || null;

// ---- pass 1: class_name maps ----
const fileInfo = {}, classToFile = {};
const resToFile = f => path.join(ROOT, f.replace(/^res:\/\//,''));
for (const f of files) {
  const raw = fs.readFileSync(f, 'utf8');
  const cn = (raw.match(/^class_name\s+([A-Za-z_]\w*)/m) || [])[1] || null;
  const rel = path.relative(SRC, f);
  fileInfo[f] = { rel, layer: layerOf(rel), className: cn, raw };
  if (cn) classToFile[cn] = f;
}
const allClassNames = new Set(Object.keys(classToFile));
const idOf = f => fileInfo[f].className || ('~' + fileInfo[f].rel.split(path.sep).join('/').replace(/\.gd$/, ''));

// ---- pass 2: dependency edges ----
const edges = new Map();
const addEdge = (a,b) => { if (a && b && a !== b) edges.set(a+' '+b, (edges.get(a+' '+b)||0)+1); };
for (const f of files) {
  const info = fileInfo[f], me = idOf(f), raw = info.raw;
  const ext = raw.match(/^extends\s+(?:"([^"]+)"|([A-Za-z_]\w*))/m);
  if (ext) {
    if (ext[2] && allClassNames.has(ext[2])) addEdge(me, ext[2]);
    else if (ext[1]) { const tf = resToFile(ext[1]); if (fileInfo[tf]) addEdge(me, idOf(tf)); }
  }
  let m, re = /(?:preload|load)\(\s*"([^"]+)"\s*\)/g;
  while ((m = re.exec(raw))) { const tf = resToFile(m[1]); if (fileInfo[tf]) addEdge(me, idOf(tf)); }
  const code = raw.replace(/#.*$/gm,'').replace(/"(?:[^"\\]|\\.)*"/g,'""').replace(/'(?:[^'\\]|\\.)*'/g,"''");
  const seen = new Set(); let im, ire = /\b([A-Z][A-Za-z0-9_]*)\b/g;
  while ((im = ire.exec(code))) { const id = im[1]; if (seen.has(id)) continue; seen.add(id);
    if (allClassNames.has(id) && id !== info.className) addEdge(me, id); }
}

// ---- tick-cadence rule ----
// CURATED allowlist: things that legitimately tick every frame and can't be told apart
// from violators by static text alone. Two kinds:
//   (a) the sanctioned tick DRIVERS — they ARE the controlled cadence / engine loop.
//   (b) projection / visual / input controllers — ticking is a side effect of projection.
// Edit this list if a classification is wrong.
const TICK_ALLOW = new Set([
  // (a) sanctioned drivers / cadence mechanism
  'GecsWorldController','WorldTimeController','AiSchedulerController','WorldSimulationController','PopulationRealizationController',
  // (b) projection / FX / input (projection-side)
  'WorldStatusController','WorldInteractionController','CharacterAppearanceController','BuildingVisibilityController',
  'DayNightLightingController','BleedSplotchController','LodRadiusOverlay','~player_controller','~move_command_indicator','~world_text_notice',
]);
const TICK_OK_LAYERS = new Set(['Projection','UI','Actors','Appearance/Nav','GECS·Components','GECS·Systems','GECS·Core','Bootstrap']);
const GATE_RE = /realiz|is_visible|\bvisible\b|_lod\b|in_view|within_view|on_screen|distance_to|\.distance|\bcamera\b|should_tick|should_process|_is_active\b|\b_near\b|_in_range|set_process\(\s*false|set_physics_process\(\s*false/i;
function funcBody(raw, fn) {
  const lines = raw.split('\n');
  const start = lines.findIndex(l => new RegExp('^func\\s+'+fn+'\\b').test(l));
  if (start < 0) return null;
  const body = [];
  for (let i = start+1; i < lines.length; i++) { const l = lines[i]; if (/^\S/.test(l) && l.trim() !== '') break; body.push(l); }
  return body.join('\n');
}
function tickViolation(info) {
  if (TICK_OK_LAYERS.has(info.layer)) return null;
  const raw = info.raw;
  if (/set_process(_internal)?\(\s*Engine\.is_editor_hint\(\)\s*\)/.test(raw)) return null; // editor-only process
  for (const fn of ['_process','_physics_process']) {
    const body = funcBody(raw, fn);
    if (body === null) continue;
    if (/if\s+not\s+Engine\.is_editor_hint\(\)[^\n]*:\s*\n\s*return/.test(body)) continue;   // returns at runtime → editor-only
    const runtimeReturns = /if\s+Engine\.is_editor_hint\(\)[^\n]*:\s*\n\s*return/.test(body); // returns in editor → runs at runtime
    if (/Engine\.is_editor_hint\(\)/.test(body) && !runtimeReturns) continue;                 // work only inside editor guard
    const work = body.split('\n').some(l => /[a-z_]+\(/.test(l) && !/is_editor_hint|^\s*return|^\s*#/.test(l));
    if (!work) continue;
    if (GATE_RE.test(body)) continue;                                                          // LOD/visibility gated
    return fn;
  }
  return null;
}

// ---- nodes / degrees ----
const nodes = {};
for (const f of files) nodes[idOf(f)] = { id: idOf(f), layer: fileInfo[f].layer, in:0, out:0, tick: (tickViolation(fileInfo[f]) && !TICK_ALLOW.has(idOf(f))) ? true : false, status: statusOf(f) };
const edgeList = [];
for (const [k,w] of edges) { const [a,b] = k.split(' '); if (!nodes[a] || !nodes[b]) continue; edgeList.push({source:a,target:b,w}); nodes[a].out++; nodes[b].in++; }

// ---- insights ----
const arr = Object.values(nodes);
const byIn  = [...arr].sort((x,y)=>y.in-x.in).slice(0,15);
const byOut = [...arr].sort((x,y)=>y.out-x.out).slice(0,15);
const layers = [...new Set(arr.map(n=>n.layer))];
const mat = {}; layers.forEach(l=>mat[l]={});
for (const e of edgeList) { const a=nodes[e.source].layer, b=nodes[e.target].layer; if(a!==b) mat[a][b]=(mat[a][b]||0)+1; }
const TRUTH = new Set(['GECS·Components','GECS·Systems','GECS·Core']);
const DOWN  = new Set(['Actors','Projection','UI','World-Content']);
const violations = edgeList.filter(e => TRUTH.has(nodes[e.source].layer) && DOWN.has(nodes[e.target].layer));
const tickViolators = arr.filter(n => n.tick);

function sccs() {
  let idx=0; const stack=[], on={}, index={}, low={}, out=[], adj={};
  arr.forEach(n=>adj[n.id]=[]); edgeList.forEach(e=>adj[e.source].push(e.target));
  function strong(v){ index[v]=low[v]=idx++; stack.push(v); on[v]=true;
    for(const w of adj[v]){ if(index[w]===undefined){strong(w);low[v]=Math.min(low[v],low[w]);} else if(on[w]) low[v]=Math.min(low[v],index[w]); }
    if(low[v]===index[v]){ const c=[]; let w; do{w=stack.pop();on[w]=false;c.push(w);}while(w!==v); if(c.length>1) out.push(c); } }
  for(const n of arr) if(index[n.id]===undefined) strong(n.id);
  return out;
}
const cycles = sccs();

// ---- report ----
console.log('FILES', files.length, ' NODES', arr.length, ' EDGES', edgeList.length);
console.log('GIT WORKING TREE:', arr.filter(n=>n.status==='new').length, 'new,', arr.filter(n=>n.status==='modified').length, 'modified');
console.log('\nTRUTH-RULE VIOLATIONS (GECS → live node):', violations.length);
violations.forEach(e=>console.log('  ', e.source, '→', e.target));
console.log('\nTICK-CADENCE VIOLATORS (ungated runtime _process in durable layer):', tickViolators.length);
tickViolators.forEach(n=>console.log('  ', n.id, '['+n.layer+']'));
console.log('\nDEPENDENCY CYCLES:', cycles.length);
cycles.sort((a,b)=>b.length-a.length).slice(0,8).forEach(c=>console.log('   ('+c.length+')', c.join(' → ')));

// ---- emit ----
const LCOL = {
  'GECS·Components':'#2f5fb3','GECS·Systems':'#4f86d6','GECS·Core':'#5566c4','Controllers':'#8a52cf',
  'Actors':'#c0504d','Projection':'#2f8f6b','AI':'#c1742d','World-Sim':'#9a7b22','World-Content':'#7a6a3b',
  'Items':'#b14b8a','UI':'#2f9a9a','Social/Jobs':'#4a9d4a','Appearance/Nav':'#6b7bd6','Bootstrap':'#9aa3b2','Resources':'#a0863c','Other':'#777' };
const compOf = {}; cycles.forEach((c,i)=>c.forEach(id=>compOf[id]=i));
const cycleNodes = new Set(Object.keys(compOf));
const violSet = new Set(violations.map(e=>e.source+' '+e.target));
const isCycleEdge = e => compOf[e.source]!==undefined && compOf[e.source]===compOf[e.target];
const outNodes = arr.map(n=>({ id:n.id, layer:n.layer, in:n.in, out:n.out, cycle:cycleNodes.has(n.id), tick:n.tick, status:n.status }));
const outLinks = edgeList.map(e=>({ source:e.source, target:e.target, w:e.w, violation:violSet.has(e.source+' '+e.target), cycle:isCycleEdge(e) }));
const layerList = [...new Set(arr.map(n=>n.layer))].map(name=>({ name, color:LCOL[name]||'#777' }));
const layerLinks = [];
for (const a of layers) for (const [b,c] of Object.entries(mat[a])) layerLinks.push({ source:a, target:b, w:c, violation:TRUTH.has(a)&&DOWN.has(b) });
const insights = {
  hubs: byIn.slice(0,12).map(n=>({id:n.id,layer:n.layer,deg:n.in})),
  coupled: byOut.slice(0,12).map(n=>({id:n.id,layer:n.layer,deg:n.out})),
  violations: violations.map(e=>({s:e.source,t:e.target})),
  tick: tickViolators.map(n=>({id:n.id,layer:n.layer})),
  cycles: cycles.sort((a,b)=>b.length-a.length),
  changed: { new: arr.filter(n=>n.status==='new').map(n=>n.id), modified: arr.filter(n=>n.status==='modified').map(n=>n.id) },
  totals: { files: files.length, nodes: arr.length, edges: edgeList.length },
};
fs.writeFileSync(path.join(__dirname,'graphdata.js'), 'window.GRAPH=' + JSON.stringify({ nodes:outNodes, links:outLinks, layers:layerList, layerLinks, insights }) + ';\n');
console.log('\nwrote', path.join(__dirname,'graphdata.js'));
