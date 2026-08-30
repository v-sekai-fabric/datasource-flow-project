"""Rebuild the morph stress fixture from Khronos's MorphStressTest.glb.

Reads the GLB directly (json + buffer, no engine, no Blender) and authors
art/stress_test_animation/morph_stress_test.usda: the mesh rigid-bound to a
one-joint skeleton, every morph target as a UsdSkelBlendShape, and the sampled
weights animation as blendShapeWeights time samples.

    anny-render-corpus/.pixi/envs/usd/python.exe make_morph_stress_from_gltf.py <MorphStressTest.glb>
"""
import json
import pathlib
import struct
import sys

import numpy as np
from pxr import Gf, Sdf, Usd, UsdGeom, UsdSkel, Vt

HERE = pathlib.Path(__file__).parent


def read_accessor(doc, buf, idx):
    acc = doc["accessors"][idx]
    view = doc["bufferViews"][acc["bufferView"]]
    off = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    dt = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[acc["componentType"]]
    a = np.frombuffer(buf, dtype=dt, count=acc["count"] * ncomp, offset=off)
    return a.reshape(acc["count"], ncomp) if ncomp > 1 else a


def main(glb_path):
    raw = pathlib.Path(glb_path).read_bytes()
    assert raw[:4] == b"glTF"
    jl = struct.unpack_from("<I", raw, 12)[0]
    doc = json.loads(raw[20:20 + jl])
    bin_off = 20 + jl + 8
    buf = raw[bin_off:]

    mesh = doc["meshes"][0]
    prim = mesh["primitives"][0]
    pts = read_accessor(doc, buf, prim["attributes"]["POSITION"]).astype(np.float32)
    idxs = read_accessor(doc, buf, prim["indices"]).astype(np.int32).reshape(-1)
    names = [n.replace(" ", "_") for n in mesh.get("extras", {}).get(
        "targetNames", [f"target_{i}" for i in range(len(prim["targets"]))])]
    targets = [read_accessor(doc, buf, t["POSITION"]).astype(np.float32)
               for t in prim["targets"]]

    # The weights animation: one sampler whose output is count*len(names) floats.
    anim = doc["animations"][0]
    ch = next(c for c in anim["channels"] if c["target"]["path"] == "weights")
    smp = anim["samplers"][ch["sampler"]]
    times = read_accessor(doc, buf, smp["input"]).astype(np.float64)
    weights = read_accessor(doc, buf, smp["output"]).astype(np.float32).reshape(len(times), len(names))

    tps = 24.0
    out = HERE / "art" / "stress_test_animation" / "morph_stress_test.usda"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    stage = Usd.Stage.CreateNew(str(out))
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    stage.SetTimeCodesPerSecond(tps)
    stage.SetStartTimeCode(float(times[0]) * tps)
    stage.SetEndTimeCode(float(times[-1]) * tps)

    root = UsdSkel.Root.Define(stage, Sdf.Path("/Morph"))
    stage.SetDefaultPrim(root.GetPrim())
    skel = UsdSkel.Skeleton.Define(stage, Sdf.Path("/Morph/Skel"))
    skel.CreateJointsAttr(["root"])
    ident = Gf.Matrix4d(1.0)
    skel.CreateBindTransformsAttr([ident])
    skel.CreateRestTransformsAttr([ident])

    m = UsdGeom.Mesh.Define(stage, Sdf.Path("/Morph/Mesh"))
    m.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(pts))
    m.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(idxs))
    m.CreateFaceVertexCountsAttr(Vt.IntArray.FromNumpy(np.full(len(idxs) // 3, 3, np.int32)))
    m.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
    nrm_idx = prim["attributes"].get("NORMAL")
    if nrm_idx is not None:
        m.CreateNormalsAttr(Vt.Vec3fArray.FromNumpy(read_accessor(doc, buf, nrm_idx).astype(np.float32)))
        m.SetNormalsInterpolation(UsdGeom.Tokens.vertex)

    binding = UsdSkel.BindingAPI.Apply(m.GetPrim())
    binding.CreateSkeletonRel().SetTargets([skel.GetPath()])
    n = len(pts)
    binding.CreateJointIndicesPrimvar(constant=False, elementSize=1).Set(
        Vt.IntArray.FromNumpy(np.zeros(n, np.int32)))
    binding.CreateJointWeightsPrimvar(constant=False, elementSize=1).Set(
        Vt.FloatArray.FromNumpy(np.ones(n, np.float32)))

    shape_paths = []
    for name, offs in zip(names, targets):
        bs = UsdSkel.BlendShape.Define(stage, Sdf.Path("/Morph/Mesh/" + name))
        bs.CreateOffsetsAttr(Vt.Vec3fArray.FromNumpy(offs))
        shape_paths.append(bs.GetPath())
    binding.CreateBlendShapesAttr(Vt.TokenArray(names))
    binding.CreateBlendShapeTargetsRel().SetTargets(shape_paths)

    a = UsdSkel.Animation.Define(stage, Sdf.Path("/Morph/Skel/Anim"))
    a.CreateJointsAttr(Vt.TokenArray(["root"]))
    a.CreateRotationsAttr().Set(Vt.QuatfArray([Gf.Quatf(1, 0, 0, 0)]), Usd.TimeCode(float(times[0]) * tps))
    a.CreateTranslationsAttr().Set(Vt.Vec3fArray([Gf.Vec3f(0, 0, 0)]), Usd.TimeCode(float(times[0]) * tps))
    a.CreateScalesAttr().Set(Vt.Vec3hArray([Gf.Vec3h(1, 1, 1)]), Usd.TimeCode(float(times[0]) * tps))
    a.CreateBlendShapesAttr(Vt.TokenArray(names))
    w = a.CreateBlendShapeWeightsAttr()
    for t, row in zip(times, weights):
        w.Set(Vt.FloatArray.FromNumpy(row), Usd.TimeCode(float(t) * tps))
    UsdSkel.BindingAPI.Apply(skel.GetPrim()).CreateAnimationSourceRel().SetTargets([a.GetPath()])
    stage.Save()

    per = {nm: (float(weights[:, i].min()), float(weights[:, i].max()))
           for i, nm in enumerate(names)}
    print(f"wrote {out.name}: {n} verts, {len(names)} shapes, {len(times)} weight samples")
    for nm, (lo, hi) in per.items():
        print(f"  {nm}: [{lo:.4f}, {hi:.4f}]")


if __name__ == "__main__":
    main(sys.argv[1])
