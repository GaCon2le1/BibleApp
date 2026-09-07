//
//  ContentView.swift
//  BibleApp
//
//  Created by Gacon on 7/9/26.
//

import SwiftUI
import BibleFeedKit

struct ContentView: View {
    @State private var store = ContentStore()

    var body: some View {
        VStack(spacing: 8) {
            Text("\(store.verses.count) verses loaded")
                .font(.headline)
            if let first = store.verses.first {
                Text(first.reference).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { store.load() }
    }
}

#Preview {
    ContentView()
}
