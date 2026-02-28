//
//  SendState.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

enum SendState: Equatable {
    case idle
    case sending
    case sent
    case failed(String)
    case unavailable(String)
}
