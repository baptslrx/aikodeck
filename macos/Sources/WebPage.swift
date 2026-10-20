import AppKit

/// La télécommande affichée sur le téléphone (une seule page, sans rien installer).
enum WebPage {
    static func manifest(token: String) -> String {
        """
        {"name":"AikoDeck","short_name":"AikoDeck","start_url":"/?k=\(token)","display":"standalone",
         "background_color":"#0A0A0C","theme_color":"#0A0A0C","icons":[{"src":"/icon.png","sizes":"180x180","type":"image/png"}]}
        """
    }

    @MainActor static let iconPNG: Data = {
        let src = NSImage(named: NSImage.applicationIconName) ?? NSImage(size: NSSize(width: 180, height: 180))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(srgbRed: 0.04, green: 0.04, blue: 0.05, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 180, height: 180).fill()
        src.draw(in: NSRect(x: -14, y: -14, width: 208, height: 208))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }()

    static let html = #"""
    <!doctype html>
    <html lang="fr"><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
    <meta name="apple-mobile-web-app-title" content="AikoDeck">
    <link rel="apple-touch-icon" href="/icon.png">
    <title>AikoDeck</title>
    <style>
    :root{--bg:#0A0A0C;--surface:#17171A;--text:#F4F6F8;--sub:#9AA3AD;--accent:#7DC8FF;--accentText:#7DC8FF;--line:rgba(255,255,255,.09)}
    @media (prefers-color-scheme:light){:root{--bg:#FFFFFF;--surface:#F2F7FC;--text:#0B0D10;--sub:#5B6470;--accentText:#1F7FC8;--line:rgba(0,0,0,.08)}}
    *{box-sizing:border-box;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none}
    html,body{margin:0;height:100%;background:var(--bg);color:var(--text);font:15px/1.3 -apple-system,system-ui,sans-serif;touch-action:manipulation}
    body{padding:calc(env(safe-area-inset-top) + 10px) 14px calc(env(safe-area-inset-bottom) + 14px)}
    header{display:flex;align-items:center;gap:10px;margin:4px 2px 12px}
    header h1{font-size:19px;margin:0;font-weight:700}
    header .mac{color:var(--sub);font-size:13px;margin-left:auto;display:flex;align-items:center;gap:6px}
    .dot{width:8px;height:8px;border-radius:50%;background:#555}
    .dot.on{background:var(--accent);box-shadow:0 0 8px var(--accent)}
    nav{display:flex;gap:8px;overflow-x:auto;padding-bottom:10px;scrollbar-width:none}
    nav::-webkit-scrollbar{display:none}
    nav button{flex:none;border:1px solid var(--line);background:var(--surface);color:var(--sub);border-radius:999px;padding:8px 15px;font:600 14px -apple-system,system-ui}
    nav button.on{background:var(--accent);color:#05121C;border-color:var(--accent)}
    .grid{display:grid;grid-template-columns:repeat(3,1fr);gap:11px}
    @media (min-width:600px){.grid{grid-template-columns:repeat(5,1fr)}}
    @media (orientation:landscape) and (max-height:500px){.grid{grid-template-columns:repeat(6,1fr)}.key{aspect-ratio:1.25}}
    .key{position:relative;aspect-ratio:1;border-radius:20px;border:1.5px solid var(--c);background:color-mix(in srgb,var(--c) 18%,var(--surface));
      display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;padding:8px;transition:transform .08s,background .15s;color:var(--text)}
    .key .i{font-size:32px;line-height:1}
    .key .l{font-size:12px;font-weight:600;text-align:center;line-height:1.15;color:var(--text);opacity:.9}
    .key.down{transform:scale(.93);background:color-mix(in srgb,var(--c) 45%,var(--surface))}
    .key.ok::after,.key.err::after{content:"";position:absolute;inset:-2px;border-radius:21px;border:3px solid var(--f);animation:f .5s forwards}
    .key.ok{--f:#5FD39A}.key.err{--f:#FF6B6B}
    @keyframes f{from{opacity:1}to{opacity:0}}
    .msg{position:fixed;left:50%;bottom:calc(env(safe-area-inset-bottom) + 22px);transform:translateX(-50%);background:var(--surface);border:1px solid var(--accent);
      color:var(--text);padding:10px 16px;border-radius:999px;font-weight:600;font-size:14px;opacity:0;transition:opacity .2s;pointer-events:none;max-width:90vw;text-align:center}
    .msg.show{opacity:1}
    .empty{color:var(--sub);text-align:center;margin-top:30vh;padding:0 20px}
    </style></head><body>
    <header><h1>AikoDeck</h1><div class="mac"><span class="dot" id="dot"></span><span id="mac">…</span></div></header>
    <nav id="tabs"></nav>
    <main class="grid" id="grid"></main>
    <div class="empty" id="empty" hidden></div>
    <div class="msg" id="msg"></div>
    <script>
    const qs=new URLSearchParams(location.search);
    let key=qs.get('k')||localStorage.getItem('aikodeck-key')||'';
    if(qs.get('k'))localStorage.setItem('aikodeck-key',key);
    document.querySelector('link[rel=manifest]')||document.head.insertAdjacentHTML('beforeend','<link rel="manifest" href="/manifest.webmanifest?k='+encodeURIComponent(key)+'">');
    let decks=[],version=0,current=localStorage.getItem('aikodeck-deck')||'';
    const $=id=>document.getElementById(id);
    function toast(t){const m=$('msg');m.textContent=t;m.classList.add('show');clearTimeout(m._t);m._t=setTimeout(()=>m.classList.remove('show'),1800)}
    function empty(t){$('grid').innerHTML='';$('tabs').innerHTML='';$('empty').hidden=false;$('empty').textContent=t}
    async function api(path,opts={}){opts.headers=Object.assign({'X-Aiko-Key':key},opts.headers||{});const r=await fetch(path,opts);
      if(r.status===401){throw new Error('auth')}return r.json()}
    async function load(){
      if(!key){empty('Scanne le QR code affiché par AikoDeck sur ton Mac.');return}
      try{const d=await api('/api/decks');decks=d.decks;version=d.version;$('mac').textContent=d.mac;$('dot').classList.add('on');$('empty').hidden=true;
        if(!decks.find(x=>x.id===current))current=decks[0]?decks[0].id:'';render()}
      catch(e){$('dot').classList.remove('on');
        if(e.message==='auth')empty('Cette télécommande n\'est plus reconnue. Scanne à nouveau le QR code sur ton Mac.');
        else{$('mac').textContent='Mac injoignable';setTimeout(load,2000)}}
    }
    function render(){
      $('tabs').innerHTML='';decks.forEach(d=>{const b=document.createElement('button');b.textContent=d.name;b.className=d.id===current?'on':'';
        b.onclick=()=>{current=d.id;localStorage.setItem('aikodeck-deck',current);render()};$('tabs').appendChild(b)});
      const deck=decks.find(d=>d.id===current);const g=$('grid');g.innerHTML='';if(!deck)return;
      deck.buttons.forEach(b=>{const k=document.createElement('div');k.className='key';k.style.setProperty('--c',b.color||'#7DC8FF');
        k.innerHTML='<div class="i"></div><div class="l"></div>';k.querySelector('.i').textContent=b.icon||'•';k.querySelector('.l').textContent=b.label;
        k.addEventListener('pointerdown',e=>{e.preventDefault();k.classList.add('down');press(deck.id,b,k)});
        ['pointerup','pointerleave','pointercancel'].forEach(t=>k.addEventListener(t,()=>k.classList.remove('down')));
        g.appendChild(k)});
    }
    async function press(deckId,b,el){
      if(navigator.vibrate)navigator.vibrate(12);
      el.classList.remove('ok','err');void el.offsetWidth;
      try{const r=await api('/api/press',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({deck:deckId,button:b.id})});
        el.classList.add(r.ok?'ok':'err');if(!r.ok)toast(r.error||'Erreur')}
      catch(e){el.classList.add('err');toast(e.message==='auth'?'Scanne à nouveau le QR code':'Mac injoignable');$('dot').classList.remove('on')}
    }
    setInterval(async()=>{if(!key||document.hidden)return;try{const v=await api('/api/version');$('dot').classList.add('on');
      if(v.version!==version)load()}catch(e){$('dot').classList.remove('on')}},2000);
    document.addEventListener('visibilitychange',()=>{if(!document.hidden)load()});
    load();
    </script></body></html>
    """#
}
