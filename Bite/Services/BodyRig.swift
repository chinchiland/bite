import Foundation

/// MakeHuman's CC0 body (makehumancommunity/makehuman), as tools/body/pack_body.py packs it into
/// body.bin: the skin and the eyeballs at rest, a young man's and a young woman's shape, the nine
/// muscle by weight targets of each, and a 20-bone skeleton with MakeHuman's own skin weights.
/// Foundation only, so the tests run it on Linux.
final class BodyMesh {
    struct Bone {
        let name: String
        let parent: Int
        let joint: [Int]
    }

    struct Delta {
        let scale: Float
        let values: [Int16]
    }

    enum Failure: Error { case format }

    let count: Int
    let indices: [UInt16]
    let span: Float
    let base: [Sex: [Float]]
    let deltas: [Sex: [Delta]]
    let eye: [UInt8]
    let bones: [Bone]
    let boneIndex: [UInt8]
    let boneWeight: [UInt8]
    let id: [String: Int]
    /// Weight on the arms, on the neck and head, and on the parts that never jiggle.
    let arm: [Float]
    let head: [Float]
    let still: [Float]
    /// Where clothes go, from each body at rest: height (0 at the soles, 1 at the crown) and, on
    /// the arms and the shoulders they hang from, how far from the shoulder to the wrist (-1 off
    /// them), so a sleeve meets the tee with no skin between.
    let band: [Sex: [Float]]
    let armT: [Sex: [Float]]
    let mid: Float
    let feet: Float

    /// Xcode copies a synchronized folder's resources to the bundle's top, or keeps the folder.
    static let shared: BodyMesh? = (Bundle.main.url(forResource: "body", withExtension: "bin")
        ?? Bundle.main.url(forResource: "body", withExtension: "bin", subdirectory: "Body"))
        .flatMap { try? Data(contentsOf: $0, options: .mappedIfSafe) }
        .flatMap { try? BodyMesh(data: $0) }

    init(data: Data) throws {
        var read = Reader(data: data)
        guard read.bytes(4) == Array("BODY".utf8) else { throw Failure.format }
        let n = Int(read.u32()), t = Int(read.u32())
        count = n
        span = read.f32()
        var base: [Sex: [Float]] = [:], deltas: [Sex: [Delta]] = [:]
        for sex in [Sex.male, .female] { base[sex] = read.array(n * 3, of: Float.self) }
        for sex in [Sex.male, .female] {
            deltas[sex] = (0..<9).map { _ in let scale = read.f32(); return Delta(scale: scale, values: read.array(n * 3, of: Int16.self)) }
        }
        self.base = base
        self.deltas = deltas
        indices = read.array(t * 3, of: UInt16.self)
        eye = read.bytes(n)
        let boneCount = Int(read.u8())
        var bones: [Bone] = []
        for _ in 0..<boneCount {
            let parent = Int(read.u8()), length = Int(read.u8())
            let name = String(decoding: read.bytes(length), as: UTF8.self)
            let joints = read.array(Int(read.u32()), of: UInt32.self).map(Int.init)
            bones.append(Bone(name: name, parent: parent == 255 ? -1 : parent, joint: joints))
        }
        self.bones = bones
        let boneIndex = read.bytes(n * 4), boneWeight = read.bytes(n * 4)
        self.boneIndex = boneIndex
        self.boneWeight = boneWeight
        guard read.offset == data.count else { throw Failure.format }
        let id = Dictionary(uniqueKeysWithValues: bones.enumerated().map { ($1.name, $0) })
        self.id = id

        let weight = { (names: [String]) -> [Float] in
            let set = Set(names.compactMap { id[$0] })
            var out = [Float](repeating: 0, count: n)
            for v in 0..<n { for k in 0..<4 where set.contains(Int(boneIndex[v * 4 + k])) { out[v] += Float(boneWeight[v * 4 + k]) / 255 } }
            return out
        }
        let arm = weight(["upperarm.L", "lowerarm.L", "hand.L", "upperarm.R", "lowerarm.R", "hand.R"])
        self.arm = arm
        head = weight(["neck", "head"])
        still = weight(["head", "neck", "hand.L", "hand.R", "foot.L", "foot.R", "shin.L", "shin.R", "lowerarm.L", "lowerarm.R"])

        var band: [Sex: [Float]] = [:], armT: [Sex: [Float]] = [:]
        for sex in [Sex.male, .female] {
            let p = base[sex] ?? []
            var lo = Float.infinity, hi = -Float.infinity
            for v in 0..<n { lo = min(lo, p[v * 3 + 1]); hi = max(hi, p[v * 3 + 1]) }
            band[sex] = (0..<n).map { (p[$0 * 3 + 1] - lo) / (hi - lo) }
            let joints = BodyShape.joints(of: p, bones: bones)
            var along = [Float](repeating: -1, count: n)
            for side in ["L", "R"] {
                guard let s = id["upperarm.\(side)"], let w = id["hand.\(side)"] else { continue }
                let axis = joints[w] - joints[s], length = (axis * axis).sum()
                for v in 0..<n where arm[v] >= 0.12 && (p[v * 3] > 0) == (axis.x > 0) {
                    let x = SIMD3(p[v * 3], p[v * 3 + 1], p[v * 3 + 2]) - joints[s]
                    along[v] = max((x * axis).sum() / length, -0.5)
                }
            }
            armT[sex] = along
        }
        self.band = band
        self.armT = armT
        let male = base[.male] ?? []
        var lo = Float.infinity, hi = -Float.infinity
        for v in 0..<n { lo = min(lo, male[v * 3 + 1]); hi = max(hi, male[v * 3 + 1]) }
        mid = (lo + hi) / 2
        feet = lo
    }

