"""Step A of the canonical-ANNY animation fixture: the numbers, from the anny env.

SYSTEMIC INVENTORY -- everything the source authors, and where it goes:
  vertices, faces                  -> mesh points/topology
  texture_coordinates (+indices)   -> primvars:st, faceVarying (21,334 coords)
  vertex_bone_indices/weights      -> UsdSkel joint primvars (9 influences; the
                                      twist fix rides in these weights)
  bone poses, parents, labels      -> Skeleton (worlds orthonormalised once)
  11 phenotype axes                -> residual shapes + one clip per axis
  52 facial actions                -> sparse shapes (fa_*)
  254 local-change dials           -> sparse shapes (lc_*)
  normals                          -> AUTHORED HERE (the source OBJ follows the
                                      compute-on-import convention and carries
                                      none; this generator is the asset's author)
Deferred, documented rather than dropped:
  skin textures (mpfb_*.jpg)       -> multi-layer MPFB material; compositing
                                      needs the Mitsuba bake that replaced the
                                      blocklisted Blender path (RFD 1122)
  body_parts_segmentation.yaml     -> carries part colors only; the per-vertex
                                      mapping lives elsewhere and is not yet read


Emits one npz: default-identity vertices and faces, the full joint set, a
phenotype blendshape (heavy minus default, per vertex), and which joint the
animation bends. Step B (usd env) writes the stage.

    anny-render-corpus/.pixi/envs/anny/python.exe make_anny_anim_fixture_a.py
"""
import json
import pathlib
import sys

import numpy as np
import torch

CORPUS = pathlib.Path(r"C:\weftspun-keypoints\6-datasource\anny-render-corpus")
sys.path.insert(0, str(CORPUS))
import anny_rig  # noqa: E402


def main():
    model = anny_rig.build_corpus_model(dtype=torch.float64)
    ident = anny_rig._identity_pose(model)
    with torch.no_grad():
        base = model(pose_parameters=ident, phenotype_kwargs={})
    base_v = base["vertices"][0]

    # Every phenotype axis and every facial action becomes a blendshape: the
    # delta of the axis at 1.0 against the default body. The twist fix needs no
    # shapes or bones -- it lives in vertex_bone_weights (anny_rig's header:
    # "NO TWIST BONE, NO RUNTIME STEP").
    # A phenotype is a clip, not a slider: joints animate default-rest ->
    # phenotype-rest while the shape weight rides 0 -> 1 on the same timeline.
    # LBS already displaces the skin once the joints move, so the shape is the
    # RESIDUAL against the skeleton-only deformation, or the change is counted
    # twice: delta = phenotype_verts - LBS(default_verts, weights, T_b) with
    # T_b = phenoWorld_b @ inv(defaultWorld_b).
    base_bp = base["bone_poses"][0].numpy()
    si = model.vertex_bone_indices.numpy()
    sw = model.vertex_bone_weights.numpy()

    def lbs_residual(pheno_v, pheno_bp):
        T = pheno_bp @ np.linalg.inv(base_bp)          # (B, 4, 4)
        vh = np.concatenate([base_v.numpy(), np.ones((len(si), 1))], axis=1)
        out = np.zeros((len(si), 3))
        for k in range(si.shape[1]):
            out += sw[:, k:k+1] * np.einsum("vij,vj->vi", T[si[:, k]][:, :3, :], vh)
        return pheno_v - out

    shapes = {}
    pheno_bone_poses = {}
    for label in model.phenotype_labels:
        with torch.no_grad():
            r = model(pose_parameters=ident, phenotype_kwargs={label: 1.0})
        shapes["ph_" + label] = lbs_residual(r["vertices"][0].numpy(),
                                             r["bone_poses"][0].numpy())
        pheno_bone_poses["ph_" + label] = r["bone_poses"][0].numpy()
    for label in model.facial_action_labels:
        with torch.no_grad():
            v = model(pose_parameters=ident, facial_actions={label: 1.0})["vertices"][0]
        shapes["fa_" + label] = (v - base_v).numpy()
    # The third authored shape family: 254 local-change dials (per-region fat,
    # muscle, scale). Pure vertex deltas like the facial actions; authored
    # sparsely downstream since each moves one region.
    for label in model.local_change_labels:
        with torch.no_grad():
            v = model(pose_parameters=ident,
                      local_changes_kwargs={label: 1.0})["vertices"][0]
        shapes["lc_" + label.replace("-", "_")] = (v - base_v).numpy()

    # Authored normals: this generator is the asset's author (the source OBJ
    # follows the compute-on-import convention and carries none), so smooth
    # area-weighted vertex normals are authored here, deterministically from
    # the source geometry. The converter chain stays pass-through.
    fv = base_v.numpy()[np.asarray(model.faces)]
    fn = np.cross(fv[:, 1] - fv[:, 0], fv[:, 2] - fv[:, 0])
    vn = np.zeros((len(base_v), 3))
    for c in range(3):
        np.add.at(vn, np.asarray(model.faces)[:, c], fn)
    vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)

    # Authored UVs: faceVarying texture coordinates with per-corner indices.
    m_uv = model.texture_coordinates.numpy()
    m_uvi = model.face_texture_coordinate_indices.numpy()

    labels = list(model.bone_labels)
    bend = next(i for i, n in enumerate(labels) if "lowerarm01.L" in n or "lowerarm" in n)

    out = pathlib.Path("anny_anim_fixture.npz")
    np.savez(out,
             verts=base_v.numpy(),
             faces=np.asarray(model.faces),
             bone_poses=base["bone_poses"][0].numpy(),
             parents=np.asarray(model.bone_parents),
             bend_joint=np.int64(bend),
             skin_indices=model.vertex_bone_indices.numpy(),
             skin_weights=model.vertex_bone_weights.numpy(),
             normals=vn,
             uv=m_uv, uv_face_indices=m_uvi,
             shape_names=np.array(sorted(shapes)),
             **{"shape_" + k: v for k, v in shapes.items()},
             **{"bones_" + k: v for k, v in pheno_bone_poses.items()})
    pathlib.Path("anny_anim_fixture.names.json").write_text(json.dumps(labels),
                                                            encoding="utf-8")
    print("verts %d, joints %d, bend joint %d (%s), shapes %d" % (
        base["vertices"].shape[1], len(labels), bend, labels[bend], len(shapes)))
    for k in ("ph_weight", "fa_jawOpen"):
        off = np.linalg.norm(shapes[k], axis=1)
        print("%s: max %.1f mm, moved verts %d" % (k, off.max() * 1e3, int((off > 1e-6).sum())))


if __name__ == "__main__":
    main()
