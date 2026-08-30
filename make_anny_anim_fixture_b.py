"""Step B: the stage, from the usd env. Reads step A's npz and writes
anny_anim_test.usda: the canonical mesh with its authored 9-influence skinning
(the twist fix lives in those weights), the full skeleton, the left forearm
keyed 0 -> 90 degrees over two seconds, and all 63 canonical blendshapes --
11 phenotype axes and 52 facial actions -- with ph_weight keyed 0 -> 1 -> 0
on the same clock and every other shape at rest.

    anny-render-corpus/.pixi/envs/usd/python.exe make_anny_anim_fixture_b.py
"""
import json
import pathlib

import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdSkel, Vt

HERE = pathlib.Path(__file__).parent
TPS, END = 24, 48  # two seconds


def matrix(m):
    return Gf.Matrix4d(*[float(x) for x in np.asarray(m).T.reshape(-1)])


def sanitise(name):
    return "".join(c if c.isalnum() or c == "_" else "_" for c in name)


def joint_paths(names, parents):
    paths = []
    for i, name in enumerate(names):
        me = sanitise(name)
        paths.append(me if parents[i] < 0 else paths[int(parents[i])] + "/" + me)
    return paths


def main():
    d = np.load(HERE / "anny_anim_fixture.npz")
    names = json.loads((HERE / "anny_anim_fixture.names.json").read_text(encoding="utf-8"))
    verts, faces = d["verts"], d["faces"]
    bone_poses, parents = d["bone_poses"], d["parents"]
    bend = int(d["bend_joint"])

    # usdz: a stored (uncompressed) package. The stage is authored as a crate
    # and packaged; the usda never exists on disk, the generators stay the
    # text-form source of truth.
    out = HERE / "art" / "canonical_anny" / "anny_anim_test.usdz"
    tmp = HERE / "art" / "canonical_anny" / "_anny_anim_test.usdc"
    stage = Usd.Stage.CreateNew(str(tmp))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.z)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    stage.SetStartTimeCode(0)
    stage.SetEndTimeCode(END)
    stage.SetTimeCodesPerSecond(TPS)

    root = UsdSkel.Root.Define(stage, Sdf.Path("/Subject"))
    stage.SetDefaultPrim(root.GetPrim())

    mesh = UsdGeom.Mesh.Define(stage, Sdf.Path("/Subject/Mesh"))
    mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(verts.astype(np.float32)))
    mesh.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(faces.reshape(-1).astype(np.int32)))
    mesh.CreateFaceVertexCountsAttr(Vt.IntArray.FromNumpy(np.full(faces.shape[0], 3, np.int32)))
    mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    mesh.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(d["normals"].astype(np.float32)))
    mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
    # Authored UVs, faceVarying with the source's own per-corner indices.
    st = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar(
        "st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.faceVarying)
    st.Set(Vt.Vec2fArray.FromNumpy(d["uv"].astype(np.float32)))
    st.SetIndices(Vt.IntArray.FromNumpy(d["uv_face_indices"].reshape(-1).astype(np.int32)))

    skel = UsdSkel.Skeleton.Define(stage, Sdf.Path("/Subject/Skeleton"))
    paths = joint_paths(names, parents)
    skel.CreateJointsAttr(Vt.TokenArray(paths))
    # ANNY bone bases carry shear that UsdSkel's per-joint T/R/S animation cannot
    # represent. Orthonormalising each WORLD matrix once, then deriving bind,
    # rest locals and the animation from that one clean chain, keeps everything
    # consistent; cleaning per-local instead compounds the error down the chain
    # and tears the skeleton apart.
    def clean_worlds(bp):
        out = []
        for m in bp:
            tf = Gf.Transform(matrix(m))
            w = Gf.Matrix4d(1.0)
            w.SetRotate(tf.GetRotation())
            w.SetTranslateOnly(tf.GetTranslation())
            out.append(w)
        return out

    world = clean_worlds(bone_poses)
    skel.CreateBindTransformsAttr(Vt.Matrix4dArray(world))
    rest = [world[i] if parents[i] < 0 else world[i] * world[int(parents[i])].GetInverse()
            for i in range(len(parents))]
    decomp = [Gf.Transform(m) for m in rest]
    skel.CreateRestTransformsAttr(Vt.Matrix4dArray(rest))

    binding = UsdSkel.BindingAPI.Apply(mesh.GetPrim())
    binding.CreateSkeletonRel().SetTargets([skel.GetPath()])
    n = verts.shape[0]
    # The canonical mapping, as authored: up to 9 influences per vertex,
    # rows already normalised. Nothing is resampled here.
    si, sw = d["skin_indices"], d["skin_weights"]
    k = si.shape[1]
    binding.CreateJointIndicesPrimvar(constant=False, elementSize=int(k)).Set(
        Vt.IntArray.FromNumpy(si.reshape(-1).astype(np.int32)))
    binding.CreateJointWeightsPrimvar(constant=False, elementSize=int(k)).Set(
        Vt.FloatArray.FromNumpy(sw.reshape(-1).astype(np.float32)))

    # Every phenotype axis and facial action, authored as its own blendshape.
    # Facial actions move a small region, so they are authored sparsely; the
    # dense phenotype axes carry one offset per point.
    shape_names = [str(n) for n in d["shape_names"]]
    targets = []
    for name in shape_names:
        offs = d["shape_" + name].astype(np.float32)
        moved = np.linalg.norm(offs, axis=1) > 1e-7
        shape = UsdSkel.BlendShape.Define(stage, Sdf.Path("/Subject/Mesh/" + name))
        if moved.sum() < 0.5 * len(offs):
            idx = np.nonzero(moved)[0]
            shape.CreateOffsetsAttr(Vt.Vec3fArray.FromNumpy(offs[idx]))
            shape.CreatePointIndicesAttr(Vt.IntArray.FromNumpy(idx.astype(np.int32)))
        else:
            shape.CreateOffsetsAttr(Vt.Vec3fArray.FromNumpy(offs))
        targets.append(shape.GetPath())
    binding.CreateBlendShapesAttr(Vt.TokenArray(shape_names))
    binding.CreateBlendShapeTargetsRel().SetTargets(targets)

    # Eleven phenotype CLIPS on one timeline, 2 s per segment: each axis keys
    # its joints default-rest -> phenotype-rest -> back in sync with its own
    # shape weight, so scrubbing any segment is that axis's slider and the
    # skeleton moves with the body. ph_weight leads (the tests watch the first
    # segment) and carries the forearm-bend overlay; the rest follow sorted.
    ph_axes = ["ph_weight"] + sorted(n for n in shape_names
                                     if n.startswith("ph_") and n != "ph_weight")
    ph_decomp = {}
    for name in ph_axes:
        wl = clean_worlds(d["bones_" + name])
        rl = [wl[i] if parents[i] < 0 else wl[i] * wl[int(parents[i])].GetInverse()
              for i in range(len(parents))]
        ph_decomp[name] = [Gf.Transform(m) for m in rl]

    end_all = END * len(ph_axes)
    stage.SetEndTimeCode(end_all)
    anim = UsdSkel.Animation.Define(stage, Sdf.Path("/Subject/Skeleton/Anim"))
    anim.CreateJointsAttr(Vt.TokenArray(paths))
    rots = anim.CreateRotationsAttr()
    trans = anim.CreateTranslationsAttr()
    scales = anim.CreateScalesAttr()
    anim.CreateBlendShapesAttr(Vt.TokenArray(shape_names))
    w = anim.CreateBlendShapeWeightsAttr()

    def set_joints(tc, dc, bend_deg):
        q = [Gf.Quatf(tf.GetRotation().GetQuat()) for tf in dc]
        t = [Gf.Vec3f(tf.GetTranslation()) for tf in dc]
        extra = Gf.Quatf(Gf.Rotation(Gf.Vec3d(1, 0, 0), bend_deg).GetQuat())
        q[bend] = q[bend] * extra
        rots.Set(Vt.QuatfArray(q), Usd.TimeCode(tc))
        trans.Set(Vt.Vec3fArray(t), Usd.TimeCode(tc))
        scales.Set(Vt.Vec3hArray([Gf.Vec3h(1, 1, 1)] * len(paths)), Usd.TimeCode(tc))

    def set_weights(tc, axis_name, v):
        vals = np.zeros(len(shape_names), np.float32)
        if axis_name is not None:
            vals[shape_names.index(axis_name)] = v
        w.Set(Vt.FloatArray.FromNumpy(vals), Usd.TimeCode(tc))

    for seg, name in enumerate(ph_axes):
        t0 = seg * END
        bend_deg = 90.0 if seg == 0 else 0.0
        set_joints(t0, decomp, 0.0)
        set_joints(t0 + END // 2, ph_decomp[name], bend_deg)
        set_joints(t0 + END, decomp, 0.0)
        set_weights(t0, None, 0.0)
        set_weights(t0 + END // 2, name, 1.0)
        set_weights(t0 + END, None, 0.0)
    UsdSkel.BindingAPI.Apply(skel.GetPrim()).CreateAnimationSourceRel().SetTargets(
        [anim.GetPath()])

    stage.Save()
    del stage
    from pxr import UsdUtils
    if out.exists():
        out.unlink()
    ok = UsdUtils.CreateNewUsdzPackage(str(tmp), str(out))
    tmp.unlink()
    if not ok:
        raise SystemExit("usdz packaging failed")
    print(f"wrote {out.name}: {n} verts, {len(paths)} joints, bend joint "
          f"{names[bend]}, {len(shape_names)} blendshapes")


if __name__ == "__main__":
    main()
