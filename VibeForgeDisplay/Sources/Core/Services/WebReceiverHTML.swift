import Foundation

/// The HTML served to browser-based receivers (smart TVs, phones, sticks with a browser).
/// Apple devices play HLS natively via <video>; other browsers fall back to hls.js.
/// This is embedded (not bundle-loaded) so the server has no filesystem dependency.
///
/// Access control: every data request carries the session token in the path
/// (/t/<token>/...). The token arrives in the deep link / QR the Mac generates.
/// Stream names are inserted with textContent (never innerHTML) to avoid any
/// DOM-injection from route names.
enum WebReceiver {
    static let html = ##"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; media-src 'self'; img-src 'self' data:; style-src 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; connect-src 'self'">
<title>VibeForge Display — Receiver</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; background: #0a0a0d; color: #eee;
    font-family: -apple-system, system-ui, Segoe UI, Roboto, sans-serif; }
  #stage { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center; background: #000; }
  video { width: 100%; height: 100%; object-fit: contain; background: #000; }
  #picker { padding: 6vh 6vw; }
  h1 { font-weight: 600; font-size: clamp(20px, 3vw, 34px); margin: 0 0 4px; }
  p.sub { color: #8a8a92; margin: 0 0 4vh; font-size: clamp(13px, 1.6vw, 18px); }
  a.tile { display: block; text-decoration: none; color: #eee; background: #15151a;
    border: 1px solid #26262c; border-radius: 14px; padding: 20px 22px; margin: 0 0 14px;
    font-size: clamp(16px, 2vw, 22px); transition: background .15s, border-color .15s; }
  a.tile:hover, a.tile:focus { background: #1c1c24; border-color: #5a8cff; outline: none; }
  .dot { display:inline-block; width:9px; height:9px; border-radius:50%; background:#4cc072; margin-right:10px; }
  #status { position: fixed; left: 0; right: 0; bottom: 0; text-align: center;
    color: #8a8a92; font-size: 13px; padding: 10px; pointer-events: none; }
  .err { color: #e05a5f; }
</style>
</head>
<body>
<div id="stage" style="display:none"><video id="v" autoplay playsinline muted controls></video></div>
<div id="picker">
  <h1>VibeForge Display</h1>
  <p class="sub" id="subtitle">Choose a screen to show on this TV.</p>
  <div id="list"></div>
</div>
<div id="status"></div>
<script>
  const qs = new URLSearchParams(location.search);
  const token = qs.get('t') || '';
  const key = qs.get('s');
  const statusEl = document.getElementById('status');
  const setStatus = (t, isErr) => { statusEl.textContent = t || ''; statusEl.className = isErr ? 'err' : ''; };
  // All data endpoints are token-gated. Build paths with the token from the link.
  const api = (p) => '/t/' + encodeURIComponent(token) + p;

  if (!token) {
    document.getElementById('subtitle').textContent =
      'Open the link (or scan the QR) generated on the Mac — it includes a one-time access code.';
    document.getElementById('list').textContent = '';
  }

  async function showPicker() {
    if (!token) return;
    try {
      const res = await fetch(api('/streams.json'), { cache: 'no-store' });
      if (!res.ok) { setTimeout(showPicker, 2000); return; }
      const streams = await res.json();
      const list = document.getElementById('list');
      if (!streams.length) { list.textContent = 'No active streams yet. Start one on the Mac.'; setTimeout(showPicker, 2000); return; }
      list.textContent = '';
      for (const s of streams) {
        const a = document.createElement('a');
        a.className = 'tile';
        a.href = '/?t=' + encodeURIComponent(token) + '&s=' + encodeURIComponent(s.key);
        const dot = document.createElement('span');
        dot.className = 'dot';
        a.appendChild(dot);
        // textContent — never innerHTML — so a route name cannot inject markup.
        a.appendChild(document.createTextNode(s.name || s.key));
        list.appendChild(a);
      }
    } catch (e) { setTimeout(showPicker, 2000); }
  }

  function play(streamKey) {
    document.getElementById('picker').style.display = 'none';
    document.getElementById('stage').style.display = 'flex';
    const v = document.getElementById('v');
    const src = api('/s/' + encodeURIComponent(streamKey) + '/media.m3u8');
    setStatus('Connecting…');
    v.addEventListener('playing', () => setStatus(''));
    v.addEventListener('waiting', () => setStatus('Buffering…'));

    if (v.canPlayType('application/vnd.apple.mpegurl')) {
      v.src = src;
      v.play().catch(() => setStatus('Tap to start playback'));
      return;
    }
    // Fallback for browsers without native HLS (Android/Fire TV/Chrome).
    // Loaded cross-origin with no referrer. For untrusted receiver networks,
    // pin an SRI hash or self-host this file.
    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.13/dist/hls.min.js';
    script.crossOrigin = 'anonymous';
    script.referrerPolicy = 'no-referrer';
    script.onload = () => {
      if (window.Hls && window.Hls.isSupported()) {
        const hls = new window.Hls({ lowLatencyMode: true, liveSyncDurationCount: 2, maxLiveSyncPlaybackRate: 1.5 });
        hls.loadSource(src);
        hls.attachMedia(v);
        hls.on(window.Hls.Events.ERROR, (_, d) => { if (d.fatal) setStatus('Stream error — retrying…', true); });
      } else { setStatus('This browser cannot play the stream.', true); }
    };
    script.onerror = () => setStatus('Could not load player (no internet on this device?).', true);
    document.head.appendChild(script);
  }

  if (key && token) play(key); else showPicker();
</script>
</body>
</html>
"""##
}