    /// Little-endian reads, unaligned, the way the packer writes.
    private struct Reader {
        let data: Data
        var offset = 0

        mutating func bytes(_ count: Int) -> [UInt8] {
            defer { offset += count }
            return [UInt8](data[data.startIndex + offset ..< data.startIndex + offset + count])
        }

        mutating func array<T>(_ count: Int, of type: T.Type) -> [T] {
            let size = MemoryLayout<T>.stride * count
            defer { offset += size }
            return [T](unsafeUninitializedCapacity: count) { buffer, initialized in
                data.withUnsafeBytes { raw in
                    _ = memcpy(buffer.baseAddress!, raw.baseAddress!.advanced(by: offset), size)
                }
                initialized = count
            }
        }

        mutating func u8() -> UInt8 { bytes(1)[0] }
        mutating func u32() -> UInt32 { array(1, of: UInt32.self)[0] }
        mutating func f32() -> Float { array(1, of: Float.self)[0] }
    }
}

/// One body at rest, for MakeHuman's muscle and weight sliders (0 to 1, 0.5 the average body):
/// its shape, its joints, its normals, and, when asked, the fat under its skin.
struct BodyShape {
    let sex: Sex
    let rest: [Float]
    let joints: [SIMD3<Float>]
    let normals: [Float]
    /// How far the skin stands off the same body with almost no fat; empty when not asked for.
    let fat: [Float]
    /// How much each vertex swings with the body's movement: its fat, off the parts that don't jiggle.
    let jiggle: [Float]
    /// How wide the body is at the hips and the waist, so hands rest beside it and never inside.
    let hipWidth: Float
    let waistWidth: Float

    init(mesh: BodyMesh, sex: Sex, muscle: Double, weight: Double, bare: Double?) {
        self.sex = sex
        let rest = BodyShape.shape(mesh: mesh, sex: sex, muscle: muscle, weight: weight)
        self.rest = rest
        joints = BodyShape.joints(of: rest, bones: mesh.bones)
        normals = BodyShape.normals(of: rest, indices: mesh.indices)
        var fat: [Float] = [], jiggle: [Float] = []
        if let bare {
            let thin = BodyShape.shape(mesh: mesh, sex: sex, muscle: muscle, weight: bare)
            fat = (0..<mesh.count).map { v in
                let d = SIMD3(rest[v * 3] - thin[v * 3], rest[v * 3 + 1] - thin[v * 3 + 1], rest[v * 3 + 2] - thin[v * 3 + 2])
                return (d * d).sum().squareRoot()
            }
            jiggle = (0..<mesh.count).map { v in pow(min(max(fat[v] / 0.55, 0), 1), 1.3) * min(max(1 - mesh.still[v], 0), 1) }
        }
        self.fat = fat
        self.jiggle = jiggle
        var hip: Float = 0, waist: Float = 0
        let band = mesh.band[sex] ?? []
        for v in 0..<mesh.count where mesh.arm[v] <= 0.2 {
            let x = abs(rest[v * 3])
            if band[v] > 0.47 && band[v] < 0.53 { hip = max(hip, x) }
            if band[v] > 0.56 && band[v] < 0.61 { waist = max(waist, x) }
        }
        hipWidth = hip
        waistWidth = waist
    }

