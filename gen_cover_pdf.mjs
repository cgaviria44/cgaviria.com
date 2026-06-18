import { readFileSync, writeFileSync } from 'fs';
import { execSync } from 'child_process';

const PROJECT = '/Users/cgaviria/Documents/projects/cgaviria.com';
const HTML = readFileSync(`${PROJECT}/cover-letter.html`, 'utf8');

// Extract CSS
const cssMatch = HTML.match(/<style>([\s\S]+?)<\/style>/);
const css = cssMatch[1];

// Extract the I18N object. The <script> defines today/enDate/esDate then `const I18N = {...}`.
// Keep everything up to `function applyLang` and return I18N.
const scriptMatch = HTML.match(/<script>([\s\S]+?)<\/script>/);
const fullScript = scriptMatch[1];
const cutPoint = fullScript.search(/function applyLang/);
const safeScript = fullScript.slice(0, cutPoint).trim() + '\nreturn I18N;';
const I18N = new Function(safeScript)();

if (!I18N || !I18N.en || !I18N.es) throw new Error('Could not extract I18N');
console.log('I18N extracted for cover letter.');

function buildStaticHTML(lang) {
  const t = I18N[lang];
  return `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Christian Gaviria — Cover Letter</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>${css}</style>
</head>
<body>
<div class="page">
  <header class="cl-header">
    <div class="cl-header-main">
      <div class="cl-name">Christian Camilo Gaviria Castro</div>
      <div class="cl-title">${t.title}</div>
      <div class="cl-contact">
        <a href="mailto:me@cgaviria.com">me@cgaviria.com</a>
        <span class="cl-contact-sep">·</span>
        <a href="https://linkedin.com/in/cgaviria44">linkedin.com/in/cgaviria44</a>
        <span class="cl-contact-sep">·</span>
        <a href="https://linktr.ee/cgaviria44">linktr.ee/cgaviria44</a>
        <span class="cl-contact-sep">·</span>
        <span>${t.location}</span>
      </div>
    </div>
  </header>

  <div class="cl-meta">
    <div class="cl-date">${t.date}</div>
    <div class="cl-to">
      <strong>${t.toLabel}</strong><br>
      Hiring Manager
    </div>
  </div>

  <div class="cl-subject">${t.subject}</div>

  <div class="cl-body">${t.body}</div>

  <div class="cl-sign">
    <div>${t.signOff}</div>
    <div style="margin-top:24px;"><strong>${t.signName}</strong></div>
    <div style="color:#666; font-size:13px; margin-top:2px;">${t.signContact}</div>
  </div>

  <footer>${t.footer}</footer>
</div>
</body>
</html>`;
}

for (const lang of ['en', 'es']) {
  const staticPath = `/tmp/cover-letter_${lang}_static.html`;
  writeFileSync(staticPath, buildStaticHTML(lang), 'utf8');
  console.log(`Static HTML written: ${staticPath}`);

  execSync(`"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless=new --no-sandbox \
    --print-to-pdf="${PROJECT}/cover-letter_${lang}.pdf" \
    --print-to-pdf-no-header --no-pdf-header-footer \
    "file://${staticPath}" 2>/dev/null`);

  console.log(`Generated: cover-letter_${lang}.pdf`);
}
