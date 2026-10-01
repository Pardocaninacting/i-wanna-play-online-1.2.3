// IWPO globe: a lat/long wireframe earth driven by the live lobby state. The main
// server is the one hub light; each online player is a light running an orbit band
// and jumping with the I wanna kid's physics; active rooms are pulse beams rising
// off the hub. Nobody online -> the grid alone keeps turning.
//
// Data enters through window.IWPO_GLOBE.setState({ players, rooms }); everything
// re-tunes smoothly on the next frames. No player geography is known or wanted.
import * as THREE from '../vendor/three.module.min.js';

const canvas = document.querySelector('#globe-stage');
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const compactViewport = window.matchMedia('(max-width: 759px)');

const STEEL = new THREE.Color(0x5aa0e8);
const DEEP = new THREE.Color(0x3f7fbf);
const CAPE = new THREE.Color(0xd64545);
const WARM = new THREE.Color(0xffe9c8);

if (canvas) {
  try {
    const renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: !reduceMotion && !compactViewport.matches,
      powerPreference: compactViewport.matches ? 'low-power' : 'high-performance',
    });
    renderer.setClearColor(0x000000, 0);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, reduceMotion || compactViewport.matches ? 1 : 1.6));
    renderer.autoClear = true;

    const assetUrl = (path) => new URL(path, import.meta.url).href;
    const GLOBE_RADIUS = 1.24;

    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(32, 1, 0.1, 120);
    // Frame budget: visible half-height = tan(fov/2) * camera.z ≈ 1.75 world units.
    // Everything drawn (orbits, room beams, hub) must stay inside that radius,
    // otherwise the pulses get sliced off at the canvas edge.
    camera.position.set(0, 0, 6.1);

    const rig = new THREE.Group();
    scene.add(rig);
    // Earth's axis leans ~23.4°; the spin below runs inside this tilted frame,
    // so the globe turns about a slanted axis instead of straight up.
    // Negative Z leans the north pole to the right (the conventional look).
    const planetTilt = new THREE.Group();
    planetTilt.rotation.z = -THREE.MathUtils.degToRad(23.4);
    rig.add(planetTilt);
    const planet = new THREE.Group();
    planetTilt.add(planet);

    // north up, east right (z inverted or the landmasses mirror)
    function latLonToVec3(latDeg, lonDeg, radius) {
      const lat = (latDeg * Math.PI) / 180;
      const lon = (lonDeg * Math.PI) / 180;
      return new THREE.Vector3(
        radius * Math.cos(lat) * Math.cos(lon),
        radius * Math.sin(lat),
        radius * Math.cos(lat) * -Math.sin(lon),
      );
    }

    function makeGlowTexture(inner, outer) {
      const size = 128;
      const glowCanvas = document.createElement('canvas');
      glowCanvas.width = size;
      glowCanvas.height = size;
      const context = glowCanvas.getContext('2d');
      const gradient = context.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
      gradient.addColorStop(0, inner);
      gradient.addColorStop(0.25, outer);
      gradient.addColorStop(1, 'rgba(0, 0, 0, 0)');
      context.fillStyle = gradient;
      context.fillRect(0, 0, size, size);
      const texture = new THREE.CanvasTexture(glowCanvas);
      texture.colorSpace = THREE.SRGBColorSpace;
      texture.generateMipmaps = false;
      texture.minFilter = THREE.LinearFilter;
      texture.magFilter = THREE.LinearFilter;
      return texture;
    }

    const glowTexture = makeGlowTexture('rgba(255, 255, 255, 1)', 'rgba(160, 220, 255, 0.45)');
    const dotTexture = makeGlowTexture('rgba(255, 255, 255, 1)', 'rgba(255, 255, 255, 0.3)');

    // occluder: hides the back side of the wireframe and the dot matrix
    planet.add(new THREE.Mesh(
      new THREE.SphereGeometry(GLOBE_RADIUS - 0.02, 64, 64),
      new THREE.MeshBasicMaterial({ color: 0x0a0f1a }),
    ));

    // lat/long wireframe
    {
      const linePositions = [];
      const segments = 96;
      for (let lat = -75; lat <= 75; lat += 15) {
        for (let step = 0; step < segments; step += 1) {
          const from = (step / segments) * 360 - 180;
          const to = ((step + 1) / segments) * 360 - 180;
          linePositions.push(latLonToVec3(lat, from, GLOBE_RADIUS), latLonToVec3(lat, to, GLOBE_RADIUS));
        }
      }
      for (let lon = -180; lon < 180; lon += 15) {
        for (let step = 0; step < segments; step += 1) {
          const from = (step / segments) * 180 - 90;
          const to = ((step + 1) / segments) * 180 - 90;
          linePositions.push(latLonToVec3(from, lon, GLOBE_RADIUS), latLonToVec3(to, lon, GLOBE_RADIUS));
        }
      }
      const geometry = new THREE.BufferGeometry().setFromPoints(linePositions);
      planet.add(new THREE.LineSegments(
        geometry,
        new THREE.LineBasicMaterial({
          color: 0x3f7fbf, transparent: true, opacity: 0.42,
          blending: THREE.AdditiveBlending, depthWrite: false,
        }),
      ));
    }

    // land dot matrix, sampled off a Natural Earth land mask (_dev/make-land-mask.cjs)
    {
      const image = new Image();
      image.onload = () => {
        try {
          const sampleCanvas = document.createElement('canvas');
          sampleCanvas.width = image.naturalWidth;
          sampleCanvas.height = image.naturalHeight;
          const context = sampleCanvas.getContext('2d', { willReadFrequently: true });
          context.drawImage(image, 0, 0);
          const pixels = context.getImageData(0, 0, sampleCanvas.width, sampleCanvas.height).data;
          const positions = [];
          const colors = [];
          const step = Math.max(2, Math.round(sampleCanvas.width / 480));
          for (let y = 0; y < sampleCanvas.height; y += step) {
            const v = y / sampleCanvas.height;
            const latDeg = 90 - v * 180;
            const rowSamples = Math.max(1, Math.round(Math.cos((latDeg * Math.PI) / 180) * (sampleCanvas.width / step)));
            const xStep = Math.max(step, Math.round(sampleCanvas.width / Math.max(rowSamples, 1) / 1.6));
            for (let x = 0; x < sampleCanvas.width; x += xStep) {
              if (pixels[(y * sampleCanvas.width + x) * 4] < 128) continue;
              const lonDeg = (x / sampleCanvas.width) * 360 - 180;
              const point = latLonToVec3(latDeg, lonDeg, GLOBE_RADIUS + 0.005);
              positions.push(point.x, point.y, point.z);
              const tint = 0.62 + Math.random() * 0.5;
              colors.push(STEEL.r * tint, STEEL.g * tint, STEEL.b * tint);
            }
          }
          const geometry = new THREE.BufferGeometry();
          geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions), 3));
          geometry.setAttribute('color', new THREE.BufferAttribute(new Float32Array(colors), 3));
          planet.add(new THREE.Points(
            geometry,
            new THREE.PointsMaterial({
              size: 0.042, map: dotTexture, vertexColors: true, transparent: true,
              opacity: 1, blending: THREE.AdditiveBlending, depthWrite: false,
            }),
          ));
          if (reduceMotion) renderer.render(scene, camera);
        } catch (samplingError) {
          console.warn('[globe] land sampling failed', samplingError);
        }
      };
      image.src = assetUrl('../img/land-mask.png');
    }

    // fresnel rim
    planet.add(new THREE.Mesh(
      new THREE.SphereGeometry(GLOBE_RADIUS * 1.09, 64, 64),
      new THREE.ShaderMaterial({
        side: THREE.BackSide,
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
        uniforms: {
          uA: { value: new THREE.Color(0x5aa0e8) },
          uB: { value: new THREE.Color(0x3f7fbf) },
        },
        vertexShader: `
          varying vec3 vNormal;
          void main() {
            vNormal = normalize(normalMatrix * normal);
            gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
          }
        `,
        fragmentShader: `
          varying vec3 vNormal;
          uniform vec3 uA;
          uniform vec3 uB;
          void main() {
            float intensity = pow(0.62 - dot(vNormal, vec3(0.0, 0.0, 1.0)), 3.2);
            vec3 glow = mix(uA, uB, vNormal.y * 0.5 + 0.5);
            gl_FragColor = vec4(glow, 1.0) * intensity * 0.9;
          }
        `,
      }),
    ));

    // ---- the hub: the main server, one light ----
    const HUB = [31, 121];
    const hubNormal = latLonToVec3(HUB[0], HUB[1], 1).normalize();
    const hubSurface = hubNormal.clone().multiplyScalar(GLOBE_RADIUS + 0.012);
    const hubSprite = new THREE.Sprite(new THREE.SpriteMaterial({
      map: glowTexture, color: CAPE, transparent: true, opacity: 0.95,
      blending: THREE.AdditiveBlending, depthWrite: false,
    }));
    hubSprite.position.copy(hubSurface);
    hubSprite.scale.setScalar(0.18);
    planet.add(hubSprite);

    const hubRing = new THREE.Mesh(
      new THREE.RingGeometry(0.05, 0.062, 40),
      new THREE.MeshBasicMaterial({
        color: 0xd64545, transparent: true, opacity: 0.7,
        blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
      }),
    );
    hubRing.position.copy(hubSurface);
    hubRing.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), hubNormal);
    planet.add(hubRing);

    // ---- pulse lines with a moving head (shared shader) ----
    const flowVertexShader = `
      attribute float aU;
      varying float vU;
      void main() {
        vU = aU;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `;
    const flowFragmentShader = `
      varying float vU;
      uniform float uTime;
      uniform vec3 uColor;
      uniform float uSpeed;
      uniform float uBase;
      void main() {
        float head = fract(vU * 2.0 - uTime * uSpeed);
        float pulse = smoothstep(0.0, 0.1, head) * smoothstep(0.42, 0.16, head);
        float alpha = uBase + pulse * 0.85;
        gl_FragColor = vec4(uColor, alpha);
      }
    `;

    function makeFlowLine(points, color, { base = 0.12, speed = 0.24, closed = false } = {}) {
      const geometry = new THREE.BufferGeometry().setFromPoints(points);
      const count = points.length;
      const us = new Float32Array(count);
      const denominator = closed ? count : count - 1;
      for (let index = 0; index < count; index += 1) us[index] = index / denominator;
      geometry.setAttribute('aU', new THREE.BufferAttribute(us, 1));
      const material = new THREE.ShaderMaterial({
        vertexShader: flowVertexShader,
        fragmentShader: flowFragmentShader,
        uniforms: {
          uTime: { value: 0 },
          uColor: { value: new THREE.Color(color) },
          uSpeed: { value: speed },
          uBase: { value: base },
        },
        transparent: true,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      });
      const line = closed
        ? new THREE.LineLoop(geometry, material)
        : new THREE.Line(geometry, material);
      return { line, material };
    }

    // ---- two orbit bands: the tracks the online players run on ----
    function createOrbit(radiusX, radiusY, tilt, color, speed) {
      const orbit = new THREE.Group();
      orbit.rotation.set(tilt, 0.22, -0.18);
      const points = [];
      const segments = 160;
      for (let index = 0; index <= segments; index += 1) {
        const angle = (index / segments) * Math.PI * 2;
        points.push(new THREE.Vector3(Math.cos(angle) * radiusX, Math.sin(angle) * radiusY, 0));
      }
      const { line, material } = makeFlowLine(points, color, { base: 0.08, speed, closed: true });
      orbit.add(line);
      rig.add(orbit);
      return { orbit, radiusX, radiusY, material };
    }

    const orbitConfigs = [
      { radiusX: 1.60, radiusY: 0.60, tilt: 0.42, color: 0x5aa0e8, speed: 0.22 },
      { radiusX: 1.78, radiusY: 0.50, tilt: 1.06, color: 0x3f7fbf, speed: 0.16 },
    ];
    const orbits = orbitConfigs.map((c) => createOrbit(c.radiusX, c.radiusY, c.tilt, c.color, c.speed));

    // ---- online players: lights that run the bands and jump like the kid ----
    // The I wanna engine's own numbers (50 fps; jump 8.5, double jump 7, gravity 0.4,
    // early release x0.45, fall cap 9, run 3 px/frame): no sprite is drawn, the hop
    // rhythm alone is the genre's signature. The red trail is the cape.
    const KID = { jump: 8.5, djump: 7, gravity: 0.4, release: 0.45, maxFall: 9, run: 3 };
    const GAME_FRAME = 1 / 50;
    const PX = 0.002;           // world units per game pixel: a full double jump ~0.31
    const TRAIL_POINTS = 24;    // one sample every 2 game frames, ~1 s of history
    const randInt = (lo, hi) => lo + Math.floor(Math.random() * (hi - lo + 1));

    const trailShade = new Float32Array(TRAIL_POINTS * 3);
    for (let p = 0; p < TRAIL_POINTS; p += 1) {
      const fade = Math.pow(p / (TRAIL_POINTS - 1), 1.6) * 0.85;
      trailShade[p * 3] = CAPE.r * fade;
      trailShade[p * 3 + 1] = CAPE.g * fade;
      trailShade[p * 3 + 2] = CAPE.b * fade;
    }

    function bandPoint(band, theta, lift, out) {
      const c = Math.cos(theta);
      const s = Math.sin(theta);
      // outward normal of the ellipse, in the band's own plane
      let nx = c / band.radiusX;
      let ny = s / band.radiusY;
      const length = Math.hypot(nx, ny) || 1;
      nx /= length;
      ny /= length;
      out.x = c * band.radiusX + nx * lift;
      out.y = s * band.radiusY + ny * lift;
      out.nx = nx;
      out.ny = ny;
      return out;
    }

    const MAX_PLAYER_LIGHTS = 24;
    const jumpers = [];
    for (let i = 0; i < MAX_PLAYER_LIGHTS; i += 1) {
      const bandIndex = i % orbits.length;
      const band = orbits[bandIndex];
      const sprite = new THREE.Sprite(new THREE.SpriteMaterial({
        map: glowTexture, color: WARM, transparent: true, opacity: 0,
        blending: THREE.AdditiveBlending, depthWrite: false,
      }));
      sprite.scale.setScalar(0.1);
      sprite.visible = false;
      band.orbit.add(sprite);   // band space: (x, y, 0), the group's tilt does the rest

      const k = {
        sprite, band,
        theta: (Math.floor(i / orbits.length) / (MAX_PLAYER_LIGHTS / orbits.length)) * Math.PI * 2
          + bandIndex * 0.9 + Math.random() * 0.3,
        dir: bandIndex === 0 ? 1 : -1,
        h: 0, vs: 0, air: false, canDjump: false, hold: 0, djumpAt: -1,
        wait: randInt(10, 120), tick: 0, wake: 0, presence: 0,
        x: 0, y: 0, nx: 0, ny: 1,
        history: new Float32Array(TRAIL_POINTS * 3),
      };
      bandPoint(band, k.theta, 0, k);
      for (let p = 0; p < TRAIL_POINTS; p += 1) {
        k.history[p * 3] = k.x;
        k.history[p * 3 + 1] = k.y;
      }
      const trailGeometry = new THREE.BufferGeometry();
      trailGeometry.setAttribute('position', new THREE.BufferAttribute(k.history, 3));
      trailGeometry.setAttribute('color', new THREE.BufferAttribute(trailShade, 3));
      k.trail = new THREE.Line(trailGeometry, new THREE.LineBasicMaterial({
        vertexColors: true, transparent: true, opacity: 0,
        blending: THREE.AdditiveBlending, depthWrite: false,
      }));
      k.trail.frustumCulled = false;
      k.trail.visible = false;
      band.orbit.add(k.trail);
      jumpers.push(k);
    }

    function stepJumper(k) {
      const sin = Math.sin(k.theta);
      const cos = Math.cos(k.theta);
      // constant ground speed along the ellipse, not constant angle
      const stretch = Math.hypot(k.band.radiusX * sin, k.band.radiusY * cos) || 1;
      k.theta += (k.dir * KID.run * PX) / stretch;

      if (k.air) {
        if (k.hold > 0) {
          k.hold -= 1;
          if (k.hold === 0 && k.vs > 0) k.vs *= KID.release;
        }
        if (k.djumpAt > 0) {
          k.djumpAt -= 1;
          if (k.djumpAt === 0 && k.canDjump) {
            k.vs = KID.djump;
            k.canDjump = false;
            k.hold = randInt(4, 20);
            k.wake = 0.7;
          }
        }
        k.h += k.vs;
        k.vs = Math.max(k.vs - KID.gravity, -KID.maxFall);
        if (k.h <= 0) {
          k.h = 0;
          k.vs = 0;
          k.air = false;
          k.wait = randInt(8, 90);
        }
      } else {
        k.wait -= 1;
        if (k.wait <= 0) {
          k.air = true;
          k.vs = KID.jump;
          k.canDjump = true;
          k.hold = randInt(3, 26);
          k.djumpAt = Math.random() < 0.6 ? randInt(8, 30) : -1;
          k.wake = 1;
        }
      }

      bandPoint(k.band, k.theta, k.h * PX, k);
      k.tick = (k.tick + 1) % 2;
      if (k.tick === 0) {
        k.history.copyWithin(0, 3);
        const last = (TRAIL_POINTS - 1) * 3;
        k.history[last] = k.x;
        k.history[last + 1] = k.y;
      }
    }

    // a jump pushes the background fluid: fluid.js listens for iwpo:wake
    const wakePoint = new THREE.Vector3();
    const wakeTip = new THREE.Vector3();
    const globeCenter = new THREE.Vector3();
    let lastWakeAt = 0;
    function emitWake(k, strength) {
      const now = performance.now();
      if (now - lastWakeAt < 220) return;
      wakePoint.set(k.x, k.y, 0);
      k.band.orbit.localToWorld(wakePoint);
      rig.getWorldPosition(globeCenter);
      if (wakePoint.z < globeCenter.z) return;   // far half of the band: the globe hides it
      wakeTip.set(k.x + k.nx * 0.2, k.y + k.ny * 0.2, 0);
      k.band.orbit.localToWorld(wakeTip);
      wakePoint.project(camera);
      wakeTip.project(camera);
      const rect = canvas.getBoundingClientRect();
      const ux = (wakeTip.x - wakePoint.x) * rect.width;
      const uy = -(wakeTip.y - wakePoint.y) * rect.height;
      const length = Math.hypot(ux, uy) || 1;
      lastWakeAt = now;
      window.dispatchEvent(new CustomEvent('iwpo:wake', {
        detail: {
          x: rect.left + (wakePoint.x + 1) * 0.5 * rect.width,
          y: rect.top + (1 - wakePoint.y) * 0.5 * rect.height,
          ux: ux / length,
          uy: uy / length,
          strength,
        },
      }));
    }

    function updateJumpers(snap) {
      for (let i = 0; i < jumpers.length; i += 1) {
        const k = jumpers[i];
        const want = i < shownPlayers ? 1 : 0;
        k.presence = snap ? want : k.presence + (want - k.presence) * 0.08;
        const visible = k.presence > 0.01;
        k.sprite.visible = visible;
        k.trail.visible = visible && !reduceMotion;
        if (!visible) continue;
        k.sprite.material.opacity = 0.95 * k.presence;
        k.sprite.position.set(k.x, k.y, 0);
        k.trail.material.opacity = k.presence;
        k.trail.geometry.attributes.position.needsUpdate = true;
        if (k.wake > 0) {
          emitWake(k, k.wake);
          k.wake = 0;
        }
      }
    }

    // ---- room beams: a short vertical pulse rising off the hub area ----
    const MAX_ROOM_BEAMS = 8;
    const roomBeams = [];
    for (let i = 0; i < MAX_ROOM_BEAMS; i += 1) {
      // jittered a few degrees around the hub so multiple rooms fan out
      const jitLat = HUB[0] + ((i % 3) - 1) * 4;
      const jitLon = HUB[1] + (Math.floor(i / 3) - 1) * 5;
      const base = latLonToVec3(jitLat, jitLon, GLOBE_RADIUS + 0.02);
      const top = latLonToVec3(jitLat, jitLon, GLOBE_RADIUS + 0.40);
      const points = [];
      const segments = 24;
      for (let step = 0; step <= segments; step += 1) {
        points.push(base.clone().lerp(top, step / segments));
      }
      const { line, material } = makeFlowLine(points, 0xd64545, { base: 0, speed: 0.5 + i * 0.07 });
      line.visible = false;
      planet.add(line);   // planet space: the beam rotates with the hub, always attached
      roomBeams.push({ line, material });
    }

    // ---- live state ----
    let targetPlayers = 0;
    let targetRooms = 0;
    let shownPlayers = 0;
    let shownRooms = 0;

    window.IWPO_GLOBE = {
      setState({ players, rooms }) {
        targetPlayers = Math.max(0, Math.min(MAX_PLAYER_LIGHTS, players | 0));
        targetRooms = Math.max(0, Math.min(MAX_ROOM_BEAMS, rooms | 0));
        if (reduceMotion) renderStill();
      },
    };

    // ---- interaction & layout ----
    const pointerTarget = new THREE.Vector2();
    const pointer = new THREE.Vector2();
    window.addEventListener('pointermove', (event) => {
      pointerTarget.x = (event.clientX / Math.max(window.innerWidth, 1) - 0.5) * 2;
      pointerTarget.y = (event.clientY / Math.max(window.innerHeight, 1) - 0.5) * -2;
    }, { passive: true });

    let rendererWidth = 0;
    let rendererHeight = 0;

    function textRightEdge(selector) {
      const element = document.querySelector(selector);
      if (!element) return 0;
      const range = document.createRange();
      range.selectNodeContents(element);
      let right = 0;
      for (const rect of range.getClientRects()) right = Math.max(right, rect.right);
      return right;
    }

    // Wide screens: the bands (plus a double jump of headroom) start right of the
    // hero copy, so nothing crosses the headline. The globe stays on the camera
    // axis and the lens is shifted instead: moving it off-axis would stretch the
    // sphere into an ellipse under the wide horizontal FOV.
    const BAND_REACH = 1.78 + 0.32;
    const GLOBE_RIM = GLOBE_RADIUS * 1.09;
    function placeRig(width, height) {
      rig.position.set(0, 0, 0);
      if (width < 760) {
        camera.clearViewOffset();
        rig.position.set(0, 0.1, 0);
        rig.scale.setScalar(0.8);
        return;
      }
      const halfHeight = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * camera.position.z;
      const unit = (height / 2) / halfHeight;   // px per world unit at the globe's depth
      const left = canvas.getBoundingClientRect().left;
      const copyRight = Math.max(
        textRightEdge('.hero h1'), textRightEdge('.hero__lead'), textRightEdge('.hero__cta'),
      ) - left;
      const gap = 40;
      const room = width - copyRight - gap;
      const scale = Math.max(0.62, Math.min(1.1, room / (2 * BAND_REACH * unit * 0.92)));
      const centerX = Math.min(
        copyRight + gap + BAND_REACH * scale * unit,
        width - 24 - GLOBE_RIM * scale * unit,
      );
      rig.scale.setScalar(scale);
      camera.setViewOffset(width, height, width / 2 - centerX, 0, width, height);
    }

    function resize() {
      const width = Math.max(canvas.clientWidth, 1);
      const height = Math.max(canvas.clientHeight, 1);
      if (width === rendererWidth && height === rendererHeight) return;
      rendererWidth = width;
      rendererHeight = height;
      renderer.setSize(width, height, false);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
      placeRig(width, height);
      if (reduceMotion) renderer.render(scene, camera);
    }
    resize();
    if (document.fonts) document.fonts.ready.then(() => placeRig(rendererWidth, rendererHeight));
    window.addEventListener('resize', () => { if (!compactViewport.matches) resize(); }, { passive: true });
    window.addEventListener('orientationchange', () => {
      requestAnimationFrame(() => requestAnimationFrame(resize));
    }, { passive: true });

    let animationFrame = 0;
    let running = false;
    let clock = 0;
    let simAccum = 0;
    let lastNow = performance.now();
    // start with the hub (east Asia) facing the camera, then drift
    const HUB_FACING = 2.05;

    function updateBeams(snap) {
      for (let i = 0; i < roomBeams.length; i += 1) {
        const beam = roomBeams[i];
        const on = i < shownRooms;
        beam.line.visible = beam.line.visible || on;
        const uniforms = beam.material.uniforms;
        const want = on ? 0.34 : 0;
        uniforms.uBase.value = snap ? want : uniforms.uBase.value + (want - uniforms.uBase.value) * 0.08;
        uniforms.uTime.value = clock;
        if (!on && uniforms.uBase.value < 0.01) beam.line.visible = false;
      }
    }

    // red = people: the hub stays steel blue until someone is online
    let hubWarmth = 0;
    function updateHub(snap) {
      const want = targetPlayers > 0 ? 1 : 0;
      hubWarmth = snap ? want : hubWarmth + (want - hubWarmth) * 0.05;
      hubSprite.material.color.copy(STEEL).lerp(CAPE, hubWarmth);
      hubRing.material.color.copy(STEEL).lerp(CAPE, hubWarmth);
    }

    function frame(now) {
      // clamped step: a tab or scroll pause must not fast-forward the scene
      const dt = Math.min(Math.max((now - lastNow) / 1000, 0), 0.1);
      lastNow = now;
      clock += dt;
      pointer.lerp(pointerTarget, 0.025);

      rig.rotation.set(pointer.y * 0.05, pointer.x * 0.08, 0);
      planet.rotation.y = HUB_FACING + clock * 0.06;

      // ease the live counts toward their targets
      shownPlayers += (targetPlayers - shownPlayers) * 0.06;
      shownRooms += (targetRooms - shownRooms) * 0.08;

      simAccum += dt;
      while (simAccum >= GAME_FRAME) {
        simAccum -= GAME_FRAME;
        for (let i = 0; i < jumpers.length; i += 1) {
          if (i < shownPlayers || jumpers[i].presence > 0.01) stepJumper(jumpers[i]);
        }
      }

      for (const { material } of orbits) material.uniforms.uTime.value = clock;
      updateHub(false);
      updateJumpers(false);
      updateBeams(false);

      const phase = (clock * 0.45) % 1;
      hubRing.scale.setScalar(1 + phase * 3.2);
      hubRing.material.opacity = (1 - phase) * 0.65;

      renderer.render(scene, camera);
    }

    function renderStill() {
      shownPlayers = targetPlayers;
      shownRooms = targetRooms;
      planet.rotation.y = HUB_FACING;
      updateHub(true);
      updateJumpers(true);
      updateBeams(true);
      renderer.render(scene, camera);
    }

    function loop(now) {
      frame(now);
      if (running) animationFrame = requestAnimationFrame(loop);
    }
    function start() {
      if (running || reduceMotion) return;
      running = true;
      lastNow = performance.now();
      animationFrame = requestAnimationFrame(loop);
    }
    function stop() {
      running = false;
      cancelAnimationFrame(animationFrame);
    }

    if (reduceMotion) {
      renderStill();
    } else if ('IntersectionObserver' in window) {
      // scrolled past the hero: stop drawing and stop pushing wakes
      new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting) start();
        else stop();
      }).observe(canvas);
    } else {
      start();
    }
    window.addEventListener('pagehide', stop, { once: true });
  } catch (error) {
    console.warn('[globe] WebGL unavailable', error);
    canvas.style.display = 'none';
    const fallback = document.querySelector('#globe-fallback');
    if (fallback) fallback.hidden = false;
  }
}