    /// The base shape plus the muscle by weight targets, mixed the way MakeHuman mixes its sliders.
    static func shape(mesh: BodyMesh, sex: Sex, muscle: Double, weight: Double) -> [Float] {
        func levels(_ v: Double) -> [Float] {
            let v = Float(min(max(v, 0), 1))
            return v < 0.5 ? [1 - 2 * v, 2 * v, 0] : [0, 2 - 2 * v, 2 * v - 1]
        }
        var out = mesh.base[sex] ?? []
        let mw = levels(muscle), ww = levels(weight), deltas = mesh.deltas[sex] ?? []
        out.withUnsafeMutableBufferPointer { o in
            for i in 0..<3 {
                for j in 0..<3 {
                    let f = mw[i] * ww[j]
                    guard f > 1e-4, i * 3 + j < deltas.count else { continue }
                    let s = f * deltas[i * 3 + j].scale
                    deltas[i * 3 + j].values.withUnsafeBufferPointer { q in
                        for v in 0..<min(o.count, q.count) { o[v] += Float(q[v]) * s }
                    }
                }
            }
        }
        return out
    }

    /// Each bone's head: the middle of its group of joint vertices.
    static func joints(of p: [Float], bones: [BodyMesh.Bone]) -> [SIMD3<Float>] {
        bones.map { bone in
            var sum = SIMD3<Float>(0, 0, 0)
            for v in bone.joint { sum += SIMD3(p[v * 3], p[v * 3 + 1], p[v * 3 + 2]) }
            return sum / Float(max(bone.joint.count, 1))
        }
    }

    static func normals(of p: [Float], indices: [UInt16]) -> [Float] {
        var out = [Float](repeating: 0, count: p.count)
        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]) * 3, b = Int(indices[t + 1]) * 3, c = Int(indices[t + 2]) * 3
            let u = SIMD3(p[b] - p[a], p[b + 1] - p[a + 1], p[b + 2] - p[a + 2]), w = SIMD3(p[c] - p[a], p[c + 1] - p[a + 1], p[c + 2] - p[a + 2])
            let n = Rig.cross(u, w)
            for k in [a, b, c] { out[k] += n.x; out[k + 1] += n.y; out[k + 2] += n.z }
            t += 3
        }
        var v = 0
        while v < out.count {
            let l = max((out[v] * out[v] + out[v + 1] * out[v + 1] + out[v + 2] * out[v + 2]).squareRoot(), 1e-9)
            out[v] /= l; out[v + 1] /= l; out[v + 2] /= l
            v += 3
        }
        return out
    }
}

/// A rotation and a translation.
struct Affine {
    var r: Rig.Mat3
    var t: SIMD3<Float>

    static let identity = Affine(r: .identity, t: SIMD3(0, 0, 0))

    func apply(_ v: SIMD3<Float>) -> SIMD3<Float> { r.apply(v) + t }
    func then(_ other: Affine) -> Affine { Affine(r: r * other.r, t: r.apply(other.t) + t) }
}

/// Where a hand reaches: a point near a bone (its rest head plus an offset that turns with it,
/// written for the left side and mirrored), pushed past the hips or the waist when asked, and
/// which way the elbow points.
struct Reach: Equatable {
    enum Flank { case hip, waist }
    var bone: String
    var at: SIMD3<Float>
    var pole: SIMD3<Float>
    var flank: Flank? = nil
}

/// A pose: angles in degrees for the trunk, legs and hands, about x (a bone hanging down swings
/// forward with a negative angle), y (twist) and z (toward the body's left is positive), each
/// about the bone's head; each arm reaching for a target, or between two while a pose changes.
struct Pose {
    var angles: [String: SIMD3<Float>]
    var arms: [String: (from: Reach, to: Reach, k: Float)]
    var offset = SIMD3<Float>(0, 0, 0)
}

enum Rig {
    /// A 3x3 matrix by rows.
    struct Mat3 {
        var x: SIMD3<Float>
        var y: SIMD3<Float>
        var z: SIMD3<Float>

