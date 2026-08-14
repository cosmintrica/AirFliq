# AirFliq website

The animated product, privacy and support site for AirFliq, built with Next.js,
vinext and the OpenAI Sites runtime.

## Prerequisites

- Node.js `>=22.13.0`

## Quick Start

```bash
npm install
npm run dev
npm run build
```

The public experience lives in `app/page.tsx`, with shared styling in
`app/globals.css`. Privacy and support are first-class routes under `app/`.
The hosting project identifier is kept in `.openai/hosting.json`; no credentials
or runtime secrets belong in the repository.

## Useful Commands

- `npm run dev`: start local development
- `npm run build`: verify the vinext build output
- `npm test`: build and verify the rendered product, privacy and support pages

## Learn More

- [vinext Documentation](https://github.com/cloudflare/vinext)
