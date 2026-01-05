/**
 
 ## Scene
 
 The SpriteKit scene used for SKView and offline rendering with SKRenderer.
 
 Achraf Kassioui
 Created 26 Nov 2025
 Updated 5 Jan 2026
 
 */
import SpriteKit

// MARK: Image Filters

enum CoreImageFilter: String, CaseIterable, Identifiable {
    case none = "No Filter"
    case gaussianBlur = "Gaussian Blur"
    case pixellate = "Pixellate"
    case sepiaTone = "Sepia Tone"
    case bloom = "Bloom"
    case vignette = "Vignette"
    
    var id: String {
        self.rawValue
    }
    
    func resolveFilter() -> CIFilter? {
        switch self {
        case .none: return nil
        case .gaussianBlur:
            let filter = CIFilter.gaussianBlur()
            filter.radius = 10
            return filter
        case .pixellate:
            let filter = CIFilter.pixellate()
            filter.scale = 10
            return filter
        case .sepiaTone:
            return CIFilter.sepiaTone()
        case .bloom:
            let filter = CIFilter.bloom()
            filter.intensity = 0.5
            filter.radius = 10
            return filter
        case .vignette:
            let filter = CIFilter.vignette()
            filter.intensity = 1.0
            filter.radius = 1.0
            return filter
        }
    }
}

// MARK: BitMasks

struct BitMasks: OptionSet {
    let rawValue: UInt32
    
    static let body1 = BitMasks(rawValue: 1 << 0)
    static let body2 = BitMasks(rawValue: 1 << 1)
    
    static let field1 = BitMasks(rawValue: 1 << 2)
    
    static let none = BitMasks([])
    static let all = BitMasks(rawValue: UInt32.max)
}

// MARK: Scene

class SKRenderScene: SKScene, SKPhysicsContactDelegate {
    
    var imagefilter: CoreImageFilter
    private(set) var deltaTime: TimeInterval = 0
    
    private var lastUpdateTime: TimeInterval = 0
    private let scaleFactor: CGFloat
    private var feedback = UIImpactFeedbackGenerator()
    
    // MARK: Init
    
    /// Setup must be done in `init` or `sceneDidLoad` since SKRenderer doesn't call `didMove(to view)`
    init(size: CGSize, scaleFactor: CGFloat, imageFilter: CoreImageFilter) {
        self.scaleFactor = scaleFactor
        self.imagefilter = imageFilter
        
        super.init(size: size)
        
        self.scaleMode = .aspectFit
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.backgroundColor = .darkGray
        self.physicsWorld.contactDelegate = self
        self.physicsWorld.speed = 1
        
        /// Apply CoreImage filter if provided
        if imagefilter != .none {
            self.shouldEnableEffects = true
            self.filter = imageFilter.resolveFilter()
        }
        
        createContent()
        
        /// Control when bouncing balls are created, for physics determinism tests
        let sequence1 = SKAction.sequence([
            .wait(forDuration: 0),
            .run { [weak self] in
                self?.createBouncingBalls()
            }
        ])
        
        run(sequence1)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: didMove
    
    override func didMove(to view: SKView) {
        /// Better looking during device orientation change
        view.contentMode = .center
        /// When presented by SKView, we want the scene to fill the screen
        scaleMode = .resizeFill
        
        feedback = UIImpactFeedbackGenerator(view: view)
        feedback.prepare()
    }
    
    func applyFilter(_ imageFilter: CoreImageFilter) {
        let filterToApply = imageFilter.resolveFilter()
        if filterToApply == nil {
            shouldEnableEffects = false
        } else {
            shouldEnableEffects = true
            filter = filterToApply
        }
    }
    
    // MARK: Content
    
    private func createBouncingBalls() {
        /// Bouncing balls
        /// Test physics determinsim. Collisions and friction stress test physics predictability run after run
        let circleCount = 5
        let spacing: CGFloat = 60
        let totalWidth = CGFloat(circleCount - 1) * spacing
        let startX = -totalWidth / 2
        
        for i in 0..<circleCount {
            let circle = SKShapeNode(circleOfRadius: 18 * scaleFactor)
            circle.fillColor = .orange
            circle.lineWidth = 2 * scaleFactor
            circle.strokeColor = .black
            circle.setScale(1/scaleFactor)
            
            circle.physicsBody = SKPhysicsBody(circleOfRadius: 18)
            circle.physicsBody?.collisionBitMask = BitMasks.body1.rawValue
            circle.physicsBody?.contactTestBitMask = BitMasks.body1.rawValue
            circle.physicsBody?.fieldBitMask = BitMasks.none.rawValue
            /// Toggle these lines to test determinism
            circle.physicsBody?.restitution = 1
            circle.physicsBody?.linearDamping = 0
            let x = startX + CGFloat(i) * spacing
            circle.position = CGPoint(x: x, y: 150)
            addChild(circle)
        }
    }
    
    private func createContent() {
        /// Physical border
        /// With SKRenderer, SKShapeNodes with antialiasing appear blurry when output resolution is more than @1x (but render sharp in SKView)
        /// Solution: supersampling. Create shapes at @x size, then scale down by @x
        let frameSize = CGSize(width: 390, height: 844)
        let frame = SKShapeNode(rectOf: CGSize(width: frameSize.width * scaleFactor, height: frameSize.height * scaleFactor))
        frame.lineWidth = 1 * scaleFactor
        frame.strokeColor = .black
        frame.setScale(1/scaleFactor)
        /// Physics body must match the final scaled size, not the supersampled size
        frame.physicsBody = SKPhysicsBody(edgeLoopFrom: frameSize.centeredRect())
        addChild(frame)
        
        /// Shape animated with SKAction
        let rectangleSize = CGSize(width: 150, height: 75)
        let roundedRectangle = SKShapeNode(rectOf: CGSize(width: rectangleSize.width * scaleFactor, height: rectangleSize.height * scaleFactor), cornerRadius: 12 * scaleFactor)
        roundedRectangle.fillColor = .systemRed
        roundedRectangle.strokeColor = .black
        roundedRectangle.lineWidth = 3 * scaleFactor
        roundedRectangle.setScale(1/scaleFactor) /// Scale back to intended size
        
        roundedRectangle.physicsBody = SKPhysicsBody(rectangleOf: rectangleSize)
        roundedRectangle.physicsBody?.isDynamic = false
        roundedRectangle.physicsBody?.categoryBitMask = BitMasks.body2.rawValue
        roundedRectangle.physicsBody?.collisionBitMask = BitMasks.body2.rawValue
        addChild(roundedRectangle)
        
        let action = SKAction.rotate(byAngle: .pi, duration: 1)
        roundedRectangle.run(.repeatForever(action))
        
        /// Ground sprite
        let ground = SKSpriteNode(color: .black, size: CGSize(width: 350, height: 10))
        ground.physicsBody = SKPhysicsBody(rectangleOf: ground.size)
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.restitution = 1
        ground.physicsBody?.categoryBitMask = BitMasks.body1.rawValue
        ground.physicsBody?.collisionBitMask = BitMasks.body1.rawValue
        ground.position = CGPoint(x: 0, y: -100)
        addChild(ground)
        
        /// Text node
        let label = SKLabelNode(text: "SKRenderer")
        label.fontName = "Menlo-Bold"
        label.fontColor = .systemYellow
        label.position = CGPoint(x: 0, y: 300)
        label.verticalAlignmentMode = .center
        addChild(label)
        
        /// Programmatically generated textures must be scaled by scaleFactor for more than @1x rendering
        let textureSize = CGSize(width: 2 * scaleFactor, height: 2 * scaleFactor)
        let cgRenderer = UIGraphicsImageRenderer(size: textureSize)
        let particleTexture = SKTexture(image: cgRenderer.image { context in
            SKColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: textureSize))
        })
        