        static let identity = Mat3(x: SIMD3(1, 0, 0), y: SIMD3(0, 1, 0), z: SIMD3(0, 0, 1))

        func apply(_ v: SIMD3<Float>) -> SIMD3<Float> { SIMD3((x * v).sum(), (y * v).sum(), (z * v).sum()) }
        var transposed: Mat3 { Mat3(x: SIMD3(x.x, y.x, z.x), y: SIMD3(x.y, y.y, z.y), z: SIMD3(x.z, y.z, z.z)) }

        static func * (a: Mat3, b: Mat3) -> Mat3 {
            let bt = b.transposed
            func row(_ r: SIMD3<Float>) -> SIMD3<Float> { SIMD3((r * bt.x).sum(), (r * bt.y).sum(), (r * bt.z).sum()) }
            return Mat3(x: row(a.x), y: row(a.y), z: row(a.z))
        }
    }

    static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    static func length(_ v: SIMD3<Float>) -> Float { (v * v).sum().squareRoot() }
    static func unit(_ v: SIMD3<Float>) -> SIMD3<Float> { v / max(length(v), 1e-9) }

    /// Degrees about z, then x, then y.
    static func rotation(_ e: SIMD3<Float>) -> Mat3 {
        let r = e * (.pi / 180), cx = cos(r.x), sx = sin(r.x), cy = cos(r.y), sy = sin(r.y), cz = cos(r.z), sz = sin(r.z)
        let rz = Mat3(x: SIMD3(cz, -sz, 0), y: SIMD3(sz, cz, 0), z: SIMD3(0, 0, 1))
        let rx = Mat3(x: SIMD3(1, 0, 0), y: SIMD3(0, cx, -sx), z: SIMD3(0, sx, cx))
        let ry = Mat3(x: SIMD3(cy, 0, sy), y: SIMD3(0, 1, 0), z: SIMD3(-sy, 0, cy))
        return ry * (rx * rz)
    }

