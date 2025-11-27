# SKRenderer Demo
*26 Nov 2025*

This sample app demonstrates how to use SKRenderer to render and save a SpriteKit simulation to disk.

## Demo

https://github.com/user-attachments/assets/0dd271a7-6df9-4ba3-bf91-d8e65a187bda

## Overview

The overall structure is as follows:

- A SpriteKit scene contains all the content and behaviors.
- The scene is supplied to SKRenderer instead of, or in addition to, being presented by SKView/SpriteView.
- SKRenderer renders the SpriteKit scene into a Metal texture.
- When GPU finishes drawing a frame, it calls back to the CPU which retrieves the Metal texture, converts it to CGImage, then encodes it as PNG.
- Each frame can take as long as needed since we're not syncing to a display refresh rate.
- Images are stored to disk in a folder inside the app container. The full path is printed to console for retrieval.

## Rendering Setup

SKRenderer works with Metal. The high level architecture of a Metal pipeline is:

- A Metal renderer draws into a texture, where a texture is a block of memory on the GPU.
- If the renderer is tied to a view, the view supplies the texture and presents it to the display each frame, synchronized with the screen's refresh rate.
- If the renderer runs offscreen, the app itself allocates a texture in GPU memory, and retrieves its contents once the GPU finishes rendering.

SpriteKit’s offline rendering with SKRenderer uses this last mode. Below is the boilerplate setup done **once** when SKRenderer is created:

```swift
// Get the GPU

let device = MTLCreateSystemDefaultDevice()

// Factory for creating command buffers, used later each frame
// Command buffers = instructions for the GPU

let commandQueue = device.makeCommandQueue()

// Allocate GPU memory for the texture we'll render into
// Texture = a block of GPU memory holding pixels
// The memory allocation stays constant (let), the pixel data changes each frame

let textureDesc = MTLTextureDescriptor()
textureDesc.width = pixelWidth
textureDesc.height = pixelHeight
let renderTexture = device.makeTexture(descriptor: textureDesc)

// Create an SKRenderer instance and assign a scene to render

let renderer = SKRenderer(device: device)
renderer.scene = scene
```

Then for **each frame**, we run code in the following form:

```swift
// Update scene
// This calls all SKScene delegate functions, from update to didFinishUpdate

renderer.update(atTime: currentTime)

// Configure the rendering operation for this frame
// Links the texture as the render target and specifies clear/store actions

let renderPassDescriptor = MTLRenderPassDescriptor()
renderPassDescriptor.colorAttachments[0].texture = renderTexture
renderPassDescriptor.colorAttachments[0].loadAction = .clear
renderPassDescriptor.colorAttachments[0].storeAction = .store

// Create a command buffer to hold this frame's GPU instructions

let commandBuffer = commandQueue.makeCommandBuffer()

// Viewport is required by the API but appears ignored by SKRenderer in this context
// The texture dimensions determine the actual output size

let viewport = CGRect(origin: .zero, size: sceneSize)

// Render the scene into the texture
// SKRenderer writes drawing commands into commandBuffer

renderer.render(
    withViewport: viewport,
    commandBuffer: commandBuffer,
    renderPassDescriptor: renderPassDescriptor
)

// Create a callback when GPU finishes a frame

commandBuffer.addCompletedHandler {
    /// Convert texture to CGImage
    textureToImage(renderTexture)
}

// Send the command buffer to GPU for execution

commandBuffer.commit()
```

## Time Management

SKRenderer's `update(atTime:)` expects a system time value, not a delta time. While testing, I found that particles won't render if the time starts at 0 for the first frame. I had to initialize the start time with `CACurrentMediaTime()`, then add a delta for each frame, in order for particles to render correctly.

```swift
// When SKRenderer is created, grab system time

let renderer = SKRenderer(device: device)
let startTime = CACurrentMediaTime()

// For each frame to render, pass the start time + a time offset

for frame in 0..<totalFrames {
    let relativeTime = Double(frame) / fps
    let currentTime = startTime + relativeTime
    renderer.update(atTime: currentTime)
}
```

## Resolution and Scale Factor

