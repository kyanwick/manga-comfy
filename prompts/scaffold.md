# Prompt scaffold — Illustrious-XL v2.0

**CORRECTION 2026-07-10 — my earlier "tags only, no sentences" rule was wrong.**

Onoma's v2.0 release notes state: *"The model itself is highly compatible with
natural language sentences – it is far more robust, it is less likely to generate
multiple views or nonsense outputs."*

What I actually tested on 2026-07-09 was a **hybrid**: a tag block with two lines
of prose appended. That deleted the subject. A **pure** natural-language paragraph
(Onoma's own format, quality tags at the tail) does not — verified 2026-07-10, the
subject appeared, centred, in frame.

Current understanding, from a same-seed A/B:

- **Tags win on subject fidelity.** Prose ignored `bearded`, `hood pushed back`,
  `warm light`; tags honoured all three.
- **Prose wins on composition.** It centres the subject naturally.
- **Do not mix them.** The hybrid is what breaks.

**Also: v2.0 is an untuned base.** Onoma: *"The model itself is not trained with
aesthetic set... we release an 'untuned' base version, which should work as better
merging / training bases."* Raw v2.0 is a training substrate. A style LoRA is the
intended usage, not a workaround.

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

**Model:** Illustrious-XL-v2.0 + `anime_screencap-IllustriousV2.safetensors` @ 1.0
**Sampler:** `dpmpp_2s_ancestral_cfg_pp`, normal, 28 steps, **cfg 6.5**
**Latent:** **1248 x 1824** (2.3 MP)

Superseded 2026-07-10. Previously euler_ancestral / cfg 5.5 / 1024x1536 — that is
**30% below the model's native resolution** and the wrong sampler. v2.0 supports
512-1536 with w/h multiples of 32, up to 1:10 aspect; Onoma's own example runs
1824x1248. Their reference sampler is DPM++ 2S Ancestral CFG++, cfg ~6.5.

Positive spine:

```
1boy, solo, mature male, adult, short beard, stubble, short black hair,
calm serious expression, looking at viewer, close-up, face focus,
source_anime, anime screencap, movie still, key visual, cel shading, clean lineart,
soft key light, illuminated face, even lighting, natural skin tone,
depth of field, blurry background, bokeh, <setting>,
masterpiece, best quality, absurdres, newest
```

**Corrected 2026-07-09 from the LoRA author's own version notes** (civitai 345962,
Illustrious v2.0 build). I had guessed `source_anime`; it is not a trigger.

- **Trigger:** `anime screencap, anime coloring` (plus optional `2d, anime style`)
- **Negative:** `3d, limited palette, pale color, ai-generated`
- **Weight:** 1.0 (min 0.7, max 1.2) — not the 0.8 I tuned to
- **Sampler:** euler a + normal

`pale color` and `limited palette` in the negative are the documented fix for the
washed-out, low-contrast output I had been patching with invented tags like
`faded, washed out, low contrast`. Read the model card before tuning.

Caution: with `pale color` removed from the picture, saturation rises. At cfg 6.0
plus `illuminated face`, highlights clip — creams blow out and colours go
radioactive. Drop to cfg ~5.0 for closeups.

Negative — **short**. Onoma's own example uses five words.

```
worst quality, bad quality, text, watermark, signature
```

Add only what a specific shot proves it needs, e.g. `glowing eyes` for a
face-lit-from-below closeup, `modern, european architecture` for a period shot.

A 25-word negative accreted over one day of guessing produced **worse** images
than this five-word one. Verified same-seed 2026-07-10. Stop fighting the model
with tags it does not need.

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


## Composition — subject always, centred

Verified 2026-07-10. A frame with no subject at its focal point reads as empty.

- Positive: `centered, subject focus`, plus a concrete subject even on landscape
  plates (a lone figure, a lantern, a doorway).
- **Prop stacking deletes people.** `panel_03` with 8 prop nouns lost its figure
  entirely; the same subject with 2 prop nouns rendered perfectly. Depth on figure
  shots comes from *light and terrain*, not object count. Save the prop pile for
  `no humans` plates.
- Shot mix that reads well: roughly **70% wide / 20% medium / 10% close**.