    /// The smallest rotation taking direction a to direction b.
    static func between(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Mat3 {
        let a = unit(a), b = unit(b), c = min(max((a * b).sum(), -1), 1), axis = cross(a, b), s = length(axis)
        guard s > 1e-6 else { return .identity }
        let k = axis / s, t = 1 - c
        return Mat3(
            x: SIMD3(t * k.x * k.x + c, t * k.x * k.y - s * k.z, t * k.x * k.z + s * k.y),
            y: SIMD3(t * k.x * k.y + s * k.z, t * k.y * k.y + c, t * k.y * k.z - s * k.x),
            z: SIMD3(t * k.x * k.z - s * k.y, t * k.y * k.z + s * k.x, t * k.z * k.z + c)
        )
    }

    private static func aim(_ shape: BodyShape, _ mesh: BodyMesh, _ m: [Affine], side: String, _ reach: Reach) -> (target: SIMD3<Float>, pole: SIMD3<Float>) {
        let sign: Float = side == "L" ? 1 : -1, ref = mesh.id[reach.bone] ?? 0
        var o = SIMD3(reach.at.x * sign, reach.at.y, reach.at.z)
        if let flank = reach.flank { o.x += sign * (flank == .hip ? shape.hipWidth : shape.waistWidth) }
        return (m[ref].apply(shape.joints[ref] + o), m[ref].r.apply(SIMD3(reach.pole.x * sign, reach.pole.y, reach.pole.z)))
    }

    /// Two-bone IK: shoulder to elbow to wrist, the hand reaching a target, the elbow toward a pole.
    private static func reach(_ shape: BodyShape, _ mesh: BodyMesh, _ m: [Affine], side: String, _ goal: (from: Reach, to: Reach, k: Float)) -> (upper: Mat3, lower: Mat3)? {
        guard let iu = mesh.id["upperarm.\(side)"], let il = mesh.id["lowerarm.\(side)"], let ih = mesh.id["hand.\(side)"] else { return nil }
        let parent = mesh.bones[iu].parent
        let u0 = shape.joints[il] - shape.joints[iu], f0 = shape.joints[ih] - shape.joints[il], l1 = length(u0), l2 = length(f0)
        let a = aim(shape, mesh, m, side: side, goal.from), b = aim(shape, mesh, m, side: side, goal.to)
        let target = a.target + (b.target - a.target) * goal.k, pole = a.pole + (b.pole - a.pole) * goal.k
        let s = m[parent].apply(shape.joints[iu]), toward = target - s, dir = unit(toward)
        let d = min(max(length(toward), abs(l1 - l2) + 0.05), l1 + l2 - 0.02)
        let along = (l1 * l1 - l2 * l2 + d * d) / (2 * d), up = max(l1 * l1 - along * along, 0).squareRoot()
        let side3 = unit(pole - dir * (pole * dir).sum())
        let elbow = s + dir * along + side3 * up, wrist = elbow + unit(s + dir * d - elbow) * l2
        let gu = between(u0, elbow - s), gl = between(gu.apply(f0), wrist - elbow) * gu
        return (m[parent].r.transposed * gu, gu.transposed * gl)
    }

    /// Forward kinematics: one transform per bone; each turns about its own head at rest.
    static func pose(_ shape: BodyShape, _ mesh: BodyMesh, _ pose: Pose) -> [Affine] {
        var m = [Affine](repeating: .identity, count: mesh.bones.count)
        var lower: [String: Mat3] = [:]
        for (i, bone) in mesh.bones.enumerated() {
            let side = String(bone.name.suffix(1))
            var r: Mat3
            if bone.name.hasPrefix("upperarm"), let goal = pose.arms[side], let solved = reach(shape, mesh, m, side: side, goal) {
                r = solved.upper
                lower[side] = solved.lower
            } else if bone.name.hasPrefix("lowerarm"), let solved = lower[side] {
                r = solved
            } else {
                r = rotation(pose.angles[bone.name] ?? SIMD3(0, 0, 0))
            }
            let h = shape.joints[i], local = Affine(r: r, t: h - r.apply(h))
            m[i] = (bone.parent >= 0 ? m[bone.parent] : Affine(r: .identity, t: pose.offset)).then(local)
        }
        return m
    }

    /// Skinning: positions and normals by the four bones of each vertex, then clothes standing off
    /// the skin and the fat's swing.
    static func skin(_ shape: BodyShape, _ mesh: BodyMesh, _ m: [Affine], puff: [Float]?, swing: SIMD3<Float>?, positions: UnsafeMutablePointer<Float>, normals: UnsafeMutablePointer<Float>) {
        // Twice a frame for every vertex, so everything is read through raw buffers: no copies,
        // no reference counting inside the loop.
        let swing = shape.jiggle.isEmpty ? nil : swing
        let none: [Float] = []
        m.withUnsafeBufferPointer { mats in
            shape.rest.withUnsafeBufferPointer { rest in
                shape.normals.withUnsafeBufferPointer { n0 in
                    mesh.boneIndex.withUnsafeBufferPointer { bones in
                        mesh.boneWeight.withUnsafeBufferPointer { weights in
                            (puff ?? none).withUnsafeBufferPointer { puffs in
                                shape.jiggle.withUnsafeBufferPointer { jiggle in
                                    for v in 0..<mesh.count {
                                        let p = SIMD3(rest[v * 3], rest[v * 3 + 1], rest[v * 3 + 2]), n = SIMD3(n0[v * 3], n0[v * 3 + 1], n0[v * 3 + 2])
                                        var pos = SIMD3<Float>(0, 0, 0), nrm = SIMD3<Float>(0, 0, 0)
                                        for k in 0..<4 {
                                            let w = weights[v * 4 + k]
                                            guard w > 0 else { continue }
                                            let f = Float(w) / 255, a = mats[Int(bones[v * 4 + k])]
                                            pos += f * (a.r.apply(p) + a.t)
                                            nrm += f * a.r.apply(n)
                                        }
                                        nrm = unit(nrm)
                                        if !puffs.isEmpty { pos += nrm * puffs[v] }
                                        if let swing { pos += swing * jiggle[v] }
                                        positions[v * 3] = pos.x; positions[v * 3 + 1] = pos.y; positions[v * 3 + 2] = pos.z
                                        normals[v * 3] = nrm.x; normals[v * 3 + 1] = nrm.y; normals[v * 3 + 2] = nrm.z
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// How far clothes stand off the skin: a tee about 1 cm, jeans a little less; underwear none.
    static func puffs(_ mesh: BodyMesh, sex: Sex) -> [Float] {
        let band = mesh.band[sex] ?? [], armT = mesh.armT[sex] ?? []
        func step(_ a: Float, _ b: Float, _ x: Float) -> Float { let t = min(max((x - a) / (b - a), 0), 1); return t * t * (3 - 2 * t) }
        return (0..<mesh.count).map { v in
            let torso = step(0.525, 0.545, band[v]) * (1 - step(0.825, 0.845, band[v])) * (1 - mesh.arm[v]) * (1 - mesh.head[v])
            let sleeve: Float = armT[v] > -0.75 ? 1 - step(0.4, 0.46, armT[v]) : 0
            let jeans = step(0.03, 0.05, band[v]) * (1 - step(0.545, 0.56, band[v])) * (1 - mesh.arm[v])
            return max(torso, sleeve) * 0.1 + jeans * 0.06
        }
    }

    /// Colours, linear: skin in its tone with a faint mottle and a touch of warmth over bone, eyes
    /// looking ahead; or the fat under the skin as a map, thin in deep red to thick in yellow.
    static func colours(_ shape: BodyShape, _ mesh: BodyMesh, tone: UInt32, fatMap: Bool) -> [Float] {
        func linear(_ hex: UInt32) -> SIMD3<Float> {
            SIMD3(pow(Float((hex >> 16) & 255) / 255, 2.2), pow(Float((hex >> 8) & 255) / 255, 2.2), pow(Float(hex & 255) / 255, 2.2))
        }
        let skin = linear(tone), sclera = linear(0xE6E0D6), iris = linear(0x463224), pupil = linear(0x0C0A09)
        let ramp: [SIMD3<Float>] = [0x6E1A14, 0xB3301F, 0xE2672B, 0xF4AD3B, 0xFFE28E].map(linear)
        let p = shape.rest
        var centres: [UInt8: (SIMD3<Float>, Float)] = [:]
        for v in 0..<mesh.count where mesh.eye[v] > 0 {
            let c = centres[mesh.eye[v]] ?? (SIMD3(0, 0, 0), 0)
            centres[mesh.eye[v]] = (c.0 + SIMD3(p[v * 3], p[v * 3 + 1], p[v * 3 + 2]), c.1 + 1)
        }
        var out = [Float](repeating: 0, count: mesh.count * 3)
        for v in 0..<mesh.count {
            var c: SIMD3<Float>
            if fatMap, !shape.fat.isEmpty {
                let x = min(shape.fat[v] / 0.55, 1) * Float(ramp.count - 1), i = min(Int(x), ramp.count - 2)
                c = ramp[i] + (ramp[i + 1] - ramp[i]) * (x - Float(i))
            } else if mesh.eye[v] > 0, let centre = centres[mesh.eye[v]] {
                let d = SIMD3(p[v * 3], p[v * 3 + 1], p[v * 3 + 2]) - centre.0 / centre.1, z = d.z / max(length(d), 1e-6)
                c = z > 0.955 ? pupil : z > 0.86 ? iris : sclera
            } else {
                let mottle = sin(p[v * 3] * 3.1 + p[v * 3 + 1] * 1.7) * sin(p[v * 3 + 2] * 2.3 - p[v * 3 + 1] * 2.9), warm = mesh.still[v] * 0.05
                c = skin * SIMD3(1 + 0.035 * mottle + warm, 1 + 0.035 * mottle - warm * 0.6, 1 + 0.035 * mottle - warm)
            }
            out[v * 3] = c.x; out[v * 3 + 1] = c.y; out[v * 3 + 2] = c.z
        }
        return out
    }
}

/// Fat that moves: a damped spring trails the chest, and each vertex follows it by its fat.
struct Jiggle {
    private var offset = SIMD3<Float>(0, 0, 0)
    private var velocity = SIMD3<Float>(0, 0, 0)
    private var last: SIMD3<Float>?
    private var before: SIMD3<Float>?

    mutating func step(anchor p: SIMD3<Float>, dt: Float) -> SIMD3<Float> {
        if let last, let before, dt > 0 {
            let acceleration = (p - 2 * last + before) / (dt * dt)
            velocity += (-260 * offset - 7 * velocity - 0.9 * acceleration) * dt
            offset = simd3Clamp(offset + velocity * dt, 0.22)
        }
        before = last
        last = p
        return offset
    }

    private func simd3Clamp(_ v: SIMD3<Float>, _ m: Float) -> SIMD3<Float> {
        SIMD3(min(max(v.x, -m), m), min(max(v.y, -m), m), min(max(v.z, -m), m))
    }
}
