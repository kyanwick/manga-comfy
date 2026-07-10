# Scene grammar — turning a script line into a prompt

One image per ~3 seconds of narration. Each image is one **shot**, and a shot is
eight slots filled in order. Fill every slot or the model fills it for you, badly.

```
[1 COUNT+SUBJECT] [2 WARDROBE] [3 ACTION] [4 FRAMING]
[5 SETTING] [6 PERIOD] [7 LIGHT] [8 FX] + STYLE TAIL
```

**Style tail — always, unchanged:**

```
anime screencap, anime coloring, 2d, anime style,
masterpiece, best quality, absurdres, newest
```

**Negative — always, unchanged:**

```
3d, limited palette, pale color, ai-generated,
lowres, worst quality, low quality, bad anatomy, bad hands, extra digits,
watermark, signature, text, jpeg artifacts, blurry,
1girl, female, chibi, moe, photorealistic, photo, realistic,
modern, contemporary clothing, skyscraper, european architecture
```

The last line is the **period lock**. Without it, `desert marketplace` renders as a
Parisian square with Haussmann façades — verified 2026-07-09. With it, mudbrick.

---

## Slot 1 — count + subject

`1boy` · `1girl` · `2boys` · `no humans`

Then: `solo`, `mature male`, `young man`, `old man`, `crowd`, `multiple boys`

`no humans` is the correct opener for establishing shots, architecture, objects.

## Slot 2 — wardrobe

`robe` · `turban` · `hooded robe` · `cloak` · `hood` · `sandals` · `veil` ·
`shawl` · `head scarf` · `barefoot`

Verified: `robe, turban` reliably produces period-plausible Arabian dress.

## Slot 3 — action

`standing` · `walking` · `sitting` · `kneeling` · `praying` · `reading` ·
`pointing` · `looking up` · `looking away` · `carrying` · `holding book`

## Slot 4 — framing (Danbooru camera tags — these are real, tested)

| Tag | What you get | Face shown? |
|---|---|---|
| `wide shot, full body` | figure small, environment dominant | distant |
| `from behind` | back of subject | **no** |
| `cowboy shot` | mid-thigh up | yes |
| `upper body` | chest up | yes |
| `close-up, face focus` | face fills frame | yes |
| `profile, from side` | side-on | partial |
| `from above` / `from below` | camera height | varies |
| `looking away` / `facing away` | head turned off-camera | **no** |
| `silhouette` | shape only, backlit | **no** |
| `scenery` | pushes toward environment art | n/a |

Combine: `standing, from behind, wide shot, full body` — verified, clean
aniconism-safe frame. `walking, cowboy shot, from side` — verified, the strongest
character shot in testing.

## Slot 5 — setting

Be concrete. Nouns, not moods.

`desert town` · `narrow street` · `market stall` · `mosque interior` ·
`courtyard` · `stone library` · `oasis` · `sand dunes` · `desert cliff` ·
`tent` · `cave` · `arcade` · `pillar` · `archway` · `mudbrick wall`

## Slot 6 — period lock (positive side)

`arabian` · `middle eastern` · `mudbrick architecture` · `ancient` · `medieval`

**Do not skip these.** The negative period lock alone is not enough.

## Slot 7 — light

`dawn` · `dusk` · `golden hour` · `night` · `moonlight` · `lantern light` ·
`warm light` · `soft key light` · `rim light` · `backlighting` · `god rays` ·
`volumetric lighting` · `gradient sky`

## Slot 8 — atmosphere / FX

`detailed background` · `scenery` · `dust` · `sandstorm` · `light particles` ·
`embers` · `fog` · `depth of field` · `bokeh` · `cinematic composition`

`detailed background` earns its place — without it backgrounds go lazy.

---

## Aniconism

Prophets and Imams are not depicted. For any figure who must not show a face,
pick a framing from the **"Face shown? no"** rows above. Verified working:

```
standing, from behind, wide shot, full body
walking, from behind, facing away
silhouette, backlighting
```

If the model insists on turning the face toward camera, that is the failure mode
the spec predicted. Escalate to ControlNet — do not fight it with prompt weights.

---

## Worked examples (all verified on-pod)

**Establishing plate, no figure:**
```
no humans, arabian, middle eastern, mudbrick architecture, desert town,
narrow street, market stall, dusk, golden hour, warm light,
detailed background, scenery, <STYLE TAIL>
```
Caveat: this one drifted toward a gothic arcade. `no humans` establishing shots
need more concrete nouns than character shots — name the objects (`pottery`,
`baskets`, `awning`, `wooden door`) or you get generic architecture.

**Aniconism-safe wide:**
```
1boy, solo, mature male, short beard, robe, turban, standing, from behind,
wide shot, full body, arabian, middle eastern, mudbrick architecture,
desert town, narrow street, dusk, golden hour, warm light,
detailed background, scenery, <STYLE TAIL>
```

**Character shot (best result in testing):**
```
1boy, solo, mature male, short beard, robe, turban, walking, cowboy shot,
from side, arabian, middle eastern, mudbrick architecture, desert town,
narrow street, dusk, golden hour, warm light, detailed background, scenery,
<STYLE TAIL>
```

---

## Settings

| | |
|---|---|
| Checkpoint | `Illustrious-XL-v2.0` |
| LoRA | `anime_screencap-IllustriousV2` @ 1.0 |
| Sampler | `euler_ancestral` / `normal`, 30 steps |
| cfg | **6.0** wides · **5.0** closeups (highlights clip above that) |
| Latent | 1024 × 1536 |
| Seed | `increment` |

## Batching a scene list

Write one shot per entry into `/workspace/prompts/<name>.txt` in the
`Load Prompts From File (Inspire)` format (see `example_chapter.txt`), point the
node at it, queue once. Line order is panel order.

## Known drifts

- **Night skies go magenta.** `god rays` + a bright moon does it. Name the palette
  (`amber, deep blue sky, teal shadows`) if you want otherwise.
- **Closeups clip at cfg 6.0.** Creams blow out, colours go radioactive. Use 5.0.
- **`no humans` plates drift architectural.** Name objects, not just the place.
- **`ufotable` is not a tag.** Verified no-op. Describe the rendering instead:
  `god rays, volumetric lighting, light particles, embers, bloom, gradient sky,
  saturated`.
