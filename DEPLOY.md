# cgaviria.com — Deploy Guide (Bilingüe EN/ES)

Tu sitio personal con **CV web bilingüe** (switch EN/ES) + PDFs descargables en ambos idiomas.

## 📁 Archivos en esta carpeta

```
cv-web/
├── index.html      ← Landing/CV bilingüe (terminal dark theme, switch EN/ES)
├── photo.jpg       ← Tu foto
├── cv_en.pdf       ← PDF en inglés (de Overleaf)
├── cv_es.pdf       ← PDF en español (de Overleaf)
├── cv.docx         ← Versión Word descargable (genérica)
└── DEPLOY.md       ← Este archivo
```

## 🎯 Cómo funciona el switch EN/ES

- **Botón fijo arriba a la derecha** con dos opciones: `EN` y `ES`
- Click cambia TODO el contenido en menos de 200ms (sin recargar página)
- **Auto-detección**: si el navegador del visitante está en español, abre por defecto en ES
- **Memoria**: guarda la elección en localStorage — la próxima visita abre en el idioma elegido
- **PDF dinámico**: el botón "Download PDF" lleva a `cv_en.pdf` o `cv_es.pdf` según el idioma activo

## 🚀 Deploy en Cloudflare Pages

### Paso 1 — Subir a GitHub

**Opción A — desde la web:**
1. https://github.com/new → repo nuevo: `cgaviria.com`
2. **Add file** → **Upload files** → arrastra los 6 archivos
3. Commit

**Opción B — terminal:**
```bash
cd cv-web/
git init
git add .
git commit -m "Initial: bilingual CV site"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/cgaviria.com.git
git push -u origin main
```

### Paso 2 — Conectar Cloudflare Pages

1. https://dash.cloudflare.com → **Workers & Pages** → **Create application** → **Pages**
2. **Connect to Git** → autoriza GitHub
3. Selecciona repo `cgaviria.com`
4. Configura:
   - **Project name**: `cgaviria`
   - **Production branch**: `main`
   - **Framework preset**: None
   - **Build command**: (vacío)
   - **Build output directory**: `/`
5. **Save and Deploy**

### Paso 3 — Conectar dominio `cgaviria.com`

1. Pestaña **Custom domains** del proyecto
2. **Set up a custom domain** → `cgaviria.com` → Activate

### Paso 4 — Verificar

- https://cgaviria.com → CV con switch EN/ES
- https://cgaviria.com/cv_en.pdf → PDF inglés
- https://cgaviria.com/cv_es.pdf → PDF español

## 🔄 Cómo actualizar en el futuro

### Cambios en HTML
Edita `index.html` — todo el contenido bilingüe está en el objeto `I18N` al final del archivo. Cada texto tiene par `en:` y `es:`. Commit + push → auto-deploy.

### Cambios en PDFs (LaTeX/Overleaf)
1. En Overleaf edita `main.tex` (EN) o `main_es.tex` (ES) — los tienes en la carpeta `cv-clean/`
2. Recompile → descarga PDF
3. Renombra a `cv_en.pdf` o `cv_es.pdf`
4. Reemplaza en GitHub → auto-deploy

## 🎨 Personalización del HTML

**Cambiar colores del tema terminal** (en `index.html`, sección `:root`):
```css
--accent: #5cc8ff;     /* cyan principal */
--accent-2: #7ee787;   /* verde terminal */
--bg: #0a0e14;         /* fondo near-black */
```

**Cambiar idioma por defecto**: busca `let initLang = 'en';` en el script y cambia a `'es'`.

## ❓ Troubleshooting

| Problema | Solución |
|----------|----------|
| El switch no cambia idioma | Verifica que JS esté habilitado |
| PDFs no descargan | Verifica que `cv_en.pdf` y `cv_es.pdf` estén en raíz del repo |
| Foto no carga | `photo.jpg` debe estar exactamente con ese nombre en raíz |
| Sitio no aparece | Espera 2-5 min, limpia caché (Ctrl+Shift+R) |
