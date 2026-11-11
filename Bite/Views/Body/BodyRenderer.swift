import MetalKit
import UIKit
import simd

/// What the bodies wear: underwear, a tee and jeans, or nothing but a map of their fat.
enum BodyOutfit: String, CaseIterable, Identifiable {
    case body, clothes, fat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: tr("Body")
        case .clothes: tr("Clothes")
        case .fat: tr("Fat map")
        }
    }

    var code: Float {
        switch self {
        case .body: 0
        case .clothes: 1
        case .fat: 2
        }
    }
}

/// The skin tones on offer, sRGB, lightest to deepest.
enum BodyTone {
    static let all: [UInt32] = [0xE8C2A4, 0xD5A17C, 0xB07552, 0x7F4E2F, 0x4D2E1C]
}

private struct BodyUniforms {
    var viewProjection: simd_float4x4
    var model: simd_float4x4
    var camera: SIMD4<Float>
    var look: SIMD4<Float>
}

/// What every drawing of a body shares: the device, the two pipelines, the depth states and the
/// buffers that never change. Made once, off the main thread, the first time a body is drawn.
final class BodyGPU {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let body: MTLRenderPipelineState
    let shadow: MTLRenderPipelineState
    let solid: MTLDepthStencilState
    let floor: MTLDepthStencilState
    let indices: MTLBuffer
    let cloth: [Sex: MTLBuffer]
    let mesh: BodyMesh
    static let pixelFormat = MTLPixelFormat.bgra8Unorm
    static let depthFormat = MTLPixelFormat.depth32Float
    static let samples = 4

    init?(mesh: BodyMesh) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: BodyShader.source, options: nil) else { return nil }
        func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.rasterSampleCount = BodyGPU.samples
            d.depthAttachmentPixelFormat = BodyGPU.depthFormat
            let color = d.colorAttachments[0]!
            color.pixelFormat = BodyGPU.pixelFormat
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: d)
        }
        func depth(write: Bool) -> MTLDepthStencilState? {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = .less
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)
        }
        guard let body = pipeline("bodyVertex", "bodyFragment"), let shadow = pipeline("shadowVertex", "shadowFragment"),
              let solid = depth(write: true), let floor = depth(write: false),
              let indices = mesh.indices.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }) else { return nil }
        var cloth: [Sex: MTLBuffer] = [:]
        for sex in [Sex.male, .female] {
            let band = mesh.band[sex] ?? [], along = mesh.armT[sex] ?? []
            guard band.count == mesh.count, along.count == mesh.count else { return nil }
            var values = [Float](repeating: 0, count: mesh.count * 4)
            for v in 0..<mesh.count {
                values[v * 4] = band[v]
                values[v * 4 + 1] = along[v]
                values[v * 4 + 2] = mesh.arm[v]
                values[v * 4 + 3] = mesh.head[v]
            }
            cloth[sex] = values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) }
        }
        self.device = device
        self.queue = queue
        self.body = body
        self.shadow = shadow
        self.solid = solid
        self.floor = floor
        self.indices = indices
        self.cloth = cloth
        self.mesh = mesh
    }

    /// Nil where there is no Metal or no body in the bundle: the screen then draws flat figures.
    static let shared: BodyGPU? = BodyMesh.shared.flatMap { BodyGPU(mesh: $0) }

    func buffer(floats count: Int) -> MTLBuffer? {
        device.makeBuffer(length: count * MemoryLayout<Float>.stride, options: .storageModeShared)
    }

    func buffer(_ values: [Float]) -> MTLBuffer? {
        values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }

    /// The camera every body is framed by, so their sizes compare: the whole height with some
    /// air, and enough width for the widest pose.
    func camera(aspect: Float, fill: Float = 1.24, width: Float = 0.56) -> (viewProjection: simd_float4x4, eye: SIMD3<Float>) {
        let fov: Float = 16 * .pi / 180, fit = mesh.span * fill
        let need = max(fit / 2, fit * width / 2 / aspect), distance = need / tan(fov / 2)
        let y = mesh.mid + mesh.span * 0.02, eye = SIMD3<Float>(0, y, distance)
        return (Self.perspective(fov: fov, aspect: aspect, near: 1, far: 400) * Self.lookAt(eye: eye, center: SIMD3(0, y, 0)), eye)
    }

    static func perspective(fov: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let y = 1 / tan(fov / 2), x = y / aspect, z = far / (near - far)
        return simd_float4x4(columns: (SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, z, -1), SIMD4(0, 0, z * near, 0)))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye), s = simd_normalize(simd_cross(f, SIMD3(0, 1, 0))), u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0), SIMD4(s.y, u.y, -f.y, 0), SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }

    static func turn(_ degrees: Float) -> simd_float4x4 {
        let a = degrees * .pi / 180, c = cos(a), s = sin(a)
        return simd_float4x4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }

    /// One body into an encoder: its shadow on the floor, then itself.
    fileprivate func encode(_ encoder: MTLRenderCommandEncoder, uniforms: inout BodyUniforms, positions: MTLBuffer, normals: MTLBuffer, colors: MTLBuffer, sex: Sex) {
        var place = SIMD4<Float>(mesh.span * 0.18, mesh.span * 0.065, mesh.feet + 0.02, 0)
        encoder.setRenderPipelineState(shadow)
        encoder.setDepthStencilState(floor)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<BodyUniforms>.stride, index: 4)
        encoder.setVertexBytes(&place, length: MemoryLayout<SIMD4<Float>>.stride, index: 5)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BodyUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.setRenderPipelineState(body)
        encoder.setDepthStencilState(solid)
        encoder.setVertexBuffer(positions, offset: 0, index: 0)
        encoder.setVertexBuffer(normals, offset: 0, index: 1)
        encoder.setVertexBuffer(colors, offset: 0, index: 2)
        encoder.setVertexBuffer(cloth[sex], offset: 0, index: 3)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<BodyUniforms>.stride, index: 4)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BodyUniforms>.stride, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indices.count, indexType: .uint16, indexBuffer: indices, indexBufferOffset: 0)
    }
}

