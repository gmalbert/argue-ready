# argue ready

Static marketing site for argue ready, a live bench sheet for appellate counsel.

## Cloudflare

The deployable site is contained in [`site/`](site/).

### Cloudflare Pages

When connecting this repository in Cloudflare Pages, use:

- Framework preset: **None**
- Build command: leave blank
- Build output directory: `site`

### Cloudflare Workers Static Assets

The repository includes [`wrangler.toml`](wrangler.toml), which points Wrangler at `./site`.

After authenticating Wrangler with your Cloudflare account, deploy from the repository root:

```sh
npx wrangler deploy
```

No build step or package installation is required by the site itself.
