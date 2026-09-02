# flow-project

Godot project that exercises the IDTXFlow addon against the canonical ANNY
animation fixture.

## Fixture data

The animation fixture and its baked artifacts are not in this repository. Fetch
them from Hugging Face into the project root before opening the editor:

    hf download --repo-type dataset chibifire/anny-anim-fixture \
      anny_anim_fixture.npz anny_anim_fixture.names.json \
      render_test.tscn \
      --local-dir .

    hf download --repo-type dataset chibifire/anny-anim-fixture \
      anny_anim_test.usdz anny_anim_test.glb \
      --local-dir art/canonical_anny

The four fixture files (`.npz` source arrays, `.names.json` joint/blendshape
names, `.usdz` canonical stage, `.glb` delivery) plus the Godot scene
(`render_test.tscn`, 122 MB of baked animation tracks that exceed GitHub's
100 MB limit) are all `.gitignore`d here.

`make_anny_anim_fixture_b.py` regenerates the `.usdz` from the `.npz` inputs;
see [`chibifire/anny-anim-fixture`](https://huggingface.co/datasets/chibifire/anny-anim-fixture)
for the dataset card and provenance.
