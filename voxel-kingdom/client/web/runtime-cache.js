/* Explicit caching for immutable Godot files, including self-signed test sites.
   Only public, same-origin, versioned WASM/PCK requests participate; never APIs. */
(() => {
  const originalFetch=window.fetch.bind(window), pending=new Set();
  const metrics={hits:0,misses:0,writes:0,failures:0};
  const track=promise=>{pending.add(promise);promise.finally(()=>pending.delete(promise));};
  window.voxelRuntimeCache={metrics,flush:()=>Promise.all([...pending])};
  window.fetch=async (input,init)=>{
    const url=new URL(input instanceof Request?input.url:String(input),location.href);
    const match=url.pathname.match(/^\/assets\/([a-f0-9]{20})\/index\.(wasm|pck)$/);
    if(url.origin!==location.origin||!match||(init?.method||input?.method||'GET').toUpperCase()!=='GET')return originalFetch(input,init);
    let cache;
    try{
      cache=await caches.open('voxel-runtime-'+match[1]);
      const stored=await cache.match(url.href);
      if(stored){metrics.hits++;return stored;}
    }catch{metrics.failures++;}
    metrics.misses++;
    const response=await originalFetch(input,init);
    if(cache&&response.ok){
      track(cache.put(url.href,response.clone()).then(async()=>{
        metrics.writes++;
        const versions=(await caches.keys()).filter(key=>key.startsWith('voxel-runtime-'));
        const old=versions.filter(key=>key!=='voxel-runtime-'+match[1]);
        for(const key of old.slice(0,Math.max(0,old.length-1)))await caches.delete(key);
      }).catch(()=>{metrics.failures++;}));
    }
    return response;
  };
})();
