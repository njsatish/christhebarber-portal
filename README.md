# Chris Fleming The Barber demo

Preview with `./serve-local.sh`, then open `http://localhost:8080`.

Before publishing, obtain Chris's approval for his personal information, branding, photographs, and testimonials. Replace gallery placeholders only with approved, optimized images. Setmore remains the source of truth for pricing, deposits, policies, hours, and availability.

## Git workflow after approval

```bash
git status --short --branch
git switch -c chris-the-barber-v1 2>/dev/null || git switch chris-the-barber-v1
git add index.html assets book robots.txt sitemap.xml README.md serve-local.sh
git diff --cached --check
git diff --cached --stat
git commit -m "Create Chris the Barber local website"
git status --short --branch
git push -u origin chris-the-barber-v1
```
