import { readFileSync, writeFileSync } from 'fs';
import { execSync } from 'child_process';

const PROJECT = '/Users/cgaviria44/Documents/projects/cgaviria.com';
const HTML = readFileSync(`${PROJECT}/index.html`, 'utf8');

// Extract the I18N object by replacing const with a return statement
const scriptMatch = HTML.match(/<script>([\s\S]+?)<\/script>/);
const fullScript = scriptMatch[1];
const cutPoint = fullScript.search(/\/\/ Script is at bottom|document\.addEventListener|\(function \(\)/);
const safeScript = (cutPoint > 0 ? fullScript.slice(0, cutPoint) : fullScript).trim();

// Replace `const I18N = ` with `return ` so we can capture the value
const extractScript = safeScript.replace(/^const I18N\s*=\s*/m, 'return ');
const I18N = new Function(extractScript)();

if (!I18N || !I18N.en || !I18N.es) throw new Error('Could not extract I18N');
console.log('I18N extracted. EN skills:', I18N.en.skills.length, '| ES experience jobs:', I18N.es.experience.length);

const cssMatch = HTML.match(/<style>([\s\S]+?)<\/style>/);
const css = cssMatch[1];

function renderSkills(items) {
  return `<table class="kv-table">${items.map(s => `
    <tr>
      <td class="key">${s.label}</td>
      <td class="val">
        <div class="skill-val">
          <span class="skill-detail">${s.detail}</span>
          <span class="skill-bar"><span class="skill-bar-fill" style="width:${s.level * 10}%"></span></span>
          <span class="skill-level">${s.level}/10</span>
        </div>
      </td>
    </tr>`).join('')}</table>`;
}

function renderStack(items) {
  return `<table class="kv-table">${items.map(([label, text]) =>
    `<tr><td class="key">${label}</td><td class="val">${text}</td></tr>`
  ).join('')}</table>`;
}

function renderExperience(items) {
  return items.map(j => `
    <div class="job">
      <div class="job-header">
        <div class="job-title">${j.title}</div>
        <div class="job-period">${j.period}</div>
      </div>
      <div class="job-company">${j.company} · ${j.location}</div>
      <ul>${j.bullets.map(b => `<li>${b}</li>`).join('')}</ul>
    </div>`).join('');
}

function renderAchievements(items) {
  return items.map(t => `<li>${t}</li>`).join('');
}

function renderLanguages(items) {
  return items.map(l => `
    <li>
      <strong>${l.lang}</strong> <span class="meta">— ${l.meta}</span>
      ${l.extra ? `<div class="sub">${l.extra}</div>` : ''}
    </li>`).join('');
}

function renderEducation(items) {
  return items.map(e => `<li><strong>${e.degree}</strong><div class="meta">${e.meta}</div></li>`).join('');
}

function renderTalks(items) {
  return items.map(t => `
    <div class="talk-item">
      <div class="talk-title">${t.title}</div>
      <div class="talk-event">${t.event}</div>
      <div class="talk-desc">${t.desc}</div>
    </div>`).join('');
}

function buildStaticHTML(lang) {
  const t = I18N[lang];
  return `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>Christian Gaviria — Senior SRE</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>${css}</style>
</head>
<body>
<div class="container">
  <header class="cv-header">
    <div class="cv-header-main">
      <h1 class="cv-name">Christian Camilo Gaviria Castro</h1>
      <div class="cv-title">${t.title}</div>
      <div class="cv-contact">
        <a href="mailto:me@cgaviria.com">me@cgaviria.com</a>
        <span class="cv-contact-sep">·</span>
        <a href="https://wa.me/573003437758">+57 300 343 7758</a>
        <span class="cv-contact-sep">·</span>
        <a href="https://linkedin.com/in/cgaviria44">linkedin.com/in/cgaviria44</a>
        <span class="cv-contact-sep">·</span>
        <a href="https://linktr.ee/cgaviria44">linktr.ee/cgaviria44</a>
        <span class="cv-contact-sep">·</span>
        <span>${t.location}</span>
      </div>
    </div>
    <div class="avatar">
      <img src="${PROJECT}/photo.jpg" alt="Christian Camilo Gaviria Castro"/>
    </div>
  </header>

  <section>
    <h2 class="section-title">${t.secProfile}</h2>
    <p class="profile-text">${t.profileText}</p>
  </section>

  <section>
    <h2 class="section-title">${t.secAchievements}</h2>
    <ul class="achievement-list">${renderAchievements(t.achievements)}</ul>
  </section>

  <section>
    <h2 class="section-title">${t.secExperience}</h2>
    <div>${renderExperience(t.experience)}</div>
  </section>

  <section>
    <h2 class="section-title">${t.secProficiency}</h2>
    <div>${renderSkills(t.skills)}</div>
  </section>

  <section>
    <h2 class="section-title">${t.secStack}</h2>
    <div>${renderStack(t.stack)}</div>
  </section>

  <section>
    <div class="two-col">
      <div>
        <h2 class="section-title">${t.secEducation}</h2>
        <ul class="simple-list">${renderEducation(t.education)}</ul>
      </div>
      <div>
        <h2 class="section-title">${t.secLanguages}</h2>
        <ul class="simple-list">${renderLanguages(t.languages)}</ul>
      </div>
    </div>
  </section>

  <section>
    <h2 class="section-title">${t.secCerts}</h2>
    <div>${renderStack(t.certs)}</div>
  </section>

  <section>
    <h2 class="section-title">${t.secHonors}</h2>
    <ul class="achievement-list">${renderAchievements(t.honors)}</ul>
  </section>

  <section>
    <h2 class="section-title">${t.secTalks}</h2>
    <div>${renderTalks(t.talks)}</div>
  </section>

  <section>
    <h2 class="section-title">${t.secSoft}</h2>
    <div>${renderStack(t.soft)}</div>
  </section>

  <footer>
    <span>© 2026 Christian Camilo Gaviria Castro</span>
  </footer>
</div>
</body>
</html>`;
}

for (const lang of ['en', 'es']) {
  const staticPath = `/tmp/cv_${lang}_static.html`;
  writeFileSync(staticPath, buildStaticHTML(lang), 'utf8');
  console.log(`Static HTML written: ${staticPath}`);

  execSync(`"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    --headless=new --no-sandbox \
    --print-to-pdf="${PROJECT}/cv_${lang}.pdf" \
    --print-to-pdf-no-header --no-pdf-header-footer \
    "file://${staticPath}" 2>/dev/null`);

  console.log(`Generated: cv_${lang}.pdf`);
}
