# cgaviria.com — Claude Instructions

## Project
Bilingual CV site (EN/ES) for Christian Camilo Gaviria Castro, deployed on Cloudflare Pages at https://cv.cgaviria.com.

## Structure
- `index.html` — single file with all CV content inside the `I18N` JS object (two keys: `en` and `es`)
- `cv_en.pdf` / `cv_es.pdf` — downloadable PDFs, must always match the HTML
- `gen_pdf.mjs` — Node.js script to regenerate PDFs from the HTML. **Has its own hardcoded header template** (not read from `index.html`) — any change to the header in `index.html` must also be applied manually in `gen_pdf.mjs` (`buildStaticHTML` function, lines ~94–110). The `cv-title` div IS dynamic (`${t.title}`), so header keyword changes only need updating in the I18N `title` fields.
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
- English level: B2 Upper Intermediate — EF SET certificate 59/100, awarded 2026-05-27 (https://cert.efset.org/es/XndquY)
- **References section removed** — not standard for US market; available on request
- **Header title (same for EN and ES):** `Sr. Cloud & Security Reliability Engineer & Technical Leader · DevSecOps · Kubernetes · AWS · Cloud-Native · Linux · Windows · Platform Engineering · GitOps · Terraform · IPv6`

## Technical skills reference (for accurate CV updates)

| Area | Tools / Technologies |
|------|---------------------|
| Cloud | AWS (SAA-C03, CLF), GCP, Azure, CIVO, Equinix Metal, DigitalOcean |
| Kubernetes | Talos Linux, Cilium (eBPF), Rook Ceph, Velero, KubeVirt, Helm, ingress, service mesh, load balancers, Telepresence, etcd |
| Virtualization | KVM, Proxmox, VMware vCenter, OpenStack, KubeVirt, Apache CloudStack |
| Baremetal provisioning | MAAS (Canonical), Tinkerbell, Seeder Harvester, PXE, cloud-init |
| IaC / Automation | Terraform, Ansible, CloudFormation, ArgoCD, GitOps, Walrus, Sveltos |
| CI/CD | Jenkins, GitHub Actions, GitLab CI, AWS CodePipeline/CodeBuild/CodeDeploy |
| Observability | Prometheus, Grafana, Loki, Jaeger, Tempo, OpenTelemetry, AlertManager (→ Slack, Teams, PagerDuty) |
| Windows / Microsoft | Windows Server, Active Directory, DNS, GPOs, disk quotas, remote access (RDP/VPN), AD migrations, Entra ID (Azure AD), Microsoft Security, firewall, hardening |
| Security | Firewalls, UTM, WAF (Cloudflare), VPNs (IPsec, WireGuard, OpenVPN, Tailscale, mesh), Wazuh (SIEM/audits), Trivy, Kube-bench, GitGuardian, SSL/TLS, IAM hardening, Cisco Cybersecurity Essentials |
| Compliance | Vanta (SOC 2, continuous compliance, evidence automation) |
| Storage & DR | Rook Ceph, TrueNAS, OpenEBS, Mayastor, MinIO (object & block), RAID, Velero, DR/DRP multi-region |
| Self-hosted | Nextcloud (installation, configuration, administration) |
| Networking | BGP, OSPF, IPv4/IPv6, DNS/DNSSEC/DoH/DoT, Netris (network fabric), Wireshark, tcpdump, MikroTik (MTCNA/MTCTCE/MTCSE/MTCIPv6E), Cisco CCNA, Ubiquiti UniFi |
| Telco | 5G core on K8s, Unikraft unikernels, GPON (Huawei, ZTE, TP-Link, CData), IPTV, Asterisk/Elastix/Issabel |
| Databases | PostgreSQL, MySQL, SQL Server, Amazon Aurora |
| Scripting | Python, Bash |
| AI | Claude Code, ChatGPT, GitHub Copilot, prompt engineering |

## Experience entries (current order in `index.html`)
Listed most-recent first; ongoing freelance/project-based entries follow the main job:

| # | EN title | Company | Period | Key bullets added / notes |
|---|----------|---------|--------|--------------------------|
| 1 | Senior Site Reliability Engineer — Cloud & Security | Cuemby | Apr 2023 — May 2026 (**finished**) | Talos Linux, OpenStack, MAAS/Tinkerbell/Harvester, TrueNAS/OpenEBS/Mayastor/MinIO, Wazuh/Trivy/Kube-bench, AlertManager→Slack/Teams/PagerDuty, Vanta, Netris, Telepresence, Nextcloud, GitHub Issues/Projects + DOFA matrices, marketplace video tutorials (n8n, OpenClaw, WordPress, MySQL, etc.) |
| 2 | Cloud Engineer | Negocios NEX | Oct 2019 — Dec 2025 (**finished**) | project-based; backup & DR strategy bullet |
| 3 | Infrastructure Engineer | Smart Town SAS | 2019 — Dec 2025 (**finished**) | freelance ISP; DNS server with DNSSEC, DoH, DoT |
| 4 | Infrastructure Engineer | TikAcademy | Mar 2021 — Dec 2023 | project-based |
| 5 | Cloud Engineer | Droptek | Jan 2022 — Jul 2023 | |
| 6 | Sysadmin · Network · Wireless · Cloud Engineer | EJ Soluciones | Sep 2019 — Dec 2021 | VMware vCenter, migrations, backups; Windows Server, AD, DNS, GPOs, disk quotas, remote access, AD migrations, Entra ID, Microsoft Security, firewall, hardening |
| 7 | IT Support Coordinator | PEG Soluciones – Teltic | Aug 2016 — Dec 2021 | CGNAT, port block allocation for exposing network services |
| 8 | Network Administrator & Researcher — SISSI | ITM | Aug 2016 — Oct 2021 | |
