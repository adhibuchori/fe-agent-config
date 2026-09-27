# An image cropper's crop circle will not sit flush with its stage

**Applies to:** `react-easy-crop` (checked at 6.x) in avatar or banner croppers
**Status:** Permanent (library defaults, not a bug)

## Symptom

The round crop area never reaches the edges of its stage, leaving a band of dead space on two sides,
and the picture shows square corners inside a rounded container. Changing `border-radius`,
`overflow` or padding on a wrapper changes nothing.

## Root cause

Three defaults, and each hides behind the one before:

1. **`objectFit` defaults to `contain`**, so the media is letterboxed inside the stage; what looks
   rounded is the stage, while the media's own edge stays square.
2. **The crop size is `min(media, container)`**, so on a stage wider than it is tall the crop area
   is capped by the short side and can never fill the long one.
3. **`containerClassName` is applied to the container element itself**, not a descendant, so a rule
   written as `.my-cropper .reactEasyCrop_Container` matches nothing.

## Fix

All three together; any one alone looks almost right:

- `objectFit="cover"` on the cropper;
- a square stage (`aspect-ratio: 1 / 1`);
- style the container class itself (`.my-cropper { border-radius: inherit; }`).

If a gap survives, feed an explicit `cropSize` from a measured stage, which costs a
`ResizeObserver`: confirm the gap is still there first.

## How to catch it

Look at the cropper at a phone width and a desktop width; measure the crop area against the stage
in the inspector.

## Scope

Every crop UI built on this library.
