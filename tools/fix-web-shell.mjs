import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const htmlPath = join(root, "build/web/index.html");
const jsPath = join(root, "build/web/index.js");
let html = await readFile(htmlPath, "utf8");
const js = await readFile(jsPath, "utf8");

html = html.replace("background-color: black;", "background-color: #06101f;");
html = html.replace(/"canvasResizePolicy":[012]/g, '"canvasResizePolicy":0');

html = html.replace(
  /html, body, #canvas \{[\s\S]*?\n\}\n\n(?:html, body \{[\s\S]*?\n\}\n\n)?body \{[\s\S]*?\n\}\n\n#canvas \{[\s\S]*?\n\}\n\n#canvas:focus \{/,
  `html, body, #canvas {
\tmargin: 0;
\tpadding: 0;
\tborder: 0;
}

html, body {
\twidth: 100%;
\theight: 100%;
}

body {
\tcolor: white;
\tbackground-color: #06101f;
\toverflow: hidden;
\ttouch-action: none;
}

#memepire-viewport {
\tposition: fixed;
\tinset: 0;
\twidth: 100vw !important;
\theight: 100vh !important;
\toverflow: hidden;
\tbackground-color: #06101f;
\tdisplay: flex;
\talign-items: center;
\tjustify-content: center;
}

#canvas {
\tdisplay: block;
\twidth: min(100vw, calc(100vh * 1.777777778)) !important;
\theight: min(100vh, calc(100vw * 0.5625)) !important;
\tmax-width: none !important;
\tmax-height: none !important;
\tbackground-color: #06101f;
\timage-rendering: pixelated;
}

#canvas:focus {`,
);

html = html.replace(
  /\t\t<div id="memepire-frame">\n\t\t\t<canvas id="canvas">\n\t\t\t\tYour browser does not support the canvas tag\.\n\t\t\t<\/canvas>\n\t\t<\/div>\n\t\t<div id="memepire-cover-top" class="memepire-cover"><\/div>\n\t\t<div id="memepire-cover-bottom" class="memepire-cover"><\/div>\n\t\t<div id="memepire-cover-left" class="memepire-cover"><\/div>\n\t\t<div id="memepire-cover-right" class="memepire-cover"><\/div>/g,
  "\t\t<div id=\"memepire-viewport\">\n\t\t\t<canvas id=\"canvas\">\n\t\t\t\tYour browser does not support the canvas tag.\n\t\t\t</canvas>\n\t\t</div>",
);
html = html.replace(
  /\t\t<canvas id="canvas">\n\t\t\tYour browser does not support the canvas tag\.\n\t\t<\/canvas>/g,
  "\t\t<div id=\"memepire-viewport\">\n\t\t\t<canvas id=\"canvas\">\n\t\t\t\tYour browser does not support the canvas tag.\n\t\t\t</canvas>\n\t\t</div>",
);
html = html.replace(/\n\t\t<div id="memepire-mask-(?:top|bottom|left|right)" class="memepire-mask"><\/div>/g, "");
html = html.replace(/\n#memepire-frame \{[\s\S]*?\n\}\n\n\.memepire-cover \{[\s\S]*?\n\}\n/g, "\n");
html = html.replace(
  /\n\t\t<script>window\.__memepireNativeDevicePixelRatio=window\.devicePixelRatio;Object\.defineProperty\(window,'devicePixelRatio',\{get:function\(\)\{return 1;\},configurable:true\}\);<\/script>/g,
  "",
);
html = html.replace(
  /\n\t\t<script>\nwindow\.__memepireNativeDevicePixelRatio = window\.devicePixelRatio \|\| 1;\nif \(window\.__memepireNativeDevicePixelRatio < 1\) \{\n\tObject\.defineProperty\(window, 'devicePixelRatio', \{\n\t\tget: function\(\) \{\n\t\t\treturn 1;\n\t\t\},\n\t\tconfigurable: true\n\t\}\);\n\}\n\t\t<\/script>/g,
  "",
);
html = html.replace(
  /\nwindow\.__memepireNativeDevicePixelRatio = window\.devicePixelRatio \|\| 1;\nObject\.defineProperty\(window, 'devicePixelRatio', \{\n\tget: function\(\) \{\n\t\tvar ratio = window\.__memepireNativeDevicePixelRatio \|\| 1;\n\t\treturn ratio < 1 \? 1 \/ ratio : ratio;\n\t\},\n\tconfigurable: true\n\}\);\n/g,
  "\n",
);
html = html.replace(
  /\n\t\t<script src="index\.js"><\/script>/,
  `\n\t\t<script>
window.__memepireNativeDevicePixelRatio = window.devicePixelRatio || 1;
Object.defineProperty(window, 'devicePixelRatio', {
\tget: function () {
\t\treturn 1;
\t},
\tconfigurable: true,
});
\t\t</script>
\t\t<script src="index.js"></script>`,
);
html = html.replace(
  /\nconst memepireCanvas = document\.getElementById\('canvas'\);\nfunction memepireResizeCanvas\(\) \{[\s\S]*?\n\}\nwindow\.addEventListener\('resize', memepireResizeCanvas\);\nmemepireResizeCanvas\(\);\n(?:setTimeout\(memepireResizeCanvas, 250\);\nsetTimeout\(memepireResizeCanvas, 1000\);\n)?/g,
  "\n",
);

html = html.replace(
  /\nfunction memepireFitCanvas\(\) \{[\s\S]*?\n\}\nwindow\.addEventListener\('resize', memepireFitCanvas\);\n/g,
  "\n",
);
html = html.replace(
  /\t\t\}\)\.then\(\(\) => \{\n\t\t\tsetStatusMode\('hidden'\);\n\t\t\}, displayFailureNotice\);/,
  `\t\t}).then(() => {
\t\t\tsetStatusMode('hidden');
\t\t\tfunction memepireFitCanvas() {
\t\t\t\tconst canvas = document.getElementById('canvas');
\t\t\t\tif (!canvas) return;
\t\t\t\tcanvas.width = 1280;
\t\t\t\tcanvas.height = 720;
\t\t\t\tcanvas.style.width = 'min(100vw, calc(100vh * 1.777777778))';
\t\t\t\tcanvas.style.height = 'min(100vh, calc(100vw * 0.5625))';
\t\t\t}
\t\t\twindow.addEventListener('resize', memepireFitCanvas);
\t\t\tmemepireFitCanvas();
\t\t\tsetTimeout(memepireFitCanvas, 250);
\t\t}, displayFailureNotice);`,
);

await writeFile(htmlPath, html);
await writeFile(jsPath, js);
console.log("[memepire-web-shell] logical-pixel fractional-DPR-safe shell verified");
