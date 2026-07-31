/**
 
 ## Extensions
 
 Achraf Kassioui
 Created 20 Nov 2025
 Updated 4 Jan 2026
 
 */
import UIKit

// MARK: CGSize

extension CGSize {
    /// Returns a CGRect centered at the origin.
    func centeredRect() -> CGRect {
        CGRect(origin: CGPoint(x: -width / 2, y: -height / 2), size: self)
    }
    
    /// Resizes both width and height by a fixed delta.
    func resizeBy(_ amount: CGFloat) -> CGSize {
        CGSize(width: width + amount, height: height + amount)
    }
}

// MARK: Colors

extension UIColor {
    /// Converts UIColor to MTLClearColor for Metal rendering
    var metalClearColor: MTLClearColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        
        /// Try RGB color space first
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return MTLClearColor(red: Double(red), green: Double(green), blue: Double(blue), alpha: Double(alpha))
        }
        
        /// Fall back to grayscale (handles .darkGray, .lightGray, etc.)
        var white: CGFloat = 0
        if self.getWhite(&white, alpha: &alpha) {
            return MTLClearColor(red: Double(white), green: Double(white), blue: Double(white), alpha: Double(alpha))
        }
        
        /// Default to black if conversion fails
        return MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    }
}
