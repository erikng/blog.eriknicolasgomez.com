//
//  ContentView.swift
//  DSUI4MAPT2
//
//  Created by Erik Gomez on 6/14/21.
//

import SwiftUI

class ViewState: ObservableObject {
    @Published var buttonState = 0
}

struct ContentView: View {
    @StateObject var viewState = ViewState()
    var body: some View {
        HStack {
            LeftView(viewObserved: viewState)
            CenterView(viewObserved: viewState)
            RightView(viewObserved: viewState)
        }
        .frame(width: 400, height: 200)
    }
}

struct LeftView: View {
    @ObservedObject var viewObserved: ViewState
    var body: some View {
        ZStack {
            Color.red
            Text(String(viewObserved.buttonState))
        }
    }
}

struct CenterView: View {
    @ObservedObject var viewObserved: ViewState
    var body: some View {
        ZStack {
            Color.green
            Button {
                viewObserved.buttonState += 1
                print(viewObserved.buttonState)
            } label: {
                Text("Increase value")
            }
        }
    }
}

struct RightView: View {
    @ObservedObject var viewObserved: ViewState
    var body: some View {
        ZStack {
            Color.blue
            Button {
                viewObserved.buttonState -= 1
                print(viewObserved.buttonState)
            } label: {
                Text("Decreate value")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