/// The live stage: now on the left half, goal on the right, posed by one director, each with fat
/// that swings. Three frames in flight, each with its own vertex buffers, so the CPU never writes
/// what the GPU is still reading.
final class BodyStageRenderer: NSObject, MTKViewDelegate {
    private struct Doll {
        let shape: BodyShape
        var colors: MTLBuffer
        let positions: [MTLBuffer]
        let normals: [MTLBuffer]
        var jiggle = Jiggle()
    }

    let gpu: BodyGPU
    let director = BodyMotion.Director()
    /// Where the bodies face, in degrees, and where they are turning to.
    private(set) var yaw: Float = 0
    private var target: Float = 0
    var outfit: BodyOutfit = .body { didSet { if outfit != oldValue { recolour() } } }
    var tone: UInt32 = BodyTone.all[1] { didSet { if tone != oldValue { recolour() } } }
    /// Reduce Motion: one pose held, drawn only when something changes.
    var still = false
    private var dolls: [Doll?] = [nil, nil]
    private var puffs: [Sex: [Float]] = [:]
    private var ring = 0
    private let inFlight = DispatchSemaphore(value: 3)
    private var last: CFTimeInterval = 0
    private let start = CACurrentMediaTime()

    init(gpu: BodyGPU) {
        self.gpu = gpu
    }

    var isEmpty: Bool { !dolls.contains { $0 != nil } }

    func set(_ shape: BodyShape, at index: Int) {
        let n = gpu.mesh.count * 3
        guard dolls.indices.contains(index), let colors = gpu.buffer(Rig.colours(shape, gpu.mesh, tone: tone, fatMap: outfit == .fat)) else { return }
        let positions = (0..<3).compactMap { _ in gpu.buffer(floats: n) }, normals = (0..<3).compactMap { _ in gpu.buffer(floats: n) }
        guard positions.count == 3, normals.count == 3 else { return }
        // A new shape keeps the old one's swing, so changing a number never jolts the fat.
        dolls[index] = Doll(shape: shape, colors: colors, positions: positions, normals: normals, jiggle: dolls[index]?.jiggle ?? Jiggle())
    }

    /// Turning under a finger follows it exactly; a reset eases back to the front.
    func turn(to degrees: Float, eased: Bool) {
        target = degrees
        if !eased || still { yaw = degrees }
    }

    private func recolour() {
        // New buffers rather than writing over ones a frame in flight may still be reading.
        for i in dolls.indices {
            guard let doll = dolls[i], let colors = gpu.buffer(Rig.colours(doll.shape, gpu.mesh, tone: tone, fatMap: outfit == .fat)) else { continue }
            dolls[i]?.colors = colors
        }
    }