        /// Particle emitter with programmatic texture
        let emitter = SKEmitterNode()
        emitter.particleTexture = particleTexture
        emitter.particleScale = 1 / scaleFactor
        emitter.particlePositionRange = CGVector(dx: label.calculateAccumulatedFrame().width, dy: label.calculateAccumulatedFrame().height)
        emitter.particleScaleSpeed = -0.2
        emitter.particleBirthRate = 3000
        emitter.particleLifetime = 6.0
        emitter.particleColor = .systemYellow
        emitter.particleColorBlendFactor = 1.0
        emitter.particleSpeed = 100
        emitter.particleSpeedRange = 100
        emitter.emissionAngle = -.pi / 2
        emitter.particleAlpha = 0.4
        emitter.particleAlphaSpeed = -0
        emitter.particleBlendMode = .add
        emitter.position = CGPoint(x: 0, y: 300)
        emitter.fieldBitMask = BitMasks.field1.rawValue
        addChild(emitter)
        
        /// Turbulence field affecting particles
        /// Physics fields use a different engine than physics bodies, are SIMD based, and appear to be deterministic
        /// They are not affected by physicsWorld.speed
        let field = SKFieldNode.noiseField(withSmoothness: 1, animationSpeed: 1)
        field.strength = 1
        field.categoryBitMask = BitMasks.field1.rawValue
        addChild(field)
    }
    
    // MARK: Physics Contacts
    
    func didBegin(_ contact: SKPhysicsContact) {
        //feedback.impactOccurred(intensity: 0.5)
    }
    
    // MARK: Loop
    
    override func update(_ currentTime: TimeInterval) {
        /// First frame, initialize delta time
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        
        /// Calculate delta time
        deltaTime = currentTime - lastUpdateTime
        
        /// Store for next frame
        lastUpdateTime = currentTime
        
        /// During offline rendering, even if we supply a fixed timestep, we get alternating
        /// delta time values because we are adding 1/60 each time (floating point precision)
        //print(deltaTime)
        /*
         0.016666666720993817
         0.016666666604578495
         0.016666666720993817
         0.016666666604578495
         0.016666666720993817
         0.016666666720993817
         0.016666666604578495
         0.016666666720993817
         */
    }
    
}
