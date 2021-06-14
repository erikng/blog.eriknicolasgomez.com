//
//  ContentView.swift
//  DSUI4MAPT1
//
//  Created by Erik Gomez on 6/13/21.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            HeroSubImageView(font: .title2, imageHeight: 35, imageWidth: 35, xOffset: -65, yOffSet: 0, symbolName: "person.crop.circle.badge.checkmark", zIndex: -2)
            HeroSubImageView(font: .title, imageHeight: 40, imageWidth: 40, xOffset: -35, yOffSet: -20, symbolName: "tray.full.fill", zIndex: -1)
            HeroSubImageView(font: .largeTitle, imageHeight: 45, imageWidth: 45, xOffset: 0, yOffSet: 0, symbolName: "checkmark.seal.fill", zIndex: 0)
            HeroSubImageView(font: .largeTitle, imageHeight: 45, imageWidth: 45, xOffset: 35, yOffSet: -20, symbolName: "link.circle.fill", zIndex: -1)
            HeroSubImageView(font: .title, imageHeight: 40, imageWidth: 40, xOffset: 65, yOffSet: 0, symbolName: "arrow.down.doc.fill", zIndex: -2)
            HeroSubImageView(font: .title2, imageHeight: 35, imageWidth: 35, xOffset: 95, yOffSet: -20, symbolName: "folder.fill", zIndex: -3)
        }
        .frame(width: 300, height: 150)
    }
}

struct HeroSubImageView: View {
    var font: Font
    var imageHeight, imageWidth, xOffset, yOffSet: CGFloat
    var symbolName: String
    var zIndex: Double
    
    var body: some View {
        Image(systemName: symbolName)
            .font(font)
            .foregroundColor(.accentColor)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .frame(width: imageWidth, height: imageHeight)
                    .foregroundColor(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.blue, lineWidth: 3)
                    .opacity(0.4)
                    .frame(width: imageWidth, height: imageHeight)
            )
            .offset(x: xOffset, y: yOffSet)
            .zIndex(zIndex)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
