# Prompt scaffold — Illustrious-XL v2.0

Tag block first, natural-language body after. v2.0's multi-level caption training
accepts both; the tag order below is the order the model was trained on
(arXiv:2409.19946).

## Order

`<person count>, <character names>, <rating>, <general tags>, <artist>, <score range>, <year modifier>`

## Positive template

```
1girl, solo, <character_lora_trigger>, rating_safe, <general tags>, masterpiece, best quality, absurdres, newest,

<natural-language scene description from the prompter skill>
```

Swap `1girl` / `1boy` / `2boys` / `no humans` to match the panel.
`no humans` is the correct opener for landscape, architecture, and object plates.

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
