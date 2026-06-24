import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const htmlPath = join(root, "build/web/index.html");
let html = await readFile(htmlPath, "utf8");

html = html.replace("background-color: black;", "background-color: #06101f;");
html = html.replace(
  "if(window.devicePixelRatio>0&&window.devicePixelRatio<1){Object.defineProperty(window,'devicePixelRatio',{configurable:true,get:function memepireLowDpr(){return 1;}});}",
  "if(window.devicePixelRatio>0&&window.devicePixelRatio<1){const memepireLowDpr=window.devicePixelRatio;Object.defineProperty(window,'devicePixelRatio',{configurable:true,get:function(){return 1/memepireLowDpr;}});}",
);
html = html.replace(
  "if(window.devicePixelRatio>0&&window.devicePixelRatio<1){const memepireLowDpr=window.devicePixelRatio;document.documentElement.classList.add('memepire-low-dpr');document.documentElement.style.setProperty('--memepire-low-dpr-scale',String(1/memepireLowDpr));Object.defineProperty(window,'devicePixelRatio',{configurable:true,get:function(){return 1/memepireLowDpr;}});}",
  "if(window.devicePixelRatio>0&&window.devicePixelRatio<1){const memepireLowDpr=window.devicePixelRatio;Object.defineProperty(window,'devicePixelRatio',{configurable:true,get:function(){return 1/memepireLowDpr;}});}",
);

if (!html.includes("memepireLowDpr")) {
  html = html.replace(
    "\t\t<link id=\"-gd-engine-icon\" rel=\"icon\" type=\"image/png\" href=\"index.icon.png\" />",
    "\t\t<link id=\"-gd-engine-icon\" rel=\"icon\" type=\"image/png\" href=\"index.icon.png\" />\n<script>if(window.devicePixelRatio>0&&window.devicePixelRatio<1){const memepireLowDpr=window.devicePixelRatio;Object.defineProperty(window,'devicePixelRatio',{configurable:true,get:function(){return 1/memepireLowDpr;}});}</script>",
  );
}

if (!html.includes("html, body {\n\twidth: 100%;\n\theight: 100%;\n}")) {
  html = html.replace(
    "html, body, #canvas {\n\tmargin: 0;\n\tpadding: 0;\n\tborder: 0;\n}\n\nbody {",
    "html, body, #canvas {\n\tmargin: 0;\n\tpadding: 0;\n\tborder: 0;\n}\n\nhtml, body {\n\twidth: 100%;\n\theight: 100%;\n}\n\nbody {",
  );
}

if (!html.includes("width: 100vw;")) {
  html = html.replace(
    "\ttouch-action: none;\n}\n\n#canvas {\n\tdisplay: block;\n}\n",
    "\ttouch-action: none;\n}\n\n#canvas {\n\tdisplay: block;\n\twidth: 100vw;\n\theight: 100vh;\n\tmax-width: 100vw;\n\tmax-height: 100vh;\n}\n",
  );
}

if (!html.includes("function memepireResizeCanvas")) {
  html = html.replace(
    "const engine = new Engine(GODOT_CONFIG);",
    "GODOT_CONFIG.canvasResizePolicy = 0;\nconst memepireCanvas = document.getElementById('canvas');\nfunction memepireResizeCanvas() {\n\tif (!memepireCanvas) return;\n\tconst scale = Math.min(1, Math.max(0.5, Number(window.devicePixelRatio) || 1));\n\tmemepireCanvas.width = Math.round(1280 * scale);\n\tmemepireCanvas.height = Math.round(720 * scale);\n}\nwindow.addEventListener('resize', memepireResizeCanvas);\nmemepireResizeCanvas();\nconst engine = new Engine(GODOT_CONFIG);",
  );
}

html = html.replace(/\nhtml\.memepire-low-dpr #canvas \{\n\twidth: calc\(100vw \* var\(--memepire-low-dpr-scale\)\) !important;\n\theight: calc\(100vh \* var\(--memepire-low-dpr-scale\)\) !important;\n\tmax-width: none;\n\tmax-height: none;\n\}\n/g, "\n");

html = html.replace(/\n#canvas\.memepire-dpr-clamped \{\n\twidth: auto !important;\n\theight: auto !important;\n\}\n/g, "\n");
html = html.replace(/\n#canvas\.memepire-landscape-framed \{\n\twidth: 100vw !important;\n\theight: calc\(100vw \* 9 \/ 16\) !important;\n\tmax-height: 100vh;\n\}\n/g, "\n");

html = html.replace(/\n\tfunction syncCanvasDisplaySize\(\) \{\n\t\tif \(window\.devicePixelRatio > 0 && window\.devicePixelRatio < 1\) \{\n\t\t\tcanvas\.classList\.add\('memepire-dpr-clamped'\);\n\t\t\} else \{\n\t\t\tcanvas\.classList\.remove\('memepire-dpr-clamped'\);\n\t\t\}\n\t\}\n\twindow\.addEventListener\('resize', syncCanvasDisplaySize\);\n\tsyncCanvasDisplaySize\(\);\n/g, "\n");

html = html.replace(/\n\t\tif \(window\.innerHeight > window\.innerWidth && window\.innerWidth < 700\) \{\n\t\t\tcanvas\.classList\.add\('memepire-landscape-framed'\);\n\t\t\} else \{\n\t\t\tcanvas\.classList\.remove\('memepire-landscape-framed'\);\n\t\t\}\n/g, "\n");

await writeFile(htmlPath, html);
console.log("[memepire-web-shell] full-viewport canvas wrapper verified");
