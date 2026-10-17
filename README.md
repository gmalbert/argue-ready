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

## iOS app

The ArgueReady iOS and Apple Watch app source lives in [`ios/`](ios/). Open
[`ArgueReady.xcodeproj`](ios/ArgueReady.xcodeproj) or regenerate it from
[`project.yml`](ios/project.yml) with XcodeGen. The project includes the
ArgueReady app targets and the shared speech, coverage, transcript, settings,
and Watch connectivity sources used by its iPhone and Watch apps.
