//
//  LoadState.swift
//  RollCall
//
//  The three states every screen that downloads something can be in.
//

import Foundation

enum LoadState<Value> {
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}