A SpriteKit scene is sized in points. A Metal texture is sized in pixels. If a scene is created at 1920x1080 and SKRenderer draws it, the output will be 1920x1080 pixels. In order to get Retina resolution, we must multiply **the size of the allocated texture by a scale factor**. Metal will handle the mapping between the point-based scene and the pixel-based texture. This is reminiscent of a UIView [contentScaleFactor](https://developer.apple.com/documentation/uikit/uiview/contentscalefactor) property.

```swift
let scene = SKScene(size: CGSize(width: 1920, height: 1080))

// Scale allocated texture before rendering

let textureDesc = MTLTextureDescriptor()
textureDesc.width = Int(1920 * renderScale)  // @3x: 5760 pixels
textureDesc.height = Int(1080 * renderScale)  // @3x: 3240 pixels

renderer.render(...)
```

## Known Issues and Workarounds

HiDPI scaling doesn't work for all nodes. SKShapeNodes with antialiasing enabled render at @1x no matter the resolution of the Metal texture descriptor, and therefore will appear blurry. A workaround is to use supersampling: create shapes upsized by the scale factor, then scale down:

```swift
let scaleFactor: CGFloat = 3 // iPhone scale factor

let shape = SKShapeNode(rectOf: CGSize(width: 150 * scaleFactor, height: 75 * scaleFactor))
shape.lineWidth = 3 * scaleFactor
shape.setScale(1/scaleFactor)

// Physics body must match final size, not supersampled size

shape.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 150, height: 75))
```

An alternative is to set `isAntialiased = false` on shape nodes, which will force SKRenderer to draw them at the correct resolution, but curves will appear jagged.

Textures created programmatically should be scaled to match the render scale as well. Pass the scale factor to the scene initializer and scale texture creation accordingly:
```swift
let textureSize = CGSize(width: 2 * scaleFactor, height: 2 * scaleFactor)

// Generate a texture with Core Graphics

let cgRenderer = UIGraphicsImageRenderer(size: textureSize)
let squareTexture = SKTexture(image: cgRenderer.image { context in
    SKColor.white.setFill()
    context.fill(CGRect(origin: .zero, size: textureSize))
})
```

## Use Case: Recording Live Simulations

This setup lets you record a SpriteKit simulation to disk without affecting real-time performance, and makes it possible to apply expensive post-processing offline: filters, compositing, analysis, etc.

In order to record a specific segment of the simulation, the SpriteKit scene must be set up to recover a given state and replay the simulation. Typically this means having a deterministic state initializer + a command pattern on top of SpriteKit:
```swift
// Live interaction mutates the scene by issuing commands:

run(Command.create(..))
run(Command.move(..))

// The same interaction can be reproduced later:

history = [
    Action(time: 1.0, command: .create(...)),
    Action(time: 1.5, command: .move(...)),
    // ...
]
```

A recording pass would be implemented like this:

- Reset the scene to the desired initial state (nodes, transforms, assets…)
- Start the update loop
- At each frame, replay any commands scheduled for that timestamp
- Let SKRenderer render as many frames as needed for the interval
- Save each rendered frame to disk

This enables capturing complex simulations at any resolution and frame rate, fully decoupled from real-time display limits. The resulting frame sequence can then be assembled into a video using AVFoundation.

## Determinism

Interaction and behavior must be deterministic for frame-perfect replay. Consider the figure below: each render is from the same scene, and each image is the 500th frame of a 10 seconds simulation.

<img src="SKRenderer-Demo/Images/SKRenderer-determinism.png" alt="SKRenderer-determinism" style="zoom:50%;" />

From empirical testing, I found the following to be deterministic:

- SKActions and typical code written in update
- Physics fields effects on particles, like turbulence, appear predictable, which was a pleasant surprise! The particles themselves aren't identical from run to run, but the overall behavior is repeatable. Mind you, we can't "teleport" particles into a particular state. If the current state of a particle emitter is the result of an interaction with a field, the simulation must be replayed from the first interaction in order to recover the current state. 

I found the following to not be deterministic, despite the fixed time step of the renderer:

- Colliding physics bodies. We can see that the bouncing balls above are in different positions at similar simulation time.

If your setup depends on precise physics body positions interacting over multiple seconds, use guide rails to direct the behavior, such as careful level design and checkpoints.

## Performance

Example output from rendering 600 frames (10 seconds at 60fps) at @2x on an iPhone 13 (A15 chip):
```
========================================
RENDERING TO: /Documents/SKRender_2025-11-27_16-49-48
Resolution: 390×844 points
Node count: 11
Scale: @2x
Actual pixels: 780×1688
FPS: 60
Frames: 600
Filter: None
========================================

.
..
...

========================================
RENDER COMPLETE
Location: /Documents/SKRender_2025-11-27_16-49-48
Frames: 600
Rendering time: 6.04s (0.010s/frame)
Saving time: 0.02s
Total time: 6.06s (0.010s/frame)
========================================
```

## Code Sample

The app demonstrates:

- Complete Metal rendering setup
- SKShapeNode supersampling workaround
- Async/await pattern for GPU callbacks
- Parallel disk saving
- Support for CoreImage filters
- Resolution and scale factor configuration

Use this as a foundation for building replay systems, automated testing, or video export features in SpriteKit projects.
