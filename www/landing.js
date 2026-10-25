// www/landing.js - intro sequence, starfield, 3D topic carousel and the
// buttons that take the user from the landing page into the dashboard.
(function () {
  var L = document.getElementById('landing');
  if (!L) return;
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.body.style.overflow = 'hidden';

  // ---- starfield: each layer is one 1px div whose stars are a box-shadow list
  function stars(id, n, blur, a0, a1) {
    var out = [];
    for (var i = 0; i < n; i++) {
      out.push((Math.random() * 100).toFixed(2) + 'vw ' + (Math.random() * 100).toFixed(2) + 'vh ' +
               blur + 'px 0 rgba(255,255,255,' + (a0 + Math.random() * (a1 - a0)).toFixed(2) + ')');
    }
    document.getElementById(id).style.boxShadow = out.join(',');
  }
  stars('ldStarsA', 150, 0, 0.05, 0.30);
  stars('ldStarsB', 18, 1.2, 0.35, 0.70);

  // ---- build the topic cards (10 topics repeated around the ring)
  var topics = window.LANDING_TOPICS || [];
  var ring = document.getElementById('ldRing');
  var HUES = [200, 350, 265, 10, 45, 30, 180, 320, 220, 140];
  var N = 30, STEP = 360 / N, CULL = 46, SPEED = 4.5;   // deg, deg, deg/s
  var cards = [];
  function esc(s) { return String(s).replace(/[&<>"]/g, function (c) {
    return {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'}[c]; }); }
  for (var i = 0; i < N && topics.length; i++) {
    var t = topics[i % topics.length];
    var pos = t.pct >= 50;
    var el = document.createElement('div');
    el.className = 'ld-card';
    el.style.setProperty('--h', HUES[i % topics.length]);
    el.innerHTML =
      '<small>Topic ' + ((i % topics.length) + 1) + '</small>' +
      '<h3>' + esc(t.label) + '</h3>' +
      '<div class="w">' + t.words.map(function (w) { return '<span>' + esc(w) + '</span>'; }).join('') + '</div>' +
      '<div class="pct"><b>' + t.pct + '%</b>positive reviews' +
      '<div class="bar"><i style="width:' + t.pct + '%;background:' + (pos ? '#3fe3ff' : '#ff6b7a') + '"></i></div></div>';
    ring.appendChild(el);
    cards.push(el);
  }

  // ---- ring geometry. The camera sits AT the centre of the cylinder
  // (perspective = R), so a card at angle a is placed at
  // (R sin a, 0, R(1 - cos a)) and turned by -a: it stays tangent to the
  // cylinder and faces the camera, and the slanted top edges are perspective.
  var R = 900, cw = 170, ch = 220, phase = -6, last = 0, running = true;
  function size() {
    var w = window.innerWidth, h = window.innerHeight;
    var phone = w <= 700;
    ch = Math.max(140, Math.min(240, h * (phone ? 0.22 : 0.26)));
    cw = ch * 0.78;
    // arc spacing between neighbours is about R * sin(STEP), so R must keep that
    // wider than a card or the cards overlap (matters most on narrow phones)
    R = Math.max(cw * 1.15 / Math.sin(STEP * Math.PI / 180), w * (phone ? 1.25 : 0.72));
    ring.style.perspective = R + 'px';
    ring.style.perspectiveOrigin = '50% 70%';
    ring.style.setProperty('--cw', cw + 'px');
    ring.style.setProperty('--ch', ch + 'px');
  }
  function place() {
    for (var i = 0; i < cards.length; i++) {
      var a = ((i * STEP + phase) % 360 + 540) % 360 - 180;   // signed angle -180..180
      var el = cards[i];
      if (Math.abs(a) > CULL) { el.style.visibility = 'hidden'; continue; }
      el.style.visibility = 'visible';
      var r = a * Math.PI / 180, c = Math.cos(r);
      el.style.transform = 'translate3d(' + (R * Math.sin(r)).toFixed(2) + 'px,0,' +
                           (R * (1 - c)).toFixed(2) + 'px) rotateY(' + (-a).toFixed(3) + 'deg)';
      el.style.filter = 'brightness(' + (1 - 1.6 * (1 - c)).toFixed(3) + ')';   // edges dim (0.5 at the cull angle)
    }
  }
  function tick(t) {
    if (!running) return;
    var dt = last ? Math.min((t - last) / 1000, 0.1) : 0;
    last = t;
    if (!reduce) phase -= SPEED * dt;
    place();
    requestAnimationFrame(tick);
  }
  size(); place();
  window.addEventListener('resize', function () { size(); place(); });
  document.addEventListener('visibilitychange', function () { last = 0; });
  requestAnimationFrame(tick);

  // ---- intro timeline: logo pop -> tagline -> audience line -> hero + carousel
  function finishIntro() {
    L.classList.remove('intro-playing');
    L.classList.add('intro-done');
  }
  var introTimer = setTimeout(finishIntro, reduce ? 0 : 3300);
  document.getElementById('ldSkip').addEventListener('click', function () {
    clearTimeout(introTimer); finishIntro();
  });

  // ---- leave the landing page for a dashboard tab
  function go(tab) {
    var link = document.querySelector('a[data-value="' + tab + '"]');
    if (link) link.click();
    L.classList.add('leaving');
    document.body.style.overflow = '';
    setTimeout(function () { running = false; L.style.display = 'none'; }, 560);
  }
  function bind(id, tab) {
    document.getElementById(id).addEventListener('click', function (e) { e.preventDefault(); go(tab); });
  }
  bind('ldTryReview', 'Predict a review');
  bind('ldTryMovie', 'Predict a movie');

  // re-open from the navbar's Home link (no intro replay)
  window.showLanding = function () {
    clearTimeout(introTimer);
    L.style.display = '';
    finishIntro();
    document.body.style.overflow = 'hidden';
    requestAnimationFrame(function () { L.classList.remove('leaving'); });
    if (!running) { running = true; last = 0; requestAnimationFrame(tick); }
  };
})();
