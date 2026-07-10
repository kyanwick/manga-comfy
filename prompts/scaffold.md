# Prompt scaffold — Illustrious-XL v2.0

**Tags only. No sentences.** Verified on-pod 2026-07-09: appending two lines of
prose to a `1girl, solo` prompt made the model render an empty marketplace with
**no person in it**, in soft painterly mush. The identical scene as pure tags
produced the girl, in clean anime linework. Short prose at cfg 7.0 kept the
figure but shrank it to the frame edge and hallucinated glyphs in the corner.

The paper's multi-level captioning does not mean prose *competes well* — SDXL's
CLIP truncates at 77 tokens per chunk, and every word of narrative steals
attention from the subject tags.

This is why `oberas-image-prompter-v2` output cannot be pasted in directly: it
emits Midjourney prose. Each beat must be **translated** into a tag block.

Tag order below is the order the model was trained on (arXiv:2409.19946).

## Order

`<person count>, <character names>, <rating>, <general tags>, <artist>, <score range>, <year modifier>`

## Positive template

Comma-separated tags, ~20–40 of them. No verbs in sentences.

```
<count>, solo, <hair/identity>, <clothing>, <pose/action>, <camera/framing>,
<setting>, <time/lighting>, masterpiece, best quality, absurdres, newest
```

Worked example (rendered a real figure at 1024×1536):

```
1girl, solo, brown hair, hijab, long coat, standing, from behind,
wide shot, desert marketplace, market stall, awning, crowd,
dawn, sunset, golden hour, backlighting,
masterpiece, best quality, absurdres, newest
```

Swap `1girl` / `1boy` / `2boys` / `no humans` to match the panel.
`no humans` is the correct opener for landscape, architecture, and object plates.

## Period drift — the sparse-concept problem

Danbooru has anime slice-of-life markets, not 7th-century Arabian ones. Left
alone, `desert marketplace` renders as a **Parisian square** with Haussmann
façades and modern coats; `lantern` becomes a Victorian lamppost. The paper names
this: sparse concepts with thin training data degrade.

Pin the period explicitly in positives — `arabian`, `middle eastern`,
`adobe architecture`, `mudbrick`, `desert town`, `medieval`, `robe`, `turban` —
and push back in the negative:

```
modern, contemporary clothing, city, skyscraper, european architecture,
cobblestone street, streetlamp, power lines
```

If tags alone can't hold the period, ControlNet is the lever. Do not fight it
with prompt weights.

## Resolution

Generate **1024 × 1536** (native 9:16). The old 3:2-then-pan plan was a Midjourney
habit — there is no reason to crop when you can render the target ratio directly.

## Pinned negative — do not omit

The paper's No-Dropout Tokens guarantee 100% recognition of provocative concepts.
They are suppressed at inference, not absent from the model. Every generation
carries this negative.

```
nsfw, nude, nipples, cleavage, revealing clothes, suggestive, lowres, worst quality, low quality, bad anatomy, bad hands, extra digits, fewer digits, watermark, signature, text, error, jpeg artifacts, blurry
```

`text` and `signature` in the negative are deliberate: the model cannot render
legible words. Panels are plates. Arabic calligraphy, ayah text, and speech
bubbles are composited downstream in Remotion.

## Resolutions

| Use | Size |
|---|---|
| Oberas (3:2, pans to 9:16) | 1536 × 1024 |
| DeenWell cover (9:16) | 1024 × 1536 |
| DeenWell square | 1216 × 1216 |

## Aniconism

Prophets and Imams are not depicted. Anime models are trained on
character-centric composition and resist faceless framing. Start with negatives
plus `from behind`, `facing away`, `silhouette`, `back turned`. If the model
keeps producing faces, escalate to ControlNet — do not fight it with prompt
weights.

## Oberas screencap recipe — verified on-pod 2026-07-09

Modern TV-anime look (Blue Lock / Jujutsu Kaisen register): thick clean lineart,
flat cel shading with hard terminators, realistic adult proportions, lit face
against dark bokeh.

**Model:** Illustrious-XL-v2.0 + `anime_screencap-IllustriousV2.safetensors`
**LoRA strength:** 0.8 model / 0.8 clip (0.6 is too weak, 1.0 crushes contrast)
**Sampler:** euler_ancestral, normal, 30 steps, cfg 5.5
**Latent:** 1024 x 1536

Positive spine:

```
1boy, solo, mature male, adult, short beard, stubble, short black hair,
calm serious expression, looking at viewer, close-up, face focus,
source_anime, anime screencap, movie still, key visual, cel shading, clean lineart,
soft key light, illuminated face, even lighting, natural skin tone,
depth of field, blurry background, bokeh, <setting>,
masterpiece, best quality, absurdres, newest
```

`source_anime, anime screencap` is the LoRA's own trigger. Keep it.

Negative — the second half is load-bearing:

```
nsfw, lowres, worst quality, low quality, bad anatomy, bad hands, extra digits,
watermark, signature, text, jpeg artifacts, blurry,
1girl, female, child, chibi, moe, big eyes, sketch, painterly, soft shading,
3d, photorealistic, realistic, photo,
dark, underexposed, silhouette, backlighting, glowing eyes, red eyes
```

Two hard-won notes:

- **Pushing `1girl, female, moe, big eyes` into the negative is what unlocks adult
  male cel-shade.** Illustrious defaults to anime-waifu otherwise.
- **`backlighting` + `dark background` + `high contrast` silhouette the face once
  the LoRA is on.** The LoRA amplifies contrast. Light the face explicitly
  (`soft key light, illuminated face, even lighting`) and put the darkness in the
  *background* tags, not the lighting tags.

### Face-transfer options — all NC except one

| Route | Likeness | Licence |
|---|---|---|
| IPAdapter FaceID | medium | ❌ non-commercial (InsightFace face packs) |
| InstantID | good | ❌ Apache code, but requires NC antelopev2 |
| img2img from a photo | rough, one-off | ✅ clean |
| **Personal character LoRA** | **strong, reusable** | ✅ **clean — dataset is you** |

Anything touching InsightFace inherits non-commercial. For a monetised brand the
only clean identity route is training a LoRA on your own photos.
