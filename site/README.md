# Neocom landing site

Plain static site (hand-written HTML + CSS, no build step).

Preview locally:

    python3 -m http.server -d site 8000

Then open http://localhost:8000.

Deploy: `.github/workflows/pages.yml` publishes `site/` on every push to `main` that touches
`site/**` (it can also be run manually via workflow_dispatch).

One-time setup: in the repository settings, Pages -> Source must be set to "GitHub Actions".

Custom domain: `site/CNAME` is set to `getneocom.com`; DNS for getneocom.com is at Cloudflare.
DNS records needed:

- apex `getneocom.com`, A: 185.199.108.153, 185.199.109.153, 185.199.110.153, 185.199.111.153
- apex `getneocom.com`, AAAA: 2606:50c0:8000::153, 2606:50c0:8001::153, 2606:50c0:8002::153, 2606:50c0:8003::153
- `www`, CNAME: artem-shimanski.github.io

These records must be "DNS only" (grey cloud), not proxied; otherwise GitHub cannot issue the
certificate for "Enforce HTTPS". If proxying is wanted later, Cloudflare SSL mode must be "Full".

The domain must also be entered under Settings -> Pages -> Custom domain, with "Enforce HTTPS" enabled.

Old domain: `neocom.by` stays registered (paid until 2028) because shipped builds open
`https://neocom.by/privacy.html`. It must 301-redirect every path to the same path on
`https://getneocom.com` (e.g. a Cloudflare Redirect Rule), since GitHub Pages serves only one custom domain.