    private func puff(for sex: Sex) -> [Float]? {
        guard outfit == .clothes else { return nil }
        if let known = puffs[sex] { return known }
        let made = Rig.puffs(gpu.mesh, sex: sex)
        puffs[sex] = made
        return made
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !isEmpty else { return }
        inFlight.wait()
        let now = CACurrentMediaTime(), t = now - start, dt = Float(last > 0 && !still ? min(now - last, 0.05) : 0)
        last = now
        ring = (ring + 1) % 3
        if !still { yaw += (target - yaw) * min(1, dt * 9) }
        let pose = still ? BodyMotion.held(director.move) : director.pose(at: t)
        let mesh = gpu.mesh, chest = mesh.id["chest"] ?? 0
        for i in dolls.indices {
            guard var doll = dolls[i] else { continue }
            let m = Rig.pose(doll.shape, mesh, pose)
            let swing = doll.jiggle.step(anchor: m[chest].apply(doll.shape.joints[chest]), dt: dt)
            Rig.skin(doll.shape, mesh, m, puff: puff(for: doll.shape.sex), swing: still ? nil : swing,
                     positions: doll.positions[ring].contents().assumingMemoryBound(to: Float.self),
                     normals: doll.normals[ring].contents().assumingMemoryBound(to: Float.self))
            dolls[i] = doll
        }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = gpu.queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let size = view.drawableSize, half = size.width / 2
        let camera = gpu.camera(aspect: Float(half / max(size.height, 1)))
        for i in dolls.indices {
            guard let doll = dolls[i] else { continue }
            encoder.setViewport(MTLViewport(originX: Double(i) * half, originY: 0, width: half, height: size.height, znear: 0, zfar: 1))
            var uniforms = BodyUniforms(
                viewProjection: camera.viewProjection, model: BodyGPU.turn(yaw), camera: SIMD4(camera.eye, 0),
                look: SIMD4(outfit.code, doll.shape.sex == .female ? 1 : 0, 1, 0)
            )
            gpu.encode(encoder, uniforms: &uniforms, positions: doll.positions[ring], normals: doll.normals[ring], colors: doll.colors, sex: doll.shape.sex)
        }
        encoder.endEncoding()
        command.present(drawable)
        let semaphore = inFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.commit()
    }
}

/// Still bodies, standing in underwear, drawn into images for the pickers and the chart. One at
/// a time: it reuses its vertex buffers, so callers keep it on one serial queue.
final class BodySnapshotter {
    private let gpu: BodyGPU
    private let positions: MTLBuffer
    private let normals: MTLBuffer

    init?(gpu: BodyGPU) {
        let n = gpu.mesh.count * 3
        guard let positions = gpu.buffer(floats: n), let normals = gpu.buffer(floats: n) else { return nil }
        self.gpu = gpu
        self.positions = positions
        self.normals = normals
    }

    func image(of shape: BodyShape, tone: UInt32, size: CGSize, scale: CGFloat) -> UIImage? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded()), mesh = gpu.mesh
        guard width > 0, height > 0, let colors = gpu.buffer(Rig.colours(shape, mesh, tone: tone, fatMap: false)) else { return nil }
        Rig.skin(shape, mesh, Rig.pose(shape, mesh, BodyMotion.still), puff: nil, swing: nil,
                 positions: positions.contents().assumingMemoryBound(to: Float.self),
                 normals: normals.contents().assumingMemoryBound(to: Float.self))
        func texture(_ format: MTLPixelFormat, samples: Int, usage: MTLTextureUsage) -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            d.textureType = samples > 1 ? .type2DMultisample : .type2D
            d.sampleCount = samples
            d.storageMode = .private
            d.usage = usage
            return gpu.device.makeTexture(descriptor: d)
        }
        guard let msaa = texture(BodyGPU.pixelFormat, samples: BodyGPU.samples, usage: .renderTarget),
              let resolved = texture(BodyGPU.pixelFormat, samples: 1, usage: [.renderTarget, .shaderRead]),
              let depth = texture(BodyGPU.depthFormat, samples: BodyGPU.samples, usage: .renderTarget),
              let readback = gpu.device.makeBuffer(length: width * height * 4, options: .storageModeShared),
              let command = gpu.queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let camera = gpu.camera(aspect: Float(width) / Float(height), fill: 1.08, width: 0.5)
        var uniforms = BodyUniforms(
            viewProjection: camera.viewProjection, model: matrix_identity_float4x4, camera: SIMD4(camera.eye, 0),
            look: SIMD4(0, shape.sex == .female ? 1 : 0, 1, 0)
        )
        gpu.encode(encoder, uniforms: &uniforms, positions: positions, normals: normals, colors: colors, sex: shape.sex)
        encoder.endEncoding()
        guard let blit = command.makeBlitCommandEncoder() else { return nil }
        blit.copy(
            from: resolved, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4
        )
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        let data = Data(bytes: readback.contents(), count: width * height * 4)
        guard let provider = CGDataProvider(data: data as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }
}
