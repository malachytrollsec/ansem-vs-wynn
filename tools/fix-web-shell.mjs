import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const htmlPath = join(root, "build/web/index.html");
let html = await readFile(htmlPath, "utf8");

html = html.replace("background-color: black;", "background-color: #06101f;");

if (!html.includes("html, body {\n\twidth: 100%;\n\theight: 100%;\n}")) {
  html = html.replace(
    "html, body, #canvas {\n\tmargin: 0;\n\tpadding: 0;\n\tborder: 0;\n}\n\nbody {",
    "html, body, #canvas {\n\tmargin: 0;\n\tpadding: 0;\n\tborder: 0;\n}\n\nhtml, body {\n\twidth: 100%;\n\theight: 100%;\n}\n\nbody {",
  );
}

html = html.replace(/"canvasResizePolicy":2/g, '"canvasResizePolicy":0');

html = html.replace(/\n#canvas \{\n\tdisplay: block;\n(?:\tposition: absolute;\n\tleft: 0;\n\ttop: 0;\n\twidth: 1280px;\n\theight: 720px;\n\tmax-width: none;\n\tmax-height: none;\n\ttransform-origin: top left;\n\timage-rendering: pixelated;\n|\tposition: absolute;\n\tleft: 50%;\n\ttop: 50%;\n\twidth: 1280px;\n\theight: 720px;\n\tmax-width: calc\(100vw - 24px\);\n\tmax-height: calc\(100vh - 24px\);\n\ttransform: translate\(-50%, -50%\);\n(?:\tcontain: strict;\n\tclip-path: inset\(0\);\n)?\timage-rendering: pixelated;\n|\twidth: 100vw;\n\theight: 100vh;\n\tmax-width: 100vw;\n\tmax-height: 100vh;\n)?\}\n/g, "\n#canvas {\n\tdisplay: block;\n\tposition: absolute;\n\tleft: 50%;\n\ttop: 50%;\n\twidth: 1280px;\n\theight: 720px;\n\tmax-width: calc(100vw - 24px);\n\tmax-height: calc(100vh - 24px);\n\ttransform: translate(-50%, -50%);\n\tcontain: strict;\n\tclip-path: inset(0);\n\timage-rendering: pixelated;\n}\n");

const sizeScript = "const memepireCanvas = document.getElementById('canvas');\nfunction memepireResizeCanvas() {\n\tif (!memepireCanvas) return;\n\tmemepireCanvas.width = 1280;\n\tmemepireCanvas.height = 720;\n\tconst dpr = Number(window.devicePixelRatio) || 1;\n\tconst pixelSafeScale = dpr > 0 && dpr < 1 ? dpr : 1;\n\tconst fitScale = Math.min(1, (window.innerWidth - 24) / 1280, (window.innerHeight - 24) / 720);\n\tconst scale = Math.min(pixelSafeScale, fitScale);\n\tconst cssWidth = Math.max(1, Math.floor(1280 * scale));\n\tconst cssHeight = Math.max(1, Math.floor(720 * scale));\n\tmemepireCanvas.style.width = cssWidth + 'px';\n\tmemepireCanvas.style.height = cssHeight + 'px';\n}\nwindow.addEventListener('resize', memepireResizeCanvas);\nmemepireResizeCanvas();\n";

html = html.replace(
  /const memepireCanvas = document\.getElementById\('canvas'\);\nfunction memepireResizeCanvas\(\) \{[\s\S]*?\n\}\nwindow\.addEventListener\('resize', memepireResizeCanvas\);\nmemepireResizeCanvas\(\);\n/g,
  sizeScript,
);

if (!html.includes("function memepireResizeCanvas")) {
  html = html.replace("const engine = new Engine(GODOT_CONFIG);\n", `const engine = new Engine(GODOT_CONFIG);\n${sizeScript}`);
}

html = html.replace(/\nGODOT_CONFIG\.canvasResizePolicy = 0;\nconst memepireCanvas = document\.getElementById\('canvas'\);\nfunction memepireResizeCanvas\(\) \{\n\tif \(!memepireCanvas\) return;\n\tconst scale = Math\.min\(1, Math\.max\(0\.5, Number\(window\.devicePixelRatio\) \|\| 1\)\);\n\tmemepireCanvas\.width = Math\.round\(1280 \* scale\);\n\tmemepireCanvas\.height = Math\.round\(720 \* scale\);\n\}\nwindow\.addEventListener\('resize', memepireResizeCanvas\);\nmemepireResizeCanvas\(\);\n/g, "\n");

html = html.replace(/\nGODOT_CONFIG\.canvasResizePolicy = 0;\nconst memepireCanvas = document\.getElementById\('canvas'\);\nfunction memepireResizeCanvas\(\) \{\n\tif \(!memepireCanvas\) return;\n\tconst width = Math\.max\(1, Math\.round\(window\.innerWidth \|\| 1280\)\);\n\tconst height = Math\.max\(1, Math\.round\(window\.innerHeight \|\| 720\)\);\n\tmemepireCanvas\.width = width;\n\tmemepireCanvas\.height = height;\n\tmemepireCanvas\.style\.width = `\$\{width\}px`;\n\tmemepireCanvas\.style\.height = `\$\{height\}px`;\n\}\nwindow\.addEventListener\('resize', memepireResizeCanvas\);\nmemepireResizeCanvas\(\);\n/g, "\n");

html = html.replace(/\n#canvas\.memepire-landscape-framed \{\n\twidth: 100vw !important;\n\theight: calc\(100vw \* 9 \/ 16\) !important;\n\tmax-height: 100vh;\n\}\n/g, "\n");

html = html.replace(/\n\t\tif \(window\.innerHeight > window\.innerWidth && window\.innerWidth < 700\) \{\n\t\t\tcanvas\.classList\.add\('memepire-landscape-framed'\);\n\t\t\} else \{\n\t\t\tcanvas\.classList\.remove\('memepire-landscape-framed'\);\n\t\t\}\n/g, "\n");

await writeFile(htmlPath, html);
console.log("[memepire-web-shell] full-viewport canvas wrapper verified");
