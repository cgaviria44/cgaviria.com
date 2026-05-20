# cgaviria.com — Claude Instructions

## Project
Bilingual CV site (EN/ES) for Christian Camilo Gaviria Castro, deployed on Cloudflare Pages at https://cv.cgaviria.com.

## Structure
- `index.html` — single file with all CV content inside the `I18N` JS object (two keys: `en` and `es`)
- `cv_en.pdf` / `cv_es.pdf` — downloadable PDFs, must always match the HTML
- `gen_pdf.mjs` — Node.js script to regenerate PDFs from the HTML
- `cover-letter.html` — cover letter (separate file)

## Workflow: making changes
**Every change must be applied to BOTH `en` and `es` blocks in `index.html`, then PDFs must be regenerated.**

1. Edit `index.html` — update both language blocks
2. Run: `node /tmp/gen_pdf.mjs` (copy from `gen_pdf.mjs` in project root if /tmp version is gone)
3. Commit and push: `index.html`, `cv_en.pdf`, `cv_es.pdf`
4. Use `git -c commit.gpgsign=false` — GPG signing is disabled

## PDF generation — critical notes
- Chrome CLI does NOT execute JavaScript when printing — content rendered by JS will be blank
- The fix: `gen_pdf.mjs` pre-renders HTML server-side in Node.js (extracts I18N data + render functions via `new Function()`), produces static HTML, then passes it to Chrome CLI
- **Do NOT use `page-break-inside: avoid` on `.job` in `@media print`** — long job entries (Cuemby has many bullets) cause a blank page. Use `page-break-after: avoid` on `.job-header` instead
- Chrome flags: `--print-to-pdf-no-header --no-pdf-header-footer` to suppress URL footer
- `gen_pdf.mjs` reads `index.html`, extracts I18N, renders both languages to `/tmp/cv_en_static.html` and `/tmp/cv_es_static.html`, then generates PDFs

## Git
- Branch: `main`
- Remote: https://github.com/cgaviria44/cgaviria.com.git
- Always use: `git -c commit.gpgsign=false` (GPG disabled globally)
- Auto-deploy via Cloudflare Pages on push to `main`

## CV content guidelines
- Keep EN and ES in sync — every change in one language must be mirrored in the other
- Avoid literal translations in ES — adapt naturally
- Salary expectation: $15,000,000 COP/month with all legal benefits
- English level: B2 Upper Intermediate
